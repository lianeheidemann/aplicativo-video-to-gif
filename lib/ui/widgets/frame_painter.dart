import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/frame_settings.dart';

/// Geometria de uma moldura já calculada para um [Size] específico: raio de
/// canto externo/interno, espessura em pixels e o retângulo onde o
/// conteúdo (vídeo) deve ser desenhado. Tudo em proporção ao tamanho
/// recebido — nunca pixels fixos —, para a moldura ficar nítida e
/// proporcional em qualquer resolução, seja a prévia na tela ou o GIF
/// exportado.
class FrameGeometry {
  const FrameGeometry({
    required this.outerRadius,
    required this.innerRadius,
    required this.thickness,
    required this.contentRect,
  });

  final double outerRadius;
  final double innerRadius;
  final double thickness;
  final Rect contentRect;

  factory FrameGeometry.of(Size size, FrameSettings settings) {
    if (settings.style == FrameStyle.none) {
      return FrameGeometry(
        outerRadius: 0,
        innerRadius: 0,
        thickness: 0,
        contentRect: Offset.zero & size,
      );
    }

    final shorterSide = size.shortestSide;
    final thickness = settings.thicknessFor(size.width);
    final outerRadius = settings.cornerRadiusFor(shorterSide);
    final innerRadius = (outerRadius - thickness).clamp(0.0, outerRadius);
    final contentRect = Rect.fromLTWH(
      thickness,
      thickness,
      (size.width - thickness * 2).clamp(0.0, size.width),
      (size.height - thickness * 2).clamp(0.0, size.height),
    );

    return FrameGeometry(
      outerRadius: outerRadius,
      innerRadius: innerRadius,
      thickness: thickness,
      contentRect: contentRect,
    );
  }

  /// Recorte arredondado da área de conteúdo, pronto para clipar o vídeo.
  RRect get contentClip =>
      RRect.fromRectAndRadius(contentRect, Radius.circular(innerRadius));
}

/// Desenha o fundo/borda da moldura em [canvas] para um retângulo de
/// [size], a partir de [settings]. Não desenha o conteúdo (vídeo) — isso é
/// feito por cima, fora daqui, recortado por [FrameGeometry.contentClip].
///
/// Sem "Fundo transparente": preenche todo o retângulo (inclusive os 4
/// cantos que sobram fora da forma arredondada) com a cor da moldura — um
/// cartão colorido com uma janela arredondada para o vídeo. Com "Fundo
/// transparente": preenche só a forma arredondada, deixando os cantos sem
/// nada (transparentes no PNG exportado, ou mostrando o que houver atrás,
/// na prévia).
void paintFrame(Canvas canvas, Size size, FrameSettings settings) {
  if (settings.style == FrameStyle.none) return;

  final rect = Offset.zero & size;
  final geometry = FrameGeometry.of(size, settings);
  final paint = Paint()..color = settings.color;

  if (settings.transparentBackground) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(geometry.outerRadius)),
      paint,
    );
  } else {
    canvas.drawRect(rect, paint);
  }
}

/// [CustomPainter] que desenha [paintFrame] por cima da prévia do vídeo no
/// editor, e também sabe se [rasterize]ar a mesma moldura em qualquer
/// resolução — a mesma lógica de desenho serve para a prévia (tamanho de
/// tela) e para a exportação (tamanho exato do GIF final), nunca duas
/// implementações divergentes.
class FramePainter extends CustomPainter {
  const FramePainter(this.settings);

  final FrameSettings settings;

  @override
  void paint(Canvas canvas, Size size) => paintFrame(canvas, size, settings);

  @override
  bool shouldRepaint(covariant FramePainter oldDelegate) =>
      oldDelegate.settings != settings;

  /// Rasteriza a moldura para um PNG de exatamente [width]x[height] pixels
  /// — usado antes de chamar o FFmpeg, para a moldura nunca ser um asset de
  /// resolução fixa sendo esticado, e sim gerada já no tamanho final exato
  /// da exportação.
  static Future<Uint8List> rasterize(
    int width,
    int height,
    FrameSettings settings,
  ) => rasterizeCanvas(
    width,
    height,
    (canvas, size) => paintFrame(canvas, size, settings),
  );
}

/// Rasteriza uma máscara de transparência: branco dentro do retângulo
/// arredondado de raio [outerRadius] (canvas de [width]x[height]), preto
/// fora dele. Usada pelo FFmpeg (via `alphamerge`) para recortar os 4
/// cantos do canvas que sobram fora da moldura quando "Fundo transparente"
/// está ligado — o GIF só suporta transparência de 1 bit, então a máscara
/// vira exatamente essa decisão binária por pixel.
Future<Uint8List> rasterizeCornerMask(
  int width,
  int height,
  double outerRadius,
) => rasterizeCanvas(width, height, (canvas, size) {
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = Colors.black);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(outerRadius)),
    Paint()..color = Colors.white,
  );
});

/// Grava um desenho de [width]x[height] pixels (feito por [paint]) como PNG
/// — a base compartilhada por [FramePainter.rasterize] e
/// [rasterizeCornerMask].
Future<Uint8List> rasterizeCanvas(
  int width,
  int height,
  void Function(Canvas canvas, Size size) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  paint(canvas, size);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
