import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/size_estimate.dart';
import 'package:video_to_gif/ui/widgets/labeled_section.dart';
import 'package:video_to_gif/ui/widgets/size_panel.dart';

SizeEstimate _estimate({
  required int bytes,
  EstimateConfidence confidence = EstimateConfidence.rough,
}) {
  return SizeEstimate(
    bytes: bytes,
    frames: 72,
    width: 480,
    height: 270,
    bytesPerPixel: 0.16,
    confidence: confidence,
    durationSeconds: 6,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required SizeEstimate estimate,
  VoidCallback? onMeasure,
  VoidCallback? onConvert,
  void Function(ShareTarget)? onFitTo,
  bool measuring = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: SizePanel(
          estimate: estimate,
          suggestion: 'Dica: 40% mais leve se baixar para 10 FPS.',
          measuring: measuring,
          onMeasure: onMeasure ?? () {},
          onConvert: onConvert ?? () {},
          onFitTo: onFitTo ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('SizePanel', () {
    testWidgets('mostra peso, classificação e detalhes do GIF', (tester) async {
      await _pumpPanel(tester, estimate: _estimate(bytes: 3 * 1024 * 1024));

      expect(find.text('3.0 MB'), findsOneWidget);
      expect(find.text('Bom'), findsOneWidget);
      expect(find.textContaining('72 quadros'), findsOneWidget);
      expect(find.textContaining('480×270 px'), findsOneWidget);
    });

    testWidgets('classifica um arquivo grande como muito pesado', (
      tester,
    ) async {
      await _pumpPanel(tester, estimate: _estimate(bytes: 30 * 1024 * 1024));

      expect(find.text('30 MB'), findsOneWidget);
      expect(find.text('Muito pesado'), findsOneWidget);
    });

    testWidgets('oferece medir enquanto a estimativa é aproximada', (
      tester,
    ) async {
      var chamou = false;
      await _pumpPanel(
        tester,
        estimate: _estimate(bytes: 3 * 1024 * 1024),
        onMeasure: () => chamou = true,
      );

      expect(find.textContaining('Aproximado'), findsOneWidget);

      await tester.tap(find.text('Medir'));
      expect(chamou, isTrue);
    });

    testWidgets('troca o botão por um selo depois de medir', (tester) async {
      await _pumpPanel(
        tester,
        estimate: _estimate(
          bytes: 3 * 1024 * 1024,
          confidence: EstimateConfidence.calibrated,
        ),
      );

      expect(find.text('Medir'), findsNothing);
      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
      expect(find.textContaining('Medido'), findsOneWidget);
    });

    testWidgets('desabilita o botão enquanto mede', (tester) async {
      var chamou = false;
      await _pumpPanel(
        tester,
        estimate: _estimate(bytes: 3 * 1024 * 1024),
        measuring: true,
        onMeasure: () => chamou = true,
      );

      expect(find.text('Medindo…'), findsOneWidget);
      await tester.tap(find.text('Medindo…'));
      expect(chamou, isFalse);
    });

    testWidgets('tocar num destino que não cabe pede o ajuste automático', (
      tester,
    ) async {
      ShareTarget? pedido;
      // 12 MB medidos: cabe no WhatsApp (16 MB), não cabe no Discord (10 MB).
      await _pumpPanel(
        tester,
        estimate: _estimate(
          bytes: 12 * 1024 * 1024,
          confidence: EstimateConfidence.calibrated,
        ),
        onFitTo: (target) => pedido = target,
      );

      await tester.tap(find.text('Discord (grátis)'));
      await tester.pump();

      expect(pedido?.name, 'Discord (grátis)');
    });

    testWidgets('destino que já cabe não dispara ajuste', (tester) async {
      var chamou = false;
      await _pumpPanel(
        tester,
        estimate: _estimate(
          bytes: 1 * 1024 * 1024,
          confidence: EstimateConfidence.calibrated,
        ),
        onFitTo: (_) => chamou = true,
      );

      await tester.tap(find.text('WhatsApp'));
      await tester.pump();

      expect(chamou, isFalse);
    });

    testWidgets('converte ao tocar no botão principal', (tester) async {
      var chamou = false;
      await _pumpPanel(
        tester,
        estimate: _estimate(bytes: 3 * 1024 * 1024),
        onConvert: () => chamou = true,
      );

      await tester.tap(find.text('Converter em GIF'));
      expect(chamou, isTrue);
    });
  });

  group('OptionChips', () {
    testWidgets('marca a opção atual e avisa quando outra é escolhida', (
      tester,
    ) async {
      int? escolhido;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionChips<int>(
              options: const [10, 12, 15],
              selected: 12,
              labelBuilder: (fps) => '$fps FPS',
              onSelected: (fps) => escolhido = fps,
            ),
          ),
        ),
      );

      final selecionado = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '12 FPS'),
      );
      expect(selecionado.selected, isTrue);

      await tester.tap(find.text('15 FPS'));
      expect(escolhido, 15);
    });
  });
}
