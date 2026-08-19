import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../models/conversion_settings.dart';
import '../ui/painters/phone_frame_painter.dart';

/// Rasteriza a moldura de [style] como um PNG com canal alpha, no tamanho
/// exato [width]x[height] (o canvas final do GIF: janela de conteúdo mais
/// borda).
///
/// Chamado uma única vez por conversão — o custo é o de renderizar uma
/// imagem estática, não por quadro do vídeo. O FFmpeg depois só sobrepõe
/// esse PNG em cada quadro via `overlay`, tão barato quanto uma marca
/// d'água estática.
class FrameRenderService {
  Future<File> renderFramePng({
    required FrameStyle style,
    required int borderPx,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(width.toDouble(), height.toDouble());

    paintPhoneFrame(canvas, size, style: style, borderPx: borderPx.toDouble());

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    if (byteData == null) {
      throw StateError('Não foi possível rasterizar a moldura.');
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/moldura_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return file;
  }
}
