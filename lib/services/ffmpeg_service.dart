import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/statistics.dart';
import 'package:ffmpeg_kit_flutter_new_min/stream_information.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:path_provider/path_provider.dart';

import '../models/conversion_settings.dart';
import '../models/frame_settings.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../ui/widgets/frame_painter.dart';
import 'size_estimator.dart';

/// Resultado de uma conversão bem-sucedida: o arquivo GIF e seus metadados.
class ConversionResult {
  const ConversionResult({
    required this.file,
    required this.bytes,
    required this.width,
    required this.height,
    required this.frames,
    required this.elapsed,
  });

  final File file;
  final int bytes;
  final int width;
  final int height;
  final int frames;
  final Duration elapsed;

  String get formattedSize => SizeEstimate.formatBytes(bytes);
}

/// Erro de uma operação do FFmpeg/FFprobe, com mensagem amigável em
/// português e, opcionalmente, os logs brutos para depuração.
class FfmpegException implements Exception {
  FfmpegException(this.message, {this.logs = ''});

  final String message;
  final String logs;

  @override
  String toString() => 'FfmpegException: $message';
}

/// Envolve o FFmpeg: leitura de metadados, medição de amostra e conversão.
///
/// Toda a montagem de linha de comando vive aqui, para que a calibração e a
/// conversão final usem *exatamente* a mesma cadeia de filtros — é isso que
/// faz a estimativa medida bater com o resultado.
class FfmpegService {
  FfmpegService() {
    // Sem isso a saída do FFmpeg vai para o log do sistema e polui o Logcat.
    FFmpegKitConfig.enableLogCallback((_) {});
  }

  int? _activeSessionId;
  bool _cancelled = false;

  // ------------------------------------------------------------------
  // Metadados
  // ------------------------------------------------------------------

  /// Lê os metadados do vídeo em [path] (dimensões, duração, fps, bitrate,
  /// codec e rotação) usando o FFprobe. Lança [FfmpegException] se o
  /// arquivo não existir, não puder ser lido ou não tiver faixa de vídeo.
  Future<VideoInfo> probe(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FfmpegException('Arquivo não encontrado: $path');
    }

    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    if (info == null) {
      throw FfmpegException(
        'Não foi possível ler este arquivo. Ele pode estar corrompido ou em '
        'um formato não suportado.',
        logs: await session.getAllLogsAsString() ?? '',
      );
    }

    final streams = info.getStreams();
    final video = streams.cast<StreamInformation?>().firstWhere(
      (s) => s?.getType() == 'video',
      orElse: () => null,
    );
    if (video == null) {
      throw FfmpegException('Este arquivo não tem faixa de vídeo.');
    }

    final width = video.getWidth() ?? 0;
    final height = video.getHeight() ?? 0;
    if (width <= 0 || height <= 0) {
      throw FfmpegException('Não foi possível descobrir o tamanho do vídeo.');
    }

    final duration =
        double.tryParse(info.getDuration() ?? '') ?? _durationFrom(video) ?? 0;
    if (duration <= 0) {
      throw FfmpegException('Não foi possível descobrir a duração do vídeo.');
    }

