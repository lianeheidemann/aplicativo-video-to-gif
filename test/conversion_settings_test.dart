import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/models/video_info.dart';

const _video = VideoInfo(
  path: '/tmp/exemplo.mp4',
  fileName: 'exemplo.mp4',
  rawWidth: 1080,
  rawHeight: 1920,
  durationSeconds: 5,
  frameRate: 30,
  bitrateBps: 6000000,
  fileSizeBytes: 3000000,
  codec: 'h264',
);

void main() {
  group('moldura: espessura e canvas', () {
    test(
      'o deslocamento do pad nunca ultrapassa o canvas, em qualquer largura',
      () {
        // Regressão: com moldura + fundo transparente, o FFmpeg monta o
        // quadro posicionando o vídeo no offset `thicknessPx:thicknessPx`.
        // Se o offset mais a área de conteúdo passar do canvas, o overlay
        // do FFmpeg deixa a borda assimétrica. Isso
        // acontecia quando a espessura era arredondada de formas
        // diferentes em [ConversionSettings.frameAreaDimensions] (para o
        // canvas) e em `FfmpegService._framedGraph` (para o offset do
        // pad) — ver histórico desta constante.
        for (final style in [
          FrameStyle.slim,
          FrameStyle.classic,
          FrameStyle.thin,
        ]) {
          for (final corner in CornerStyle.values) {
            for (var w = 2; w <= 2000; w += 2) {
              final settings = ConversionSettings(
                startSeconds: 0,
                endSeconds: 5,
                targetWidth: w,
                frame: FrameSettings(
                  style: style,
                  thicknessAtReference: style.defaultThickness,
                  corner: corner,
                  transparentBackground: true,
                ),
              );

              final (areaWidth, areaHeight, thickness) = settings
                  .frameAreaDimensions(_video);
              final (canvasWidth, canvasHeight) = settings.outputDimensions(
                _video,
              );
              final thicknessPx = thickness.round();

              expect(
                thicknessPx + areaWidth,
                lessThanOrEqualTo(canvasWidth),
                reason: 'largura: style=$style corner=$corner w=$w',
              );
              expect(
                thicknessPx + areaHeight,
                lessThanOrEqualTo(canvasHeight),
                reason: 'altura: style=$style corner=$corner w=$w',
              );

              // A borda deve sair sempre simétrica (mesma espessura dos
              // dois lados), não só "não estourar".
              expect(
                canvasWidth - thicknessPx - areaWidth,
                thicknessPx,
                reason: 'assimetria horizontal: style=$style w=$w',
              );
              expect(
                canvasHeight - thicknessPx - areaHeight,
                thicknessPx,
                reason: 'assimetria vertical: style=$style w=$w',
              );
            }
          }
        }
      },
    );

    test('moldura procedural preserva o formato e o tamanho escolhidos', () {
      final formats = <CropRect?>[
        null,
        CropRect.centered(_video, 1),
        CropRect.centered(_video, 4 / 5),
        CropRect.centered(_video, 16 / 9),
      ];

      for (final crop in formats) {
        for (final style in FrameStyle.values.where(
          (style) => style != FrameStyle.none,
        )) {
          final settings = ConversionSettings(
            startSeconds: 0,
            endSeconds: 5,
            targetWidth: 480,
            crop: crop,
            frame: FrameSettings(
              style: style,
              thicknessAtReference: style.defaultThickness,
            ),
          );

          expect(
            settings.outputDimensions(_video),
            settings.contentDimensions(_video),
            reason: 'style=$style crop=$crop',
          );
        }
      }
    });
  });
}
