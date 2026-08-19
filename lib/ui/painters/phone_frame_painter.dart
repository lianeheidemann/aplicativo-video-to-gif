import 'dart:ui' as ui;

import '../../models/conversion_settings.dart';

/// Desenha a moldura tipo "celular" de [style] no [canvas], ocupando
/// exatamente [size] (a janela de conteúdo mais a borda dos dois lados).
///
/// [borderPx] é a espessura da borda já calculada por
/// `ConversionSettings.frameBorderPx`, para que o desenho use sempre o mesmo
/// número usado para posicionar o vídeo por baixo no FFmpeg — não é
/// recalculada aqui.
///
/// Tudo fora do retângulo arredondado externo e dentro da janela de
/// conteúdo (o retângulo interno, onde o vídeo aparece por baixo) fica sem
/// nenhum traço, ou seja, transparente no PNG final. Como o desenho é
/// refeito no tamanho exato pedido a cada chamada — em vez de esticar um
/// bitmap fixo — a moldura nunca perde nitidez, em qualquer proporção.
void paintPhoneFrame(
  ui.Canvas canvas,
  ui.Size size, {
  required FrameStyle style,
  required double borderPx,
}) {
  if (style == FrameStyle.none || borderPx <= 0) return;

  final radius = ui.Radius.circular(
    style.cornerRadius(size.width.round(), size.height.round()),
  );
  final outer = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(0, 0, size.width, size.height),
    radius,
  );
  final inner = ui.Rect.fromLTWH(
    borderPx,
    borderPx,
    size.width - borderPx * 2,
    size.height - borderPx * 2,
  );

  final outerPath = ui.Path()..addRRect(outer);
  final innerPath = ui.Path()..addRect(inner);
  var bezelPath = ui.Path.combine(
    ui.PathOperation.difference,
    outerPath,
    innerPath,
  );

  // O GIF só suporta transparência binária (sem meio-tom), então evitamos
  // antialiasing nas bordas entre opaco e transparente — ele seria
  // binarizado de forma imprevisível pelo palettegen/paletteuse de
  // qualquer forma.
  final bezelPaint = ui.Paint()
    ..color = style.color
    ..isAntiAlias = false;

  if (style.hasNotch) {
    final notchWidth = size.width * 0.28;
    final notchHeight = borderPx * 0.55;
    final notch = ui.RRect.fromRectAndRadius(
      ui.Rect.fromCenter(
        center: ui.Offset(size.width / 2, borderPx / 2),
        width: notchWidth,
        height: notchHeight,
      ),
      ui.Radius.circular(notchHeight / 2),
    );
    // Recorte tipo câmera/alto-falante: some da borda, revela a
    // transparência de fundo, como um "punch-hole" real.
    bezelPath = ui.Path.combine(
      ui.PathOperation.difference,
      bezelPath,
      ui.Path()..addRRect(notch),
    );
  }

  canvas.drawPath(bezelPath, bezelPaint);

  if (style.hasPill) {
    final pillWidth = size.width * 0.24;
    final pillHeight = borderPx * 0.28;
    final pillY = size.height - borderPx / 2;
    final pill = ui.RRect.fromRectAndRadius(
      ui.Rect.fromCenter(
        center: ui.Offset(size.width / 2, pillY),
        width: pillWidth,
        height: pillHeight,
      ),
      ui.Radius.circular(pillHeight / 2),
    );
    // Indicador tipo "home": uma barra sólida mais clara sobre a borda,
    // não um recorte.
    final pillPaint = ui.Paint()
      ..color = style.color.withValues(alpha: 0.5)
      ..isAntiAlias = false;
    canvas.drawRRect(pill, pillPaint);
  }
}
