import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/size_estimate.dart';
import 'package:video_to_gif/ui/widgets/labeled_section.dart';
import 'package:video_to_gif/ui/widgets/size_panel.dart';

const _summary = '480×270 px · 12 FPS · 6.0 s · 256 cores';

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

/// Monta o painel numa superfície alta e rolável, como na produção.
///
/// No app o `SizePanel` é um filho do `ListView` do editor, então ele pode ser
/// tão alto quanto precisar. A superfície padrão do teste (800×600) é menor do
/// que o painel inteiro; sem isto o `Column` estoura e o erro de layout
/// mascara a asserção que interessa.
Future<void> _pumpPanel(
  WidgetTester tester, {
  required SizeEstimate estimate,
  int originalBytes = 24 * 1024 * 1024,
  VoidCallback? onMeasure,
  VoidCallback? onConvert,
  bool measuring = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SizePanel(
            estimate: estimate,
            originalBytes: originalBytes,
            suggestion: 'Dica: 40% mais leve se baixar para 10 FPS.',
            summary: _summary,
            measuring: measuring,
            onMeasure: onMeasure ?? () {},
            onConvert: onConvert ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SizePanel', () {
    testWidgets('mostra peso, classificação e resumo das configurações', (
      tester,
    ) async {
      await _pumpPanel(tester, estimate: _estimate(bytes: 3 * 1024 * 1024));

      expect(find.text('3.0 MB'), findsOneWidget);
      expect(find.text('Moderado'), findsWidgets);
      expect(find.text(_summary), findsOneWidget);
    });

    testWidgets('classifica um arquivo grande como pesado', (tester) async {
      await _pumpPanel(tester, estimate: _estimate(bytes: 30 * 1024 * 1024));

      expect(find.text('30 MB'), findsOneWidget);
      expect(_estimate(bytes: 30 * 1024 * 1024).verdict, SizeVerdict.tooHeavy);
      expect(find.text('Pesado'), findsWidgets);
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

      // Sem calibração o rótulo é só "Estimativa"; medido vira
      // "Estimativa medida".
      expect(find.textContaining('Estimativa: '), findsOneWidget);

      await tester.tap(find.text('Medir'));
      expect(chamou, isTrue);
    });

    testWidgets('depois de medir, anuncia a faixa medida e oferece remedir', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        estimate: _estimate(
          bytes: 3 * 1024 * 1024,
          confidence: EstimateConfidence.calibrated,
        ),
      );

      expect(find.textContaining('Estimativa medida: '), findsOneWidget);
      expect(find.text('Medir'), findsNothing);
      expect(find.text('Medir novamente'), findsOneWidget);
    });

    testWidgets('a faixa aperta quando a estimativa é medida', (tester) async {
      final aproximada = _estimate(bytes: 3 * 1024 * 1024);
      final medida = _estimate(
        bytes: 3 * 1024 * 1024,
        confidence: EstimateConfidence.calibrated,
      );

      await _pumpPanel(tester, estimate: medida);

      expect(find.textContaining(medida.formattedRange), findsOneWidget);
      expect(
        medida.highBytes - medida.lowBytes,
        lessThan(aproximada.highBytes - aproximada.lowBytes),
      );
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

    testWidgets('converte ao tocar no botão principal', (tester) async {
      var chamou = false;
      await _pumpPanel(
        tester,
        estimate: _estimate(bytes: 3 * 1024 * 1024),
        onConvert: () => chamou = true,
      );

      await tester.tap(find.text('Converter em GIF ✨'));
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
