import 'package:flutter/material.dart';

import '../models/conversion_settings.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/output_service.dart';
import '../theme.dart';

/// Tela final: exibe o GIF gerado, seu peso real (comparado à estimativa) e
/// as ações de salvar na galeria ou compartilhar.
class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.result,
    required this.estimate,
    required this.settings,
    required this.video,
  });

  final ConversionResult result;
  final SizeEstimate estimate;
  final ConversionSettings settings;

  /// Vídeo original, usado para mostrar as dimensões/quadros/duração de
  /// origem ao lado dos valores do GIF gerado.
  final VideoInfo video;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  static const _output = OutputService();

  bool _saving = false;
  bool _saved = false;

  /// Salva o GIF na galeria do aparelho e mostra o resultado num snackbar.
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _output.saveToGallery(widget.result.file);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      _message('GIF salvo na galeria.');
    } on OutputException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message(e.message);
    }
  }

  /// Mostra uma snackbar simples, substituindo qualquer uma já visível.
  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final verdict = SizeVerdict.forBytes(result.bytes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GIF pronto'),
        actions: [
          IconButton(
            tooltip: 'Compartilhar',
            onPressed: () => _output.share(result.file),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: theme.colorScheme.surfaceContainerHigh,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Com moldura, o GIF tem cantos transparentes — um
                    // fundo xadrez deixa isso visível na prévia (senão só
                    // apareceria a cor do Container por trás).
                    if (widget.settings.frameStyle != FrameStyle.none)
                      const Positioned.fill(
                        child: CustomPaint(painter: _CheckerboardPainter()),
                      ),
                    // Image.file anima GIFs automaticamente, então isso já é
                    // uma prévia real do resultado.
                    Image.file(
                      result.file,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          result.formattedSize,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: verdictColor(verdict, theme.colorScheme),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          verdict.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: verdictColor(verdict, theme.colorScheme),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verdict.advice,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Divider(height: 28),
                    Text(
                      'Tamanho',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    _row(
                      'Original',
                      SizeEstimate.formatBytes(widget.video.fileSizeBytes),
                    ),
                    _row('Previsto', widget.estimate.formatted),
                    _row(
                      'Convertido',
                      result.formattedSize,
                      warn: result.bytes > widget.video.fileSizeBytes,
                    ),
                    _row('Diferença da previsão', _predictionDiff()),
                    _row(
                      'Quadros',
                      '${result.frames}',
                      original: '${_originalFrames()}',
                    ),
                    _row(
                      'Duração',
                      '${widget.settings.outputDurationSeconds.toStringAsFixed(1)}s '
                          'a ${widget.settings.fps} FPS',
                      original:
                          '${widget.video.durationSeconds.toStringAsFixed(1)}s',
                    ),
                    _row(
                      'Dimensões',
                      '${result.width}×${result.height} px',
                      original:
                          '${widget.video.width}×${widget.video.height} px',
                    ),
                    const Divider(height: 28),
                    Text(
                      'Qualidade',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    _row('Cores', '${widget.settings.colors} cores'),
                    _row('Suavização', widget.settings.dither.label),
                    _row('Paleta', widget.settings.palette.label),
                    const Divider(height: 28),
                    _row('Tempo de conversão', '${result.elapsed.inSeconds}s'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving || _saved ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_saved ? Icons.check : Icons.download),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : _saved
                    ? 'Salvo na galeria'
                    : 'Salvar na galeria',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _output.share(result.file),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.tune),
              label: const Text('Voltar e ajustar de novo'),
            ),
          ],
        ),
      ),
    );
  }

  /// Linha "rótulo à esquerda, valor à direita" usada no card de detalhes.
  /// Quando [original] é informado, mostra o valor do vídeo de origem antes
  /// do valor do GIF gerado (ex.: "1920×1080 px → 480×270 px"). [warn]
  /// destaca o valor final em laranja quando ele piorou em relação à
  /// origem (ex.: GIF mais pesado que o vídeo original).
  Widget _row(
    String label,
    String value, {
    String? original,
    bool warn = false,
  }) {
    final theme = Theme.of(context);
    const warnColor = Color(0xFFE6A15D);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (original != null) ...[
                Text(
                  original,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 12,
                    color: warn
                        ? warnColor
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: warn ? warnColor : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Estimativa do número de quadros do vídeo original (duração × FPS de
  /// origem), já que o [VideoInfo] não guarda a contagem exata.
  int _originalFrames() =>
      (widget.video.durationSeconds * widget.video.frameRate).round();

  /// Diferença percentual entre o tamanho previsto e o convertido de
  /// verdade (ex.: "-34%" quando o GIF saiu mais leve que a estimativa).
  String _predictionDiff() {
    final estimated = widget.estimate.bytes;
    final actual = widget.result.bytes;
    final percent = ((actual - estimated) / estimated * 100).round();
    return percent > 0 ? '+$percent%' : '$percent%';
  }
}

/// Fundo em xadrez usado atrás da prévia do GIF, para deixar visível a
/// transparência trazida pela moldura.
class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  static const _tile = 12.0;
  static const _light = Color(0xFFE0E0E0);
  static const _dark = Color(0xFFBDBDBD);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var y = 0.0; y < size.height; y += _tile) {
      for (var x = 0.0; x < size.width; x += _tile) {
        final isEven = ((x / _tile).floor() + (y / _tile).floor()) % 2 == 0;
        paint.color = isEven ? _light : _dark;
        canvas.drawRect(Rect.fromLTWH(x, y, _tile, _tile), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
