import 'package:flutter/material.dart';

import '../../models/size_estimate.dart';
import '../../theme.dart';

/// Painel fixo no rodapé do editor: mostra o peso previsto, o que ele
/// significa e o que fazer se estiver alto.
class SizePanel extends StatelessWidget {
  const SizePanel({
    super.key,
    required this.estimate,
    required this.suggestion,
    required this.measuring,
    required this.onMeasure,
    required this.onConvert,
    required this.onFitTo,
  });

  final SizeEstimate estimate;
  final String suggestion;
  final bool measuring;
  final VoidCallback onMeasure;
  final VoidCallback onConvert;
  final void Function(ShareTarget target) onFitTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verdictColor(estimate.verdict, theme.colorScheme);
    final calibrated = estimate.confidence == EstimateConfidence.calibrated;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              estimate.formatted,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                estimate.verdict.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          calibrated
                              ? 'Medido: entre ${estimate.formattedRange}'
                              : 'Aproximado: entre ${estimate.formattedRange}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${estimate.frames} quadros · '
                          '${estimate.width}×${estimate.height} px · '
                          '${estimate.durationSeconds.toStringAsFixed(1)}s',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!calibrated)
                    OutlinedButton.icon(
                      onPressed: measuring ? null : onMeasure,
                      icon: measuring
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.speed, size: 18),
                      label: Text(measuring ? 'Medindo…' : 'Medir'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                  else
                    Tooltip(
                      message: EstimateConfidence.calibrated.explanation,
                      child: Icon(
                        Icons.verified_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _TargetsRow(estimate: estimate, onFitTo: onFitTo),
              const SizedBox(height: 8),
              Text(suggestion, style: theme.textTheme.bodySmall),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onConvert,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Converter em GIF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mostra em quais destinos o GIF cabe. Tocar em um destino que não cabe
/// ajusta as configurações automaticamente para caber.
class _TargetsRow extends StatelessWidget {
  const _TargetsRow({required this.estimate, required this.onFitTo});

  final SizeEstimate estimate;
  final void Function(ShareTarget target) onFitTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ShareTarget.targets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final target = ShareTarget.targets[index];
          final fits = estimate.fitsIn(target);

          return ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              fits ? Icons.check_circle : Icons.error_outline,
              size: 16,
              color: fits ? const Color(0xFF2E7D32) : theme.colorScheme.error,
            ),
            label: Text(target.name, style: theme.textTheme.labelSmall),
            onPressed: fits ? null : () => onFitTo(target),
            tooltip: fits
                ? 'Cabe no limite de ${SizeEstimate.formatBytes(target.limitBytes)}'
                : 'Toque para ajustar e caber em '
                      '${SizeEstimate.formatBytes(target.limitBytes)}',
          );
        },
      ),
    );
  }
}
