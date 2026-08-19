import 'package:flutter/material.dart';

import '../../models/size_estimate.dart';
import '../../theme.dart';

/// Painel final do editor: compara o peso do vídeo original com a
/// estimativa do GIF, dá dicas de como reduzi-lo e traz o botão de
/// converter.
class SizePanel extends StatelessWidget {
  const SizePanel({
    super.key,
    required this.estimate,
    required this.originalBytes,
    required this.summary,
    required this.measuring,
    required this.onMeasure,
    required this.onConvert,
  });

  final SizeEstimate estimate;

  /// Tamanho em bytes do vídeo original, mostrado ao lado da estimativa do
  /// GIF para o usuário comparar o antes e o depois.
  final int originalBytes;
  final String summary;
  final bool measuring;
  final VoidCallback onMeasure;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verdictColor(estimate.verdict, theme.colorScheme);
    final calibrated = estimate.confidence == EstimateConfidence.calibrated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(Icons.data_usage_rounded, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Estimativa de tamanho',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        SizeEstimate.formatBytes(originalBytes),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 10,
                        left: 6,
                        right: 6,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 17,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      estimate.formatted,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _verdictLabel(estimate.verdict),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${calibrated ? 'Estimativa medida' : 'Estimativa'}: ${estimate.formattedRange}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                _ImpactBar(verdict: estimate.verdict),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: measuring ? null : onMeasure,
                  icon: measuring
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 19),
                  label: Text(
                    measuring
                        ? 'Medindo…'
                        : calibrated
                        ? 'Medir novamente'
                        : 'Medir',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: onConvert,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome),
              SizedBox(width: 8),
              Text('Converter em GIF'),
              SizedBox(width: 8),
              Icon(Icons.auto_awesome),
            ],
          ),
        ),
      ],
    );
  }

  /// Rótulo curto do veredito, usado no selo ao lado do tamanho.
  static String _verdictLabel(SizeVerdict verdict) => switch (verdict) {
    SizeVerdict.light => 'Leve',
    SizeVerdict.good => 'Moderado',
    SizeVerdict.heavy || SizeVerdict.tooHeavy => 'Pesado',
  };
}

/// Barra "leve → moderado → pesado" com um marcador indicando onde o
/// veredito atual cai.
class _ImpactBar extends StatelessWidget {
  const _ImpactBar({required this.verdict});

  final SizeVerdict verdict;

  @override
  Widget build(BuildContext context) {
    // Posição horizontal (0-1) do marcador na barra, por veredito.
    final position = switch (verdict) {
      SizeVerdict.light => 0.16,
      SizeVerdict.good => 0.5,
      SizeVerdict.heavy => 0.78,
      SizeVerdict.tooHeavy => 0.94,
    };

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: 18,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF58C78C),
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Container(height: 8, color: Color(0xFFB8B36A)),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE57373),
                            borderRadius: BorderRadius.horizontal(
                              right: Radius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: (constraints.maxWidth - 14) * position,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Row(
          children: [
            Expanded(child: Text('Leve', style: TextStyle(fontSize: 11))),
            Expanded(
              child: Text(
                'Moderado',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ),
            Expanded(
              child: Text(
                'Pesado',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
