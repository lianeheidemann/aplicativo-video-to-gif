import 'package:flutter/material.dart';

import '../models/conversion_settings.dart';
import '../models/size_estimate.dart';
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
  });

  final ConversionResult result;
  final SizeEstimate estimate;
  final ConversionSettings settings;

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: theme.colorScheme.surfaceContainerHigh,
              child: Center(
                // Image.file anima GIFs automaticamente, então isso já é
                // uma prévia real do resultado.
                child: Image.file(
                  result.file,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
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
                  _row('Dimensões', '${result.width}×${result.height} px'),
                  _row('Quadros', '${result.frames}'),
                  _row(
                    'Duração',
                    '${widget.settings.outputDurationSeconds.toStringAsFixed(1)}s '
                        'a ${widget.settings.fps} FPS',
                  ),
                  _row('Tempo de conversão', '${result.elapsed.inSeconds}s'),
                  _row(
                    'Previsto antes de converter',
                    widget.estimate.formatted,
                  ),
                  _row('Diferença da previsão', _accuracy()),
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
    );
  }

  /// Linha "rótulo à esquerda, valor à direita" usada no card de detalhes.
  Widget _row(String label, String value) {
    final theme = Theme.of(context);
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

  /// Mostrar o erro da previsão é honesto e ajuda o usuário a calibrar a
  /// própria confiança no número da tela anterior.
  String _accuracy() {
    final predicted = widget.estimate.bytes;
    if (predicted <= 0) return '—';
    final diff = (widget.result.bytes - predicted) / predicted * 100;
    final sign = diff >= 0 ? '+' : '';
    return '$sign${diff.toStringAsFixed(0)}%';
  }
}
