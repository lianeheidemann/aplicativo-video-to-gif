import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/widgets/frame_painter.dart';

void main() {
  test('máscara arredondada mantém transparência e suaviza a borda', () async {
    const width = 64;
    const height = 64;
    final png = await rasterizeCornerMask(width, height, 24);
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();

    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      int valueAt(int x, int y) => data!.getUint8((y * width + x) * 4);

      expect(valueAt(0, 0), lessThan(16));
      expect(valueAt(width ~/ 2, height ~/ 2), 255);

      final transition = <int>{
        for (var y = 0; y < 24; y++)
          for (var x = 0; x < 24; x++) valueAt(x, y),
      };
      expect(transition, contains(0));
      expect(transition, contains(255));
      expect(transition.any((value) => value > 0 && value < 255), isTrue);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });
}
