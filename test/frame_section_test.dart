import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/editor_page.dart';

// Regressão: a seção "Moldura" já teve as duas fileiras (estilos
// procedurais e molduras de imagem) fundidas numa lista só, o que tornou as
// molduras de imagem pouco descobríveis. Estes testes garantem que as duas
// fileiras sempre aparecem juntas, sem exceção, e que a seleção de uma
// nunca deixa a outra com uma marcação de "ativa" incorreta.
const _video = VideoInfo(
  path: '/tmp/video-inexistente-para-teste.mp4',
  fileName: 'video.mp4',
  rawWidth: 640,
  rawHeight: 360,
  durationSeconds: 10,
  frameRate: 30,
  bitrateBps: 1000000,
  fileSizeBytes: 1000000,
  codec: 'h264',
);

Future<void> _openFrameSection(WidgetTester tester) async {
  // Viewport retrato: em paisagem o app esconde as abas "Ajustar"/"Frame"
  // para aproveitar o espaço vertical, e o tamanho padrão de teste
  // (800x600) é "paisagem".
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settings = ConversionSettings.recommendedFor(_video);
  await tester.pumpWidget(
    MaterialApp(
      home: EditorPage(video: _video, initialSettings: settings),
    ),
  );
  // O player de vídeo nunca inicializa em teste (sem plugin real); dá
  // tempo dele desistir e marcar `_previewFailed` antes de seguir.
  await tester.pump(const Duration(seconds: 1));

  await tester.tap(find.text('Frame'));
  await tester.pump();
  await tester.tap(find.text('Moldura'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('as duas fileiras de moldura aparecem juntas, sem erro', (
    tester,
  ) async {
    await _openFrameSection(tester);

    expect(tester.takeException(), isNull);
    for (final key in [
      'frameStyleThumb_none',
      'frameStyleThumb_slim',
      'frameStyleThumb_classic',
      'frameStyleThumb_thin',
      'frameStyleThumb_story9x16',
      'imageFrameThumb_bundled_transparente',
      'imageFrameThumb_bundled_graphite',
      'imageFrameThumb_bundled_titanio',
      'imageFrameThumb_bundled_ceramica',
      'imageFrameThumb_bundled_neon',
      'imageFrameThumb_bundled_rose_gold',
    ]) {
      expect(
        find.byKey(ValueKey(key)),
        findsOneWidget,
        reason: '$key deveria estar na tela',
      );
    }
  });

  testWidgets(
    'selecionar uma moldura de imagem atualiza o resumo e desmarca "Sem moldura"',
    (tester) async {
      await _openFrameSection(tester);

      final semMoldura = find.byKey(const ValueKey('frameStyleThumb_none'));
      expect(
        find.descendant(
          of: semMoldura,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
        reason: 'antes de escolher, "Sem moldura" começa marcada',
      );

      await tester.tap(
        find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: semMoldura,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
        reason:
            '"Sem moldura" não pode continuar marcada com uma moldura de '
            'imagem ativa',
      );
      expect(
        find.text('Titânio'),
        findsWidgets,
        reason: 'o resumo da seção deve refletir a moldura de imagem ativa',
      );
    },
  );
}