    return VideoInfo(
      path: path,
      fileName: path.split('/').last,
      rawWidth: width,
      rawHeight: height,
      durationSeconds: duration,
      frameRate: _frameRateOf(video),
      bitrateBps: int.tryParse(info.getBitrate() ?? '') ?? 0,
      fileSizeBytes: file.lengthSync(),
      codec: video.getCodec() ?? 'desconhecido',
      rotationDegrees: _rotationOf(video),
    );
  }

  double? _durationFrom(StreamInformation stream) {
    final raw = stream.getAllProperties()?['duration'];
    return raw == null ? null : double.tryParse(raw.toString());
  }

  /// O FFprobe devolve taxa de quadros como fração ("30000/1001").
  double _frameRateOf(StreamInformation stream) {
    final props = stream.getAllProperties() ?? const {};
    for (final key in ['avg_frame_rate', 'r_frame_rate']) {
      final raw = props[key]?.toString();
      if (raw == null || raw.isEmpty) continue;
      final parts = raw.split('/');
      if (parts.length == 2) {
        final num = double.tryParse(parts[0]) ?? 0;
        final den = double.tryParse(parts[1]) ?? 0;
        if (num > 0 && den > 0) return num / den;
      } else {
        final value = double.tryParse(raw);
        if (value != null && value > 0) return value;
      }
    }
    return 30;
  }

  /// A rotação pode vir em `tags.rotate` (arquivos antigos) ou em
  /// `side_data_list` como matriz de exibição (arquivos modernos de celular).
  int _rotationOf(StreamInformation stream) {
    final props = stream.getAllProperties() ?? const {};

    final tags = props['tags'];
    if (tags is Map) {
      final rotate = tags['rotate'];
      final parsed = int.tryParse('$rotate');
      if (parsed != null) return _normalizeRotation(parsed);
    }

    final sideData = props['side_data_list'];
    if (sideData is List) {
      for (final entry in sideData) {
        if (entry is Map && entry['rotation'] != null) {
          final parsed = double.tryParse('${entry['rotation']}');
          if (parsed != null) return _normalizeRotation(parsed.round());
        }
      }
    }
    return 0;
  }

  int _normalizeRotation(int degrees) {
    final normalized = ((degrees % 360) + 360) % 360;
    return normalized;
  }

  // ------------------------------------------------------------------
  // Montagem dos filtros
  // ------------------------------------------------------------------

  /// Cadeia de filtros de vídeo, na única ordem que dá o resultado certo:
  ///
  ///  1. `crop`   — em pixels do vídeo original, então tem que vir primeiro;
  ///  2. `setpts` — muda a velocidade reescrevendo os tempos dos quadros;
  ///  3. `fps`    — reamostra para a taxa final (depois da velocidade, senão
  ///                o cálculo de quadros sai errado);
  ///  4. `scale`  — redimensiona por último, sobre menos pixels possível.
  String buildVideoFilter(ConversionSettings settings, VideoInfo video) {
    final parts = <String>[];

    final crop = settings.crop;
    if (crop != null) {
      parts.add('crop=${crop.width}:${crop.height}:${crop.x}:${crop.y}');
    }

    if (settings.speed != 1.0) {
      parts.add('setpts=PTS/${settings.speed}');
    }

    parts.add('fps=${settings.fps}');

    final (width, height) = settings.contentDimensions(video);
    parts.add('scale=$width:$height:flags=lanczos');

    return parts.join(',');
  }

  /// Grafo de filtro completo pronto para `-lavfi`: [input] (ex.: `0:v`) até
  /// [output], já com a moldura aplicada — conteúdo ([buildVideoFilter])
  /// ajustado à área da moldura conforme [ConversionSettings.frame]'s
  /// modo de ajuste, depois preenchido com a borda até o tamanho final
  /// ([ConversionSettings.outputDimensions]). Só deve ser chamado quando
  /// há moldura ativa (`frame.style != FrameStyle.none`).
  String _framedGraph(
    ConversionSettings settings,
    VideoInfo video, {
    required String input,
    required String output,
  }) {
    final contentFilter = buildVideoFilter(settings, video);
    final frame = settings.frame;

    final (contentWidth, contentHeight) = settings.contentDimensions(video);
    final (areaWidth, areaHeight, thickness) = settings.frameAreaDimensions(
      video,
    );
    final (canvasWidth, canvasHeight) = settings.outputDimensions(video);
    final colorHex = _ffmpegColor(frame.color);
    final thicknessPx = thickness.round();

    final parts = <String>['[$input]$contentFilter[content]'];

    if (contentWidth == areaWidth && contentHeight == areaHeight) {
      parts.add('[content]copy[fitted]');
    } else {
      final fit = _resolveFitMode(
        frame.contentFit,
        contentWidth,
        contentHeight,
        areaWidth,
        areaHeight,
      );
      switch (fit) {
        case ContentFitMode.fill:
          parts.add(
            '[content]scale=$areaWidth:$areaHeight:'
            'force_original_aspect_ratio=increase:flags=lanczos,'
            'crop=$areaWidth:$areaHeight[fitted]',
          );
        case ContentFitMode.expand:
          // Fundo: cobre a área toda e desfoca; primeiro plano: cabe
          // inteiro, sem cortar; um sobre o outro, centralizado.
          parts.add('[content]split=2[bg][fg]');
          parts.add(
            '[bg]scale=$areaWidth:$areaHeight:'
            'force_original_aspect_ratio=increase:flags=lanczos,'
            'crop=$areaWidth:$areaHeight,boxblur=12:3[bg2]',
          );
          parts.add(
            '[fg]scale=$areaWidth:$areaHeight:'
            'force_original_aspect_ratio=decrease:flags=lanczos[fg2]',
          );
          parts.add('[bg2][fg2]overlay=(W-w)/2:(H-h)/2[fitted]');
        case ContentFitMode.auto:
        case ContentFitMode.fit:
          parts.add(
            '[content]scale=$areaWidth:$areaHeight:'
            'force_original_aspect_ratio=decrease:flags=lanczos,'
            'pad=$areaWidth:$areaHeight:(ow-iw)/2:(oh-ih)/2:'
            'color=$colorHex[fitted]',
          );
      }
    }

    parts.add(
      '[fitted]pad=$canvasWidth:$canvasHeight:$thicknessPx:$thicknessPx:'
      'color=$colorHex[$output]',
    );

    return parts.join(';');
  }

  /// Resolve "Ajuste automático" para "Preencher" ou "Encaixar": se a
  /// proporção do conteúdo já está perto da proporção da área (pouco corte
  /// necessário), preenche sem barras; se está muito diferente, encaixa
  /// para não cortar demais.
  ContentFitMode _resolveFitMode(
    ContentFitMode mode,
    int contentWidth,
    int contentHeight,
    int areaWidth,
    int areaHeight,
  ) {
    if (mode != ContentFitMode.auto) return mode;
    final contentAspect = contentWidth / contentHeight;
    final areaAspect = areaWidth / areaHeight;
    final ratio = contentAspect / areaAspect;
    return (ratio >= 0.8 && ratio <= 1.25)
        ? ContentFitMode.fill
        : ContentFitMode.fit;
  }

  /// Cor no formato aceito pelos filtros do FFmpeg (`0xRRGGBB`).
  String _ffmpegColor(Color color) {
    final rgb = (color.toARGB32() & 0x00FFFFFF).toRadixString(16);
    return '0x${rgb.padLeft(6, '0')}';
  }

  /// Monta os argumentos do FFmpeg para a passagem 1: gera o arquivo de
  /// paleta de cores (PNG) a partir do trecho e filtros selecionados. Com
  /// moldura, [maskPath] (PNG branco/preto do formato arredondado, gerado
  /// por [rasterizeCornerMask]) recorta os cantos via `alphamerge` antes de
  /// gerar a paleta — assim a transparência participa da paleta desde já.
  List<String> _paletteGenArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String palettePath,
    String? maskPath,
  }) {
    if (settings.frame.style == FrameStyle.none) {
      final filter = buildVideoFilter(settings, video);
      return [
        '-y',
        '-ss',
        _seconds(settings.startSeconds),
        '-t',
        _seconds(settings.sourceDurationSeconds),
        '-i',
        video.path,
        '-vf',
        '$filter,palettegen=max_colors=${settings.colors}'
            ':stats_mode=${settings.palette.statsMode}',
        '-frames:v',
        '1',
        palettePath,
      ];
    }

    final graph = _framedGraph(settings, video, input: '0:v', output: 'framed');
    final reserve = maskPath != null ? ':reserve_transparent=1' : '';
    final paletteLabel = maskPath != null ? 'alpha' : 'framed';
    final maskStage = maskPath != null
        ? ';[framed][1:v]alphamerge[$paletteLabel]'
        : '';

    return [
      '-y',
      '-ss',
      _seconds(settings.startSeconds),
      '-t',
      _seconds(settings.sourceDurationSeconds),
      '-i',
      video.path,
      if (maskPath != null) ...['-loop', '1', '-i', maskPath],
      '-lavfi',
      '$graph$maskStage;'
          '[$paletteLabel]palettegen=max_colors=${settings.colors}'
          ':stats_mode=${settings.palette.statsMode}$reserve',
      '-frames:v',
      '1',
      palettePath,
    ];
  }

  /// Monta os argumentos do FFmpeg para a passagem 2: aplica a paleta
  /// gerada na passagem 1 ao vídeo e grava o GIF final (ou uma amostra,
  /// se [frameLimit] for informado). Com moldura, [maskPath] recorta os
  /// cantos do mesmo jeito que em [_paletteGenArgs], e `alpha_threshold`
  /// garante que os pixels transparentes da máscara virem o índice
  /// transparente reservado na paleta.
  List<String> _paletteUseArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String palettePath,
    required String outputPath,
    String? maskPath,
    int? frameLimit,
  }) {
    // Com paleta por quadro, o paletteuse precisa saber que a tabela de cores
    // muda ao longo do tempo (new=1).
    final newPalette = settings.palette == PaletteMode.perFrame ? ':new=1' : '';

    if (settings.frame.style == FrameStyle.none) {
      final filter = buildVideoFilter(settings, video);
      return [
        '-y',
        '-ss', _seconds(settings.startSeconds),
        '-t', _seconds(settings.sourceDurationSeconds),
        '-i', video.path,
        '-i', palettePath,
        '-lavfi',
        '[0:v]$filter[v];[v][1:v]paletteuse=dither=${settings.dither.ffmpegValue}'
            ':diff_mode=rectangle$newPalette',
        // 0 = repetir para sempre; -1 = tocar uma vez só.
        '-loop', settings.loop ? '0' : '-1',
        '-an',
        if (frameLimit != null) ...['-frames:v', '$frameLimit'],
        '-f', 'gif',
        outputPath,
      ];
    }

    final graph = _framedGraph(settings, video, input: '0:v', output: 'framed');
    final useLabel = maskPath != null ? 'alpha' : 'framed';
    final maskStage = maskPath != null
        ? ';[framed][2:v]alphamerge[$useLabel]'
        : '';
    final alphaThreshold = maskPath != null ? ':alpha_threshold=128' : '';

    return [
      '-y',
      '-ss',
      _seconds(settings.startSeconds),
      '-t',
      _seconds(settings.sourceDurationSeconds),
      '-i',
      video.path,
      '-i',
      palettePath,
      if (maskPath != null) ...['-loop', '1', '-i', maskPath],
      '-lavfi',
      '$graph$maskStage;'
          '[$useLabel][1:v]paletteuse=dither=${settings.dither.ffmpegValue}'
          ':diff_mode=rectangle$newPalette$alphaThreshold',
      '-loop',
      settings.loop ? '0' : '-1',
      '-an',
      if (frameLimit != null) ...['-frames:v', '$frameLimit'],
      '-f',
      'gif',
      outputPath,
    ];
  }

  /// Caminho do PNG de máscara (gerado por [rasterizeCornerMask]) para
  /// [settings], ou `null` se não há moldura ou "Fundo transparente" está
  /// desligado. As dimensões não dependem do trecho de tempo, então uma
  /// única máscara serve tanto a conversão final quanto todas as amostras
  /// de calibração.
  Future<String?> _prepareMaskFile({
    required ConversionSettings settings,
    required VideoInfo video,
    required Directory dir,
    required String stamp,
  }) async {
    final frame = settings.frame;
    if (frame.style == FrameStyle.none || !frame.transparentBackground) {
      return null;
    }

    final (canvasWidth, canvasHeight) = settings.outputDimensions(video);
    final outerRadius = FrameGeometry.of(
      Size(canvasWidth.toDouble(), canvasHeight.toDouble()),
      frame,
    ).outerRadius;

    final bytes = await rasterizeCornerMask(
      canvasWidth,
      canvasHeight,
      outerRadius,
    );
    final path = '${dir.path}/mascara_$stamp.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  String _seconds(double value) => value.toStringAsFixed(3);

  // ------------------------------------------------------------------
  // Conversão
  // ------------------------------------------------------------------

  /// Converte o vídeo em GIF usando duas passagens (paleta + aplicação).
  ///
  /// Uma passagem só, com a paleta genérica de 216 cores do GIF, produz
  /// aquele resultado "lavado" com faixas. As duas passagens escolhem as 256
  /// cores que este vídeo específico usa — é o que dá qualidade de verdade.
  Future<ConversionResult> convert({
    required VideoInfo video,
    required ConversionSettings settings,
    void Function(double progress)? onProgress,
  }) async {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final palettePath = '${dir.path}/paleta_$stamp.png';
    final outputPath = '${dir.path}/gif_$stamp.gif';

    final totalMs = settings.outputDurationSeconds * 1000;
    String? maskPath;

    try {
      maskPath = await _prepareMaskFile(
        settings: settings,
        video: video,
        dir: dir,
        stamp: '$stamp',
      );

      // A geração da paleta lê o trecho inteiro, então vale cerca de um terço
      // do tempo total. Repartimos a barra de progresso nessa proporção.
      await _run(
        _paletteGenArgs(
          video: video,
          settings: settings,
          palettePath: palettePath,
          maskPath: maskPath,
        ),
        onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs) * 0.35),
        step: 'geração da paleta',
      );

      if (_cancelled) throw FfmpegException('Conversão cancelada.');

      await _run(
        _paletteUseArgs(
          video: video,
          settings: settings,
          palettePath: palettePath,
          outputPath: outputPath,
          maskPath: maskPath,
        ),
        onTimeMs: (ms) => onProgress?.call(0.35 + _ratio(ms, totalMs) * 0.65),
        step: 'montagem do GIF',
      );

      onProgress?.call(1.0);

      final output = File(outputPath);
      if (!output.existsSync() || output.lengthSync() == 0) {
        throw FfmpegException('O GIF saiu vazio. Tente outro trecho do vídeo.');
      }

      final (width, height) = settings.outputDimensions(video);
      return ConversionResult(
        file: output,
        bytes: output.lengthSync(),
        width: width,
        height: height,
        frames: settings.frameCount,
        elapsed: stopwatch.elapsed,
      );
    } finally {
      _activeSessionId = null;
      _deleteQuietly(palettePath);
      if (maskPath != null) _deleteQuietly(maskPath);
    }
  }

  /// Progresso (0–1) dado o tempo já codificado e o tempo total esperado.
  double _ratio(double ms, double totalMs) =>
      totalMs <= 0 ? 0 : (ms / totalMs).clamp(0.0, 1.0).toDouble();

  /// Executa uma sessão do FFmpeg com os [arguments] dados, reportando
  /// progresso via [onTimeMs] e resolvendo/rejeitando conforme o código de
  /// retorno da sessão (sucesso, cancelamento ou falha).
  Future<void> _run(
    List<String> arguments, {
    required String step,
    void Function(double ms)? onTimeMs,
  }) async {
    final completer = Completer<void>();

    final session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          completer.complete();
        } else if (ReturnCode.isCancel(code)) {
          completer.completeError(FfmpegException('Conversão cancelada.'));
        } else {
          completer.completeError(
            FfmpegException(
              'O FFmpeg falhou durante a $step.',
              logs: await session.getAllLogsAsString() ?? '',
            ),
          );
        }
      },
      (_) {},
      (Statistics statistics) {
        onTimeMs?.call(statistics.getTime().toDouble());
      },
    );

    _activeSessionId = session.getSessionId();
    return completer.future;
  }

  /// Sinaliza cancelamento e interrompe a sessão do FFmpeg em andamento.
  Future<void> cancel() async {
    _cancelled = true;
    final id = _activeSessionId;
    if (id != null) {
      await FFmpegKit.cancel(id);
    }
  }

  // ------------------------------------------------------------------
  // Calibração da estimativa
  // ------------------------------------------------------------------

  /// Mede o peso real de trechos curtos e devolve o "quanto pesa por pixel"
  /// deste vídeo.
  ///
  /// Codificamos amostras de menos de um segundo em pontos diferentes do
  /// trecho escolhido, com as MESMAS configurações que o usuário selecionou.
  /// Como o modelo separa conteúdo (o que medimos) de configuração (o que
  /// calculamos), o valor obtido continua valendo mesmo depois que o usuário
  /// mexer nos controles — não é preciso medir de novo a cada ajuste.
  ///
  /// De cada amostra saem DUAS medidas: o GIF da janela inteira e o mesmo GIF
  /// cortado no primeiro quadro. A diferença entre elas é o que os quadros
  /// seguintes custaram, e é isso que permite ao modelo não diluir o primeiro
  /// quadro — caro, porque é uma imagem completa — pelo resto da conversão.
  /// A segunda codificação reaproveita a paleta já gerada, então custa pouco.
  Future<ComplexityProfile> calibrate({
    required VideoInfo video,
    required ConversionSettings settings,
    int sampleCount = 2,
    void Function(double progress)? onProgress,
  }) async {
    final duration = settings.sourceDurationSeconds;
    if (duration <= 0) return ComplexityProfile.fallback;

    // Amostra curta, mas nunca com menos de 5 quadros: com pouquíssimos
    // quadros o custo fixo do cabeçalho distorce a medição.
    final minWindow = 5 / settings.fps * settings.speed;
    var window = duration / 4;
    if (window < minWindow) window = minWindow;
    if (window > 1.0) window = 1.0;
    if (window > duration) window = duration;

    final positions = _samplePositions(
      start: settings.startSeconds,
      duration: duration,
      window: window,
      count: sampleCount,
    );

    final dir = await getTemporaryDirectory();
    final profiles = <ComplexityProfile>[];

    // As dimensões (e portanto a máscara) não dependem do trecho de tempo,
    // então uma única máscara serve todas as amostras desta calibração.
    final maskPath = await _prepareMaskFile(
      settings: settings,
      video: video,
      dir: dir,
      stamp: 'calib_${DateTime.now().millisecondsSinceEpoch}',
    );

    try {
      for (var i = 0; i < positions.length; i++) {
        final sample = settings.copyWith(
          startSeconds: positions[i],
          endSeconds: positions[i] + window,
        );

        final stamp = '${DateTime.now().millisecondsSinceEpoch}_$i';
        final palettePath = '${dir.path}/amostra_$stamp.png';
        final gifPath = '${dir.path}/amostra_$stamp.gif';
        final firstFramePath = '${dir.path}/amostra_${stamp}_q1.gif';

        try {
          await _run(
            _paletteGenArgs(
              video: video,
              settings: sample,
              palettePath: palettePath,
              maskPath: maskPath,
            ),
            step: 'medição',
          );
          await _run(
            _paletteUseArgs(
              video: video,
              settings: sample,
              palettePath: palettePath,
              outputPath: gifPath,
              maskPath: maskPath,
            ),
            step: 'medição',
          );
          await _run(
            _paletteUseArgs(
              video: video,
              settings: sample,
              palettePath: palettePath,
              outputPath: firstFramePath,
              maskPath: maskPath,
              frameLimit: 1,
            ),
            step: 'medição',
          );

          final gif = File(gifPath);
          final firstFrame = File(firstFramePath);
          if (gif.existsSync() &&
              gif.lengthSync() > 0 &&
              firstFrame.existsSync() &&
              firstFrame.lengthSync() > 0) {
            profiles.add(
              SizeEstimator.calibrate(
                measuredBytes: gif.lengthSync(),
                firstFrameBytes: firstFrame.lengthSync(),
                sampleSettings: sample,
                video: video,
              ),
            );
          }
        } on FfmpegException {
          // Uma amostra que falha (fim do arquivo, quadro corrompido) não
          // deve derrubar a medição inteira — seguimos com as que deram certo.
        } finally {
          _activeSessionId = null;
          _deleteQuietly(palettePath);
          _deleteQuietly(gifPath);
          _deleteQuietly(firstFramePath);
          onProgress?.call((i + 1) / positions.length);
        }
      }
    } finally {
      if (maskPath != null) _deleteQuietly(maskPath);
    }

    if (profiles.isEmpty) return SizeEstimator.profileFromSource(video);
    return SizeEstimator.combineSamples(profiles);
  }

  /// Espalha as amostras pelo trecho para pegar partes paradas e agitadas.
  List<double> _samplePositions({
    required double start,
    required double duration,
    required double window,
    required int count,
  }) {
    final safeCount = count < 1 ? 1 : count;
    final fractions = switch (safeCount) {
      1 => const [0.4],
      2 => const [0.2, 0.6],
      _ => const [0.1, 0.45, 0.75],
    };

    final maxStart = start + duration - window;
    return fractions.take(safeCount).map((f) {
      final position = start + duration * f;
      return position > maxStart
          ? (maxStart < start ? start : maxStart)
          : position;
    }).toList();
  }

  // ------------------------------------------------------------------
  // Miniatura para a prévia de recorte
  // ------------------------------------------------------------------

  /// Extrai um único quadro do vídeo no instante [atSeconds] como JPEG,
  /// usado para gerar a miniatura da tela de recorte. Retorna `null` se a
  /// extração falhar.
  Future<File?> extractFrame({
    required VideoInfo video,
    required double atSeconds,
    int width = 720,
  }) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/quadro_${DateTime.now().millisecondsSinceEpoch}.jpg';

    try {
      await _run([
        '-y',
        '-ss',
        _seconds(atSeconds),
        '-i',
        video.path,
        '-frames:v',
        '1',
        '-vf',
        'scale=$width:-2:flags=lanczos',
        '-q:v',
        '3',
        path,
      ], step: 'extração de quadro');
    } on FfmpegException {
      return null;
    } finally {
      _activeSessionId = null;
    }

    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// Apaga um arquivo temporário sem lançar erro se isso falhar.
  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Arquivo temporário: se não deu para apagar agora, o sistema limpa.
    }
  }
}
