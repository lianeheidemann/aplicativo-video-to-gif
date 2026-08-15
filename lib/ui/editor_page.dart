import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/conversion_settings.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/size_estimator.dart';
import 'converting_page.dart';
import 'widgets/labeled_section.dart';
import 'widgets/size_panel.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.video,
    required this.initialSettings,
  });

  final VideoInfo video;
  final ConversionSettings initialSettings;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _ffmpeg = FfmpegService();

  late ConversionSettings _settings = widget.initialSettings;

  /// Começa com um palpite tirado do bitrate do arquivo; vira uma medição
  /// real assim que o usuário toca em "Medir".
  late ComplexityProfile _profile =
      SizeEstimator.profileFromSource(widget.video);

  VideoPlayerController? _player;
  bool _measuring = false;
  AspectPreset _aspect = AspectPreset.presets.first;

  VideoInfo get _video => widget.video;

  SizeEstimate get _estimate => SizeEstimator.estimate(
        settings: _settings,
        video: _video,
        profile: _profile,
      );

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final controller = VideoPlayerController.file(File(_video.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _player = controller);
    } catch (_) {
      // A prévia é um extra: se o codec não tocar no player nativo, a
      // conversão pelo FFmpeg continua funcionando normalmente.
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _update(ConversionSettings next) {
    setState(() => _settings = next);
  }

  Future<void> _seekPreview(double seconds) async {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    await player.seekTo(Duration(milliseconds: (seconds * 1000).round()));
  }

  // ------------------------------------------------------------------
  // Medição
  // ------------------------------------------------------------------

  Future<void> _measure() async {
    setState(() => _measuring = true);
    try {
      final profile = await _ffmpeg.calibrate(
        video: _video,
        settings: _settings,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _measuring = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _measuring = false);
      _showMessage(
        'Não deu para medir este trecho. A estimativa aproximada continua '
        'valendo.',
      );
    }
  }

  void _fitTo(ShareTarget target) {
    final fitted = SizeEstimator.fitToTarget(
      settings: _settings,
      video: _video,
      targetBytes: (target.limitBytes * 0.9).round(),
      profile: _profile,
    );
    _update(fitted);
    _showMessage('Ajustado para caber no ${target.name}.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _convert() async {
    await _player?.pause();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConvertingPage(
          video: _video,
          settings: _settings,
          estimate: _estimate,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustar GIF'),
        actions: [
          IconButton(
            tooltip: 'Como deixar o GIF mais leve',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          _preview(),
          const SizedBox(height: 12),
          _durationSection(),
          _aspectSection(),
          _speedSection(),
          _resolutionSection(),
          _fpsSection(),
          _advancedSection(),
          const SizedBox(height: 8),
        ],
      ),
      bottomNavigationBar: SizePanel(
        estimate: _estimate,
        suggestion: SizeEstimator.suggestionFor(
          settings: _settings,
          video: _video,
          profile: _profile,
        ),
        measuring: _measuring,
        onMeasure: _measure,
        onConvert: _convert,
        onFitTo: _fitTo,
      ),
    );
  }

  Widget _preview() {
    final player = _player;

    if (player == null || !player.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _video.aspectRatio,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: player.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(player),
            _CropOverlay(video: _video, crop: _settings.crop),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    if (player.value.isPlaying) {
                      await player.pause();
                    } else {
                      await player.seekTo(
                        Duration(
                          milliseconds:
                              (_settings.startSeconds * 1000).round(),
                        ),
                      );
                      await player.play();
                    }
                    if (mounted) setState(() {});
                  },
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: player.value.isPlaying ? 0 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.black45,
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _durationSection() {
    final start = _settings.startSeconds;
    final end = _settings.endSeconds;

    return LabeledSection(
      icon: Icons.content_cut,
      title: 'Duração',
      value: '${_settings.sourceDurationSeconds.toStringAsFixed(1)}s',
      hint: 'Arraste as pontas para cortar o começo e o fim. '
          'É o controle que mais muda o peso.',
      child: Column(
        children: [
          RangeSlider(
            min: 0,
            max: _video.durationSeconds,
            divisions: (_video.durationSeconds * 10).round().clamp(1, 2000),
            values: RangeValues(start, end),
            labels: RangeLabels(
              _formatSeconds(start),
              _formatSeconds(end),
            ),
            onChanged: (values) {
              // Impede que as pontas se cruzem ou colem.
              if (values.end - values.start < 0.2) return;
              _update(
                _settings.copyWith(
                  startSeconds: values.start,
                  endSeconds: values.end,
                ),
              );
            },
            onChangeEnd: (values) => _seekPreview(values.start),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Início: ${_formatSeconds(start)}'),
              Text('Fim: ${_formatSeconds(end)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aspectSection() {
    final crop = _settings.crop;
    final canMove = crop != null &&
        (crop.width < _video.width || crop.height < _video.height);

    return LabeledSection(
      icon: Icons.crop,
      title: 'Formato da janela',
      value: _aspect.label,
      hint: _aspect.hint.isEmpty
          ? 'Mantém a proporção original do vídeo.'
          : _aspect.hint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionChips<AspectPreset>(
            options: AspectPreset.presets,
            selected: _aspect,
            labelBuilder: (preset) => preset.label,
            onSelected: (preset) {
              setState(() {
                _aspect = preset;
                _settings = preset.ratio == null
                    ? _settings.copyWith(clearCrop: true)
                    : _settings.copyWith(
                        crop: CropRect.centered(_video, preset.ratio!),
                      );
              });
            },
          ),
          if (crop != null && canMove) ...[
            const SizedBox(height: 8),
            Text(
              crop.height < _video.height
                  ? 'Posição vertical do recorte'
                  : 'Posição horizontal do recorte',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _cropPositionSlider(crop),
          ],
        ],
      ),
    );
  }

  Widget _cropPositionSlider(CropRect crop) {
    final verticalRoom = _video.height - crop.height;
    final horizontalRoom = _video.width - crop.width;
    final vertical = verticalRoom >= horizontalRoom;
    final room = vertical ? verticalRoom : horizontalRoom;
    if (room <= 0) return const SizedBox.shrink();

    final raw = (vertical ? crop.y : crop.x).toDouble();
    final value = raw < 0 ? 0.0 : (raw > room ? room.toDouble() : raw);

    return Slider(
      min: 0,
      max: room.toDouble(),
      value: value,
      onChanged: (v) {
        _update(
          _settings.copyWith(
            crop: vertical
                ? crop.copyWith(y: v.round())
                : crop.copyWith(x: v.round()),
          ),
        );
      },
    );
  }

  Widget _speedSection() {
    return LabeledSection(
      icon: Icons.fast_forward,
      title: 'Velocidade',
      value: '${_formatSpeed(_settings.speed)}x',
      hint: 'Acelerar encurta o GIF e economiza peso; '
          'câmera lenta deixa mais longo e mais pesado.',
      child: OptionChips<double>(
        options: ConversionSettings.speedOptions,
        selected: _settings.speed,
        labelBuilder: (speed) => '${_formatSpeed(speed)}x',
        onSelected: (speed) => _update(_settings.copyWith(speed: speed)),
      ),
    );
  }

  Widget _resolutionSection() {
    final available = ConversionSettings.widthOptions
        .where((w) => w <= _video.width)
        .toList();
    if (available.isEmpty) available.add(_video.width);

    final (width, height) = _settings.outputDimensions(_video);

    return LabeledSection(
      icon: Icons.photo_size_select_large,
      title: 'Resolução',
      value: '$width×$height',
      hint: 'Reduzir a largura pela metade corta o peso em cerca de 75%, '
          'porque a área cai ao quadrado.',
      child: OptionChips<int>(
        options: available,
        selected: available.contains(_settings.targetWidth)
            ? _settings.targetWidth
            : available.last,
        labelBuilder: (w) => '$w px',
        onSelected: (w) => _update(_settings.copyWith(targetWidth: w)),
      ),
    );
  }

  Widget _fpsSection() {
    return LabeledSection(
      icon: Icons.animation,
      title: 'Quadros por segundo (FPS)',
      value: '${_settings.fps} FPS',
      hint: _fpsHint(_settings.fps),
      child: OptionChips<int>(
        options: ConversionSettings.fpsOptions,
        selected: _settings.fps,
        labelBuilder: (fps) => '$fps',
        onSelected: (fps) => _update(_settings.copyWith(fps: fps)),
      ),
    );
  }

  Widget _advancedSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        leading: Icon(
          Icons.tune,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text(
          'Qualidade das cores',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_settings.colors} cores · ${_settings.dither.label}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _subLabel('Número de cores'),
          OptionChips<int>(
            options: ConversionSettings.colorOptions,
            selected: _settings.colors,
            labelBuilder: (c) => '$c',
            onSelected: (c) => _update(_settings.copyWith(colors: c)),
          ),
          const SizedBox(height: 12),
          _subLabel('Suavização de cor (${_settings.dither.description})'),
          OptionChips<DitherMode>(
            options: DitherMode.values,
            selected: _settings.dither,
            labelBuilder: (d) => d.label,
            onSelected: (d) => _update(_settings.copyWith(dither: d)),
          ),
          const SizedBox(height: 12),
          _subLabel('Paleta (${_settings.palette.description})'),
          OptionChips<PaletteMode>(
            options: PaletteMode.values,
            selected: _settings.palette,
            labelBuilder: (p) => p.label,
            onSelected: (p) => _update(_settings.copyWith(palette: p)),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repetir para sempre'),
            subtitle: const Text('Desligue para o GIF tocar uma vez só'),
            value: _settings.loop,
            onChanged: (v) => _update(_settings.copyWith(loop: v)),
          ),
        ],
      ),
    );
  }

  Widget _subLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      );

  void _showHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _HelpSheet(),
    );
  }

  static String _formatSeconds(double seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds - minutes * 60;
    return minutes > 0
        ? '${minutes}m ${rest.toStringAsFixed(1)}s'
        : '${rest.toStringAsFixed(1)}s';
  }

  static String _formatSpeed(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}' : '$speed';

  static String _fpsHint(int fps) {
    if (fps <= 8) return 'Bem econômico, movimento com "engasgo" visível.';
    if (fps <= 12) return 'Boa fluidez com peso baixo — o ponto ideal.';
    if (fps <= 20) return 'Bem fluido, arquivo já bem maior.';
    return 'Muito fluido, mas o peso cresce rápido e poucos apps aproveitam.';
  }
}

