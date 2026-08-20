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
import '../models/image_frame.dart';
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
  /// modo de ajuste, recortado pelos cantos internos e composto sobre o
  /// fundo colorido no tamanho final ([ConversionSettings.outputDimensions]).
  /// Só deve ser chamado quando há moldura ativa
  /// (`frame.style != FrameStyle.none`).
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
    final geometry = FrameGeometry.of(
      Size(canvasWidth.toDouble(), canvasHeight.toDouble()),
      frame,
    );
    final innerRadius = geometry.innerRadius;

    final parts = <String>['[$input]$contentFilter[content]'];

    if (contentWidth == areaWidth && contentHeight == areaHeight) {
      parts.add('[content]copy[fitted]');
    } else {
      final fit = resolveContentFit(
        frame.contentFit,
        contentWidth / contentHeight,
        areaWidth / areaHeight,
      );
      switch (fit) {
        case ContentFitMode.fill:
          parts.add(
            '[content]scale=$areaWidth:$areaHeight:'
            'force_original_aspect_ratio=increase:flags=lanczos,'
            'crop=$areaWidth:$areaHeight[fitted]',
          );
        case ContentFitMode.expand:
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

    // A prévia recorta o vídeo pelo raio interno e o desenha sobre a moldura.
    // A exportação precisa manter essa mesma ordem: primeiro o fundo colorido,
    // depois o vídeo já recortado. Um `pad` simples deixava o vídeo retangular
    // e uma composição invertida fazia a borda cobrir parte dele.
    parts.add('[fitted]format=rgba,setpts=PTS-STARTPTS[fitted_rgba]');
    if (innerRadius <= 0) {
      parts.add(
        'color=white:s=${areaWidth}x$areaHeight:r=${settings.fps}:'
        'd=${_seconds(settings.outputDurationSeconds)},format=gray[inner_mask]',
      );
    } else {
      final radius = innerRadius.toStringAsFixed(3);
      final roundedMask =
          "geq=lum='clip(($radius+0.5-hypot(max(abs(X-(W-1)/2)-((W-1)/2-$radius),0),max(abs(Y-(H-1)/2)-((H-1)/2-$radius),0)))*255,0,255)'";
      parts.add(
        'color=white:s=${areaWidth}x$areaHeight:r=${settings.fps}:'
        'd=${_seconds(settings.outputDurationSeconds)},format=gray,'
        '$roundedMask[inner_mask]',
      );
    }
    parts.add(
      '[fitted_rgba][inner_mask]alphamerge=shortest=1[rounded_content]',
    );
    parts.add(
      'color=c=$colorHex:s=${canvasWidth}x$canvasHeight:'
      'r=${settings.fps}:d=${_seconds(settings.outputDurationSeconds)}'
      '[frame_background]',
    );
    parts.add(
      '[frame_background][rounded_content]overlay='
      '$thicknessPx:$thicknessPx:shortest=1:repeatlast=0[$output]',
    );

    return parts.join(';');
  }

  /// Grafo de filtro completo pronto para `-lavfi` quando a moldura é uma
  /// arte de imagem ([FrameSettings.imageFrame]) — diferente de
  /// [_framedGraph] (que desenha a borda com `pad` de cor sólida), aqui o
  /// conteúdo é ajustado para a área de conteúdo da arte
  /// ([ConversionSettings.imageFrameContentAreaPx]) e a arte (já
  /// rasterizada em [artInput], no tamanho exato do canvas) é composta por
  /// cima via `overlay`, usando o próprio canal alfa da arte — sem precisar
  /// de [rasterizeCornerMask]/[_prepareMaskFile], que só existem para os
  /// cantos arredondados da moldura procedural.
  ///
  /// A transparência final vem da união (`blend=lighten`, ou seja, máximo
  /// por pixel) de dois mapas em escala de cinza: o canal alfa da própria
  /// arte (o corpo do mockup) e um retângulo sólido do tamanho exato da
  /// área de conteúdo (onde o vídeo sempre aparece opaco, mesmo nas barras
  /// de "Encaixar", que não têm cor de moldura configurável — por isso
  /// usam preto). [areaMaskInput] é uma fonte `color` do `lavfi`, gerada
  /// direto no grafo, sem precisar de um arquivo temporário.
  String _imageFramedGraph(
    ConversionSettings settings,
    VideoInfo video, {
    required String input,
    required String artInput,
    required String areaMaskInput,
    required String output,
  }) {
    final contentFilter = buildVideoFilter(settings, video);
    final frame = settings.frame;

    final (contentWidth, contentHeight) = settings.contentDimensions(video);
    final (areaX, areaY, areaWidth, areaHeight) = settings
        .imageFrameContentAreaPx(video);
    final (canvasWidth, canvasHeight) = settings.imageFrameCanvasDimensions(
      video,
    );

    final parts = <String>['[$input]$contentFilter[content]'];

    if (contentWidth == areaWidth && contentHeight == areaHeight) {
      parts.add('[content]copy[fitted]');
    } else {
      final fit = resolveContentFit(
        frame.contentFit,
        contentWidth / contentHeight,
        areaWidth / areaHeight,
      );
      switch (fit) {
        case ContentFitMode.fill:
          parts.add(
            '[content]scale=$areaWidth:$areaHeight:'
            'force_original_aspect_ratio=increase:flags=lanczos,'
            'crop=$areaWidth:$areaHeight[fitted]',
          );
        case ContentFitMode.expand:
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
            'color=black[fitted]',
          );
      }
    }

    parts.add(
      '[fitted]pad=$canvasWidth:$canvasHeight:$areaX:$areaY:'
      'color=black[base]',
    );
    parts.add('[$artInput]setpts=PTS-STARTPTS[art]');
    // A arte e a máscara são entradas em loop. Sem `shortest`, o overlay
    // continua repetindo o último quadro do vídeo para sempre e a conversão
    // de molduras de imagem fica presa em 0%. O vídeo é a entrada principal,
    // portanto ele também define o fim da composição.
    parts.add(
      '[base][art]overlay=0:0:shortest=1:repeatlast=0,'
      'format=rgba[visual]',
    );
    parts.add(
      '[$artInput]alphaextract,format=gray,setpts=PTS-STARTPTS[art_alpha]',
    );
    parts.add(
      '[$areaMaskInput]pad=$canvasWidth:$canvasHeight:$areaX:$areaY:'
      'color=black,format=gray,setpts=PTS-STARTPTS[area_mask]',
    );
    parts.add('[art_alpha][area_mask]blend=all_mode=lighten[final_mask]');
    parts.add('[visual][final_mask]alphamerge=shortest=1[$output]');

    return parts.join(';');
  }

  /// Rasteriza a arte da moldura de imagem selecionada
  /// ([FrameSettings.imageFrame]) num PNG de exatamente o tamanho do canvas
  /// final ([ConversionSettings.imageFrameCanvasDimensions]) — nunca um
  /// asset esticado, mesmo princípio de [_prepareMaskFile]. Devolve `null`
  /// quando não há moldura de imagem selecionada.
  Future<String?> _prepareImageFrameArt({
    required ConversionSettings settings,
    required VideoInfo video,
    required Directory dir,
    required String stamp,
  }) async {
    final asset = settings.frame.imageFrame;
    if (asset == null) return null;

    final (canvasWidth, canvasHeight) = settings.imageFrameCanvasDimensions(
      video,
    );
    final bytes = asset.source == ImageFrameSource.bundledSvg
        ? await rasterizeSvgAsset(
            asset.svgAssetPath!,
            canvasWidth,
            canvasHeight,
          )
        : await rasterizeImportedImage(
            asset.imageFilePath!,
            canvasWidth,
            canvasHeight,
          );

    final path = '${dir.path}/moldura_img_$stamp.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Argumentos completos do FFmpeg para uma moldura de imagem — sempre
  /// segue o caminho "com transparência" (paleta com
  /// `reserve_transparent=1` + `paletteuse ... alpha_threshold=128`), já
  /// que toda moldura de imagem tem alfa real (mesmo padrão de
  /// [_transparentGifArgs], mas a partir de [_imageFramedGraph]).
  List<String> _imageFramedGifArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String artPath,
    required String outputPath,
    int? frameLimit,
  }) {
    final (_, _, areaWidth, areaHeight) = settings.imageFrameContentAreaPx(
      video,
    );
    final graph = _imageFramedGraph(
      settings,
      video,
      input: '0:v',
      artInput: '1:v',
      areaMaskInput: '2:v',
      output: 'framed',
    );
    final newPalette = settings.palette == PaletteMode.perFrame ? ':new=1' : '';

    return [
      '-y',
      '-ss',
      _seconds(settings.startSeconds),
      '-t',
      _seconds(settings.sourceDurationSeconds),
      '-i',
      video.path,
      '-loop',
      '1',
      '-framerate',
      '${settings.fps}',
      '-i',
      artPath,
      '-f',
      'lavfi',
      '-i',
      'color=white:size=${areaWidth}x$areaHeight:rate=${settings.fps}',
      '-lavfi',
      '$graph;'
          '[framed]split=2[palette_source][gif_source];'
          '[palette_source]palettegen=max_colors=${settings.colors}'
          ':stats_mode=${settings.palette.statsMode}'
          ':reserve_transparent=1[palette];'
          '[gif_source][palette]paletteuse=dither=${settings.dither.ffmpegValue}'
          ':diff_mode=rectangle$newPalette:alpha_threshold=128[out]',
      '-map',
      '[out]',
      '-loop',
      settings.loop ? '0' : '-1',
      '-an',
      // As entradas da arte e da máscara são infinitas; encerra a saída junto
      // com o fluxo de vídeo, mesmo em builds do FFmpeg que não propagam o EOF
      // através de todos os filtros complexos.
      '-shortest',
      if (frameLimit != null) ...['-frames:v', '$frameLimit'],
      '-f',
      'gif',
      outputPath,
    ];
  }

  String _ffmpegColor(Color color) {
    final rgb = (color.toARGB32() & 0x00FFFFFF).toRadixString(16);
    return '0x${rgb.padLeft(6, '0')}';
  }

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

    final transparent = settings.frame.transparentBackground;
    final graph = _framedGraph(settings, video, input: '0:v', output: 'framed');
    final reserve = transparent ? ':reserve_transparent=1' : '';
    final paletteLabel = transparent ? 'alpha' : 'framed';
    final maskStage = transparent
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
      if (maskPath != null) ...[
        '-loop',
        '1',
        '-t',
        _seconds(settings.outputDurationSeconds),
        '-i',
        maskPath,
      ],
      '-lavfi',
      '$graph$maskStage;'
          '[$paletteLabel]palettegen=max_colors=${settings.colors}'
          ':stats_mode=${settings.palette.statsMode}$reserve',
      '-frames:v',
      '1',
      palettePath,
    ];
  }

  List<String> _paletteUseArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String palettePath,
    required String outputPath,
    String? maskPath,
    int? frameLimit,
  }) {
    final newPalette = settings.palette == PaletteMode.perFrame ? ':new=1' : '';

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
        '-i',
        palettePath,
        '-lavfi',
        '[0:v]$filter[v];[v][1:v]paletteuse=dither=${settings.dither.ffmpegValue}'
            ':diff_mode=rectangle$newPalette',
        '-loop',
        settings.loop ? '0' : '-1',
        '-an',
        if (frameLimit != null) ...['-frames:v', '$frameLimit'],
        '-f',
        'gif',
        outputPath,
      ];
    }

    final transparent = settings.frame.transparentBackground;
    final graph = _framedGraph(settings, video, input: '0:v', output: 'framed');
    final useLabel = transparent ? 'alpha' : 'framed';
    final maskStage = transparent ? ';[framed][2:v]alphamerge[$useLabel]' : '';
    final alphaThreshold = transparent ? ':alpha_threshold=128' : '';

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
      if (maskPath != null) ...[
        '-loop',
        '1',
        '-t',
        _seconds(settings.outputDurationSeconds),
        '-i',
        maskPath,
      ],
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

  /// Para GIF transparente, gera e aplica a paleta dentro do mesmo grafo.
  /// Isso evita a segunda sessão com vídeo + paleta PNG + máscara, que é a
  /// etapa que estava falhando no Android ao usar "Fundo transparente".
  List<String> _transparentGifArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String maskPath,
    required String outputPath,
    int? frameLimit,
  }) {
    final graph = _framedGraph(settings, video, input: '0:v', output: 'framed');
    final newPalette = settings.palette == PaletteMode.perFrame ? ':new=1' : '';

    return [
      '-y',
      '-ss',
      _seconds(settings.startSeconds),
      '-t',
      _seconds(settings.sourceDurationSeconds),
      '-i',
      video.path,
      '-loop',
      '1',
      '-framerate',
      '${settings.fps}',
      '-i',
      maskPath,
      '-lavfi',
      '$graph;'
          '[framed]format=rgba,setpts=PTS-STARTPTS[framed_rgba];'
          '[1:v]format=gray,fps=${settings.fps},'
          'setpts=PTS-STARTPTS[mask_gray];'
          '[framed_rgba][mask_gray]alphamerge=shortest=1[alpha];'
          '[alpha]split=2[palette_source][gif_source];'
          '[palette_source]palettegen=max_colors=${settings.colors}'
          ':stats_mode=${settings.palette.statsMode}'
          ':reserve_transparent=1[palette];'
          '[gif_source][palette]paletteuse=dither=${settings.dither.ffmpegValue}'
          ':diff_mode=rectangle$newPalette:alpha_threshold=128[out]',
      '-map',
      '[out]',
      '-loop',
      settings.loop ? '0' : '-1',
      '-an',
      if (frameLimit != null) ...['-frames:v', '$frameLimit'],
      '-f',
      'gif',
      outputPath,
    ];
  }

  Future<String?> _prepareMaskFile({
    required ConversionSettings settings,
    required VideoInfo video,
    required Directory dir,
    required String stamp,
  }) async {
    final frame = settings.frame;
    if (frame.style == FrameStyle.none ||
        frame.imageFrame != null ||
        !frame.transparentBackground) {
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
    String? frameArtPath;

    try {
      if (settings.frame.imageFrame != null) {
        frameArtPath = await _prepareImageFrameArt(
          settings: settings,
          video: video,
          dir: dir,
          stamp: '$stamp',
        );
        await _run(
          _imageFramedGifArgs(
            video: video,
            settings: settings,
            artPath: frameArtPath!,
            outputPath: outputPath,
          ),
          onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs)),
          step: 'montagem do GIF com moldura de imagem',
        );
        onProgress?.call(1.0);

        final output = File(outputPath);
        if (!output.existsSync() || output.lengthSync() == 0) {
          throw FfmpegException(
            'O GIF saiu vazio. Tente outro trecho do vídeo.',
          );
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
      }

      maskPath = await _prepareMaskFile(
        settings: settings,
        video: video,
        dir: dir,
        stamp: '$stamp',
      );

      if (maskPath != null && settings.frame.transparentBackground) {
        await _run(
          _transparentGifArgs(
            video: video,
            settings: settings,
            maskPath: maskPath,
            outputPath: outputPath,
          ),
          onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs)),
          step: 'montagem do GIF transparente',
        );
      } else {
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
      }

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
      if (frameArtPath != null) _deleteQuietly(frameArtPath);
    }
  }

  double _ratio(double ms, double totalMs) =>
      totalMs <= 0 ? 0 : (ms / totalMs).clamp(0.0, 1.0).toDouble();

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

  Future<void> cancel() async {
    _cancelled = true;
    final id = _activeSessionId;
    if (id != null) {
      await FFmpegKit.cancel(id);
    }
  }

  Future<ComplexityProfile> calibrate({
    required VideoInfo video,
    required ConversionSettings settings,
    int sampleCount = 2,
    void Function(double progress)? onProgress,
  }) async {
    final duration = settings.sourceDurationSeconds;
    if (duration <= 0) return ComplexityProfile.fallback;

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

    final maskPath = await _prepareMaskFile(
      settings: settings,
      video: video,
      dir: dir,
      stamp: 'calib_${DateTime.now().millisecondsSinceEpoch}',
    );
    final frameArtPath = await _prepareImageFrameArt(
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
          if (frameArtPath != null) {
            await _run(
              _imageFramedGifArgs(
                video: video,
                settings: sample,
                artPath: frameArtPath,
                outputPath: gifPath,
              ),
              step: 'medição',
            );
            await _run(
              _imageFramedGifArgs(
                video: video,
                settings: sample,
                artPath: frameArtPath,
                outputPath: firstFramePath,
                frameLimit: 1,
              ),
              step: 'medição',
            );
          } else if (maskPath != null && sample.frame.transparentBackground) {
            await _run(
              _transparentGifArgs(
                video: video,
                settings: sample,
                maskPath: maskPath,
                outputPath: gifPath,
              ),
              step: 'medição',
            );
            await _run(
              _transparentGifArgs(
                video: video,
                settings: sample,
                maskPath: maskPath,
                outputPath: firstFramePath,
                frameLimit: 1,
              ),
              step: 'medição',
            );
          } else {
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
          }

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
          // Uma amostra inválida não deve interromper as demais medições.
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
      if (frameArtPath != null) _deleteQuietly(frameArtPath);
    }

    if (profiles.isEmpty) return SizeEstimator.profileFromSource(video);
    return SizeEstimator.combineSamples(profiles);
  }

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

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // A limpeza é de melhor esforço; o arquivo temporário pode já ter sumido.
    }
  }
}
