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

const _customAspectPreset = AspectPreset(
  'Personalizado',
  -1,
  hint: 'Largura e altura livres',
);

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
  late ComplexityProfile _profile = SizeEstimator.profileFromSource(widget.video);

  VideoPlayerController? _player;
  bool _previewFailed = false;
  bool _measuring = false;
  bool _openingConversion = false;
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
      await controller.dispose();
      if (mounted) setState(() => _previewFailed = true);
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

  Future<void> _measure() async {
    setState(() => _measuring = true);
    try {
      final profile = await _ffmpeg.calibrate(video: _video, settings: _settings);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _measuring = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _measuring = false);
      _showMessage(
        'Não deu para medir este trecho. A estimativa aproximada continua valendo.',
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
    if (_openingConversion) return;
    setState(() => _openingConversion = true);
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

    if (mounted) setState(() => _openingConversion = false);
  }

  @override
  Widget build(BuildContext context) {
    final (width, height) = _settings.outputDimensions(_video);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustar GIF'),
        actions: [
          IconButton(
            tooltip: 'Como deixar o GIF mais leve',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            _preview(),
            const SizedBox(height: 18),
            _durationSection(),
            _aspectSection(),
            _speedSection(),
            _resolutionSection(),
            _fpsSection(),
            _colorSection(),
            SizePanel(
              estimate: _estimate,
              suggestion: SizeEstimator.suggestionFor(
                settings: _settings,
                video: _video,
                profile: _profile,
              ),
              summary:
                  '$width×$height px · ${_settings.fps} FPS · '
                  '${_settings.outputDurationSeconds.toStringAsFixed(1)} s · '
                  '${_settings.colors} cores',
              measuring: _measuring,
              onMeasure: _measure,
              onConvert: _openingConversion ? () {} : _convert,
              onFitTo: _fitTo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final theme = Theme.of(context);
    final player = _player;

    if (_previewFailed) {
      return Container(
        constraints: const BoxConstraints(minHeight: 180),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            const Text('Prévia indisponível para este codec'),
            const SizedBox(height: 4),
            Text(
              'A conversão continua funcionando normalmente.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (player == null || !player.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _video.aspectRatio,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
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
                          final position =
                              player.value.position.inMilliseconds / 1000;
                          if (position < _settings.startSeconds ||
                              position >= _settings.endSeconds) {
                            await _seekPreview(_settings.startSeconds);
                          }
                          await player.play();
                        }
                        if (mounted) setState(() {});
                      },
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            player.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _previewTimeline(player),
        ],
      ),
    );
  }

  Widget _previewTimeline(VideoPlayerController player) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final duration =
            _video.durationSeconds <= 0 ? 1.0 : _video.durationSeconds;
        final current = player.value.position.inMilliseconds / 1000.0;
        final start = (_settings.startSeconds / duration).clamp(0.0, 1.0);
        final end = (_settings.endSeconds / duration).clamp(0.0, 1.0);
        final position = (current / duration).clamp(0.0, 1.0);

        if (player.value.isPlaying && current >= _settings.endSeconds) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await player.seekTo(
              Duration(milliseconds: (_settings.startSeconds * 1000).round()),
            );
          });
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final ratio =
                          (details.localPosition.dx / width).clamp(0.0, 1.0);
                      _seekPreview(ratio * duration);
                    },
                    child: SizedBox(
                      height: 24,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          Positioned(
                            left: width * start,
                            width: width * (end - start),
                            child: Container(
                              height: 7,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (width - 3) * position,
                            child: Container(
                              width: 3,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (width - 2) * start,
                            child: Container(
                              width: 2,
                              height: 18,
                              color: Colors.white70,
                            ),
                          ),
                          Positioned(
                            left: (width - 2) * end,
                            child: Container(
                              width: 2,
                              height: 18,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatSeconds(_settings.startSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'Atual ${_formatSeconds(current.clamp(0, duration).toDouble())}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Text(
                    _formatSeconds(_settings.endSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _durationSection() {
    final start = _settings.startSeconds;
    final end = _settings.endSeconds;

    return LabeledSection(
      icon: Icons.content_cut_rounded,
      title: 'Duração',
      value: '${_settings.sourceDurationSeconds.toStringAsFixed(1)} s',
      hint: 'Selecione a parte do vídeo que deseja transformar em GIF.',
      tip: 'Cortes menores geram GIFs menores.',
      child: Column(
        children: [
          RangeSlider(
            min: 0,
            max: _video.durationSeconds,
            divisions: (_video.durationSeconds * 10).round().clamp(1, 2000),
            values: RangeValues(start, end),
            labels: RangeLabels(_formatSeconds(start), _formatSeconds(end)),
            onChanged: (values) {
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
          const SizedBox(height: 4),
          _metricRow('Início', _formatSeconds(start)),
          _metricRow('Fim', _formatSeconds(end)),
          _metricRow(
            'Duração total',
            '${_settings.sourceDurationSeconds.toStringAsFixed(1)} s',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _update(
                  _settings.copyWith(
                    startSeconds: widget.initialSettings.startSeconds,
                    endSeconds: widget.initialSettings.endSeconds,
                  ),
                );
                _seekPreview(widget.initialSettings.startSeconds);
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Redefinir'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aspectSection() {
    final crop = _settings.crop;
    final visiblePresets = <AspectPreset>[
      ...AspectPreset.presets.take(5),
      _customAspectPreset,
    ];

    return LabeledSection(
      icon: Icons.crop_rounded,
      title: 'Formato da janela',
      value: _aspect.label,
      hint: 'Escolha um formato e ajuste o tamanho e a posição da janela.',
      tip: _aspect == _customAspectPreset
          ? 'No modo Personalizado, largura e altura podem ser alteradas separadamente.'
          : 'Os formatos fixos mantêm a proporção enquanto você redimensiona a janela.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionChips<AspectPreset>(
            options: visiblePresets,
            selected: visiblePresets.contains(_aspect)
                ? _aspect
                : visiblePresets.first,
            labelBuilder: (preset) => preset.hint.isEmpty
                ? preset.label
                : '${preset.label} — ${preset.hint}',
            onSelected: _selectAspectPreset,
          ),
          if (crop != null) ...[
            const SizedBox(height: 18),
            _cropSizeSummary(crop),
            const SizedBox(height: 12),
            if (_aspect == _customAspectPreset)
              _customCropSizeControls(crop)
            else if (_aspect.ratio != null)
              _lockedCropSizeControl(crop, _aspect.ratio!),
            const SizedBox(height: 12),
            _cropPositionControls(crop),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _resetCurrentCrop(),
                icon: const Icon(Icons.center_focus_strong_rounded),
                label: const Text('Centralizar e redefinir'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _selectAspectPreset(AspectPreset preset) {
    setState(() {
      _aspect = preset;

      if (preset == _customAspectPreset) {
        _settings = _settings.copyWith(
          crop: _settings.crop ?? _defaultCustomCrop(),
        );
        return;
      }

      if (preset.ratio == null) {
        _settings = _settings.copyWith(clearCrop: true);
        return;
      }

      _settings = _settings.copyWith(
        crop: CropRect.centered(_video, preset.ratio!),
      );
    });
  }

  CropRect _defaultCustomCrop() {
    final width = _even(((_video.width * 0.8).round()).clamp(2, _video.width));
    final height =
        _even(((_video.height * 0.8).round()).clamp(2, _video.height));
    return _cropAroundCenter(width, height);
  }

  Widget _cropSizeSummary(CropRect crop) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.aspect_ratio_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Janela de recorte',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${crop.width}×${crop.height} px',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockedCropSizeControl(CropRect crop, double ratio) {
    final maxCrop = CropRect.centered(_video, ratio);
    final widthScale = crop.width / maxCrop.width;
    final heightScale = crop.height / maxCrop.height;
    final scale = widthScale < heightScale ? widthScale : heightScale;
    final value = scale.clamp(0.2, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subLabel('Tamanho da janela · ${(value * 100).round()}%'),
        Slider(
          min: 0.2,
          max: 1,
          divisions: 80,
          value: value,
          label: '${(value * 100).round()}%',
          onChanged: (nextScale) {
            var width = _even((maxCrop.width * nextScale).round());
            var height = _even((width / ratio).round());

            if (height > maxCrop.height) {
              height = _even(maxCrop.height);
              width = _even((height * ratio).round());
            }

            _update(
              _settings.copyWith(
                crop: _cropAroundCenter(width, height, around: crop),
              ),
            );
          },
        ),
        Text(
          'A proporção ${_aspect.label} permanece travada.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _customCropSizeControls(CropRect crop) {
    final minWidth = _video.width < 32 ? 2 : 32;
    final minHeight = _video.height < 32 ? 2 : 32;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subLabel('Largura · ${crop.width} px'),
        Slider(
          min: minWidth.toDouble(),
          max: _video.width.toDouble(),
          value: crop.width.clamp(minWidth, _video.width).toDouble(),
          label: '${crop.width} px',
          onChanged: (value) {
            final width = _even(value.round());
            _update(
              _settings.copyWith(
                crop: _cropAroundCenter(width, crop.height, around: crop),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        _subLabel('Altura · ${crop.height} px'),
        Slider(
          min: minHeight.toDouble(),
          max: _video.height.toDouble(),
          value: crop.height.clamp(minHeight, _video.height).toDouble(),
          label: '${crop.height} px',
          onChanged: (value) {
            final height = _even(value.round());
            _update(
              _settings.copyWith(
                crop: _cropAroundCenter(crop.width, height, around: crop),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _cropPositionControls(CropRect crop) {
    final horizontalRoom = _video.width - crop.width;
    final verticalRoom = _video.height - crop.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (horizontalRoom > 0) ...[
          _subLabel('Posição horizontal'),
          Slider(
            min: 0,
            max: horizontalRoom.toDouble(),
            value: crop.x.clamp(0, horizontalRoom).toDouble(),
            onChanged: (value) {
              _update(
                _settings.copyWith(crop: crop.copyWith(x: value.round())),
              );
            },
          ),
        ],
        if (verticalRoom > 0) ...[
          _subLabel('Posição vertical'),
          Slider(
            min: 0,
            max: verticalRoom.toDouble(),
            value: crop.y.clamp(0, verticalRoom).toDouble(),
            onChanged: (value) {
              _update(
                _settings.copyWith(crop: crop.copyWith(y: value.round())),
              );
            },
          ),
        ],
        if (horizontalRoom <= 0 && verticalRoom <= 0)
          Text(
            'A janela ocupa todo o vídeo.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }

  void _resetCurrentCrop() {
    if (_aspect == _customAspectPreset) {
      _update(_settings.copyWith(crop: _defaultCustomCrop()));
      return;
    }

    if (_aspect.ratio == null) {
      _update(_settings.copyWith(clearCrop: true));
      return;
    }

    _update(
      _settings.copyWith(crop: CropRect.centered(_video, _aspect.ratio!)),
    );
  }

  CropRect _cropAroundCenter(int width, int height, {CropRect? around}) {
    var safeWidth = width.clamp(2, _video.width);
    var safeHeight = height.clamp(2, _video.height);
    safeWidth = _even(safeWidth);
    safeHeight = _even(safeHeight);

    final centerX = around == null
        ? _video.width / 2
        : around.x + around.width / 2;
    final centerY = around == null
        ? _video.height / 2
        : around.y + around.height / 2;

    final maxX = _video.width - safeWidth;
    final maxY = _video.height - safeHeight;
    final x = (centerX - safeWidth / 2).round().clamp(0, maxX);
    final y = (centerY - safeHeight / 2).round().clamp(0, maxY);

    return CropRect(
      x: x,
      y: y,
      width: safeWidth,
      height: safeHeight,
    );
  }

  int _even(int value) {
    if (value <= 2) return 2;
    return value.isEven ? value : value - 1;
  }

  Widget _speedSection() {
    return LabeledSection(
      icon: Icons.speed_rounded,
      title: 'Velocidade',
      value: '${_formatSpeed(_settings.speed)}x',
      hint:
          'Acelerar encurta o GIF e economiza espaço; velocidades menores aumentam a duração.',
      tip: '1x oferece o melhor equilíbrio entre duração e tamanho.',
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
    final selected = available.contains(_settings.targetWidth)
        ? _settings.targetWidth
        : available.last;

    return LabeledSection(
      icon: Icons.photo_size_select_large_rounded,
      title: 'Resolução',
      value: '$width×$height',
      hint: 'Reduzir a largura diminui significativamente o tamanho do arquivo.',
      tip: '480 px oferece boa qualidade para a maioria dos casos.',
      child: OptionChips<int>(
        options: available,
        selected: selected,
        labelBuilder: (w) => '$w px',
        onSelected: (w) => _update(_settings.copyWith(targetWidth: w)),
      ),
    );
  }

  Widget _fpsSection() {
    return LabeledSection(
      icon: Icons.animation_rounded,
      title: 'Quadros por segundo (FPS)',
      value: '${_settings.fps} FPS',
      hint:
          'Mais FPS deixa a animação mais fluida, mas aumenta o tamanho do arquivo.',
      tip: '12 FPS é um bom equilíbrio entre fluidez e tamanho.',
      child: OptionChips<int>(
        options: ConversionSettings.fpsOptions,
        selected: _settings.fps,
        labelBuilder: (fps) => '$fps FPS',
        onSelected: (fps) => _update(_settings.copyWith(fps: fps)),
      ),
    );
  }

  Widget _colorSection() {
    final colors = <int>{
      ...ConversionSettings.primaryColorOptions,
      _settings.colors,
    }.toList()
      ..sort();

    return LabeledSection(
      icon: Icons.palette_outlined,
      title: 'Qualidade das cores',
      value: '${_settings.colors} cores · ${_settings.dither.label}',
      hint: 'Mais cores melhoram a qualidade, mas aumentam o tamanho do arquivo.',
      tip:
          '128 cores costuma equilibrar bem qualidade e tamanho; 256 preserva mais detalhes.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionChips<int>(
            options: colors,
            selected: _settings.colors,
            labelBuilder: (value) => switch (value) {
              64 => '64 cores — Menor tamanho',
              128 => '128 cores — Equilibrado',
              256 => '256 cores — Melhor qualidade',
              _ => '$value cores',
            },
            onSelected: (value) => _update(_settings.copyWith(colors: value)),
          ),
          const SizedBox(height: 18),
          _subLabel('Suavização de cor · ${_settings.dither.description}'),
          OptionChips<DitherMode>(
            options: DitherMode.values,
            selected: _settings.dither,
            labelBuilder: (d) => d.label,
            onSelected: (d) => _update(_settings.copyWith(dither: d)),
          ),
          const SizedBox(height: 18),
          _subLabel('Paleta · ${_settings.palette.description}'),
          OptionChips<PaletteMode>(
            options: PaletteMode.values,
            selected: _settings.palette,
            labelBuilder: (p) => p.label,
            onSelected: (p) => _update(_settings.copyWith(palette: p)),
          ),
          const SizedBox(height: 8),
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

  Widget _metricRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
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
}

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
        const veil = Color(0x8C000000);

        Widget handle() => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black54),
              ),
            );

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
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                    Positioned(left: -5, top: -5, child: handle()),
                    Positioned(right: -5, top: -5, child: handle()),
                    Positioned(left: -5, bottom: -5, child: handle()),
                    Positioned(right: -5, bottom: -5, child: handle()),
                  ],
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
              'Cada segundo adiciona novos quadros. Cortar um trecho é uma das formas mais eficientes de reduzir o tamanho.',
            ),
            item(
              '2. Resolução — efeito muito forte',
              'Quanto maior a área de cada quadro, maior tende a ser o GIF. 480 px costuma funcionar bem para compartilhamento.',
            ),
            item(
              '3. FPS — fluidez versus tamanho',
              'Mais quadros deixam o movimento mais suave, mas aumentam o arquivo. 12 FPS é um bom ponto de partida.',
            ),
            item(
              '4. Janela de recorte',
              'Você pode redimensionar formatos fixos mantendo a proporção ou usar o modo Personalizado para definir largura e altura livremente.',
            ),
            item(
              '5. Cores e suavização',
              'Mais cores e dither preservam gradientes e detalhes, mas podem reduzir a eficiência da compressão.',
            ),
            item(
              'Por que medir novamente?',
              'A estimativa inicial é aproximada. Ao medir, o app usa o FFmpeg em uma pequena amostra do próprio vídeo para calibrar o cálculo.',
            ),
          ],
        ),
      ),
    );
  }
}