/// Escurece as bordas que serão cortadas, para o usuário ver o recorte.
class _CropOverlay extends StatelessWidget {
  const _CropOverlay({required this.video, required this.crop});

  final VideoInfo video;
  final CropRect? crop;

  @override
  Widget build(BuildContext context) {
    final rect = crop;
    if (rect == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / video.width;
        final scaleY = constraints.maxHeight / video.height;

        final left = rect.x * scaleX;
        final top = rect.y * scaleY;
        final width = rect.width * scaleX;
        final height = rect.height * scaleY;

        // Quatro faixas escuras em volta da área que fica, em vez de um véu
        // sobre tudo: assim o trecho recortado continua nítido.
        const veil = Color(0x8C000000);

        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top,
              child: const ColoredBox(color: veil),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: top + height,
              bottom: 0,
              child: const ColoredBox(color: veil),
            ),
            Positioned(
              left: 0,
              width: left,
              top: top,
              height: height,
              child: const ColoredBox(color: veil),
            ),
            Positioned(
              left: left + width,
              right: 0,
              top: top,
              height: height,
              child: const ColoredBox(color: veil),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget item(String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'O que deixa um GIF pesado',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            item(
              '1. Duração — efeito direto',
              'O GIF não comprime no tempo como um vídeo: cada segundo a mais '
                  'soma quadros novos. Cortar de 10s para 5s tira metade do peso.',
            ),
            item(
              '2. Resolução — efeito ao quadrado',
              'A área cresce com o quadrado da largura. Ir de 480 px para '
                  '240 px deixa o arquivo quatro vezes menor.',
            ),
            item(
              '3. FPS — efeito forte, mas com desconto',
              'Dobrar o FPS não dobra o arquivo, porque quadros vizinhos são '
                  'parecidos e o GIF só regrava o que mudou. Ainda assim, '
                  '12 FPS costuma ser o melhor equilíbrio.',
            ),
            item(
              '4. Cor e suavização — o ajuste fino',
              'O GIF só aceita 256 cores por paleta. Suavizar a cor (dither) '
                  'melhora gradientes, mas adiciona ruído que atrapalha a '
                  'compressão. Se o seu vídeo tem céu, fumaça ou sombras, vale '
                  'testar "Alta"; se tem desenho ou texto, "Sem pontilhado" '
                  'fica ótimo e bem menor.',
            ),
            item(
              'Por que a estimativa é aproximada',
              'O peso depende de quanto a cena se mexe, e isso varia de vídeo '
                  'para vídeo. Tocando em "Medir", o app converte trechos de '
                  'menos de um segundo e mede o resultado real — a partir daí '
                  'o número fica preciso e continua valendo enquanto você '
                  'mexe nos outros controles.',
            ),
          ],
        ),
      ),
    );
  }
}
