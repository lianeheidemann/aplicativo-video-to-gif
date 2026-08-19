import 'dart:ui' show Color;

import 'image_frame.dart';

/// Estilo de moldura desenhado ao redor do GIF. Cada estilo sugere uma
/// proporção de tela (ou `null` para manter a proporção do recorte feito em
/// "Ajustar") e valores padrão de canto/espessura, que o usuário ainda pode
/// sobrescrever via os controles "Cantos" e "Espessura".
enum FrameStyle {
  none(
    'Sem moldura',
    targetAspectRatio: null,
    defaultCorner: CornerStyle.sharp,
    defaultThickness: 0,
  ),
  slim(
    'Celular Slim',
    targetAspectRatio: 9 / 19.5,
    defaultCorner: CornerStyle.full,
    defaultThickness: 10,
  ),
  classic(
    'Celular Clássico',
    targetAspectRatio: 3 / 4,
    defaultCorner: CornerStyle.medium,
    defaultThickness: 14,
  ),
  thin(
    'Bordas finas',
    targetAspectRatio: null,
    defaultCorner: CornerStyle.slight,
    defaultThickness: 4,
  ),
  story9x16(
    'Story 9:16',
    targetAspectRatio: 9 / 16,
    defaultCorner: CornerStyle.sharp,
    defaultThickness: 0,
  );

  const FrameStyle(
    this.label, {
    required this.targetAspectRatio,
    required this.defaultCorner,
    required this.defaultThickness,
  });

  final String label;

  /// `null` mantém a proporção do recorte já feito na aba "Ajustar"; um
  /// valor fixo (largura/altura) força a moldura nessa proporção, exigindo
  /// uma escolha de [ContentFitMode] quando o conteúdo não bate.
  final double? targetAspectRatio;
  final CornerStyle defaultCorner;

  /// Espessura sugerida (px numa largura de referência de 480px).
  final double defaultThickness;
}

/// Presets de arredondamento de canto, como razão do menor lado do canvas —
/// por ser proporcional (não pixels fixos), o arredondamento continua
/// parecendo o mesmo em qualquer resolução de saída.
enum CornerStyle {
  sharp('Reto', 0.0),
  slight('Leve', 0.04),
  medium('Médio', 0.09),
  large('Grande', 0.16),
  full('Arredondado', 0.5);

  const CornerStyle(this.label, this.radiusRatio);

  final String label;
  final double radiusRatio;
}

/// Como o vídeo se encaixa dentro da área de conteúdo da moldura quando a
/// proporção da moldura ([FrameStyle.targetAspectRatio]) é diferente da
/// proporção do recorte feito em "Ajustar".
enum ContentFitMode {
  auto('Ajuste automático', 'Melhor enquadramento para o vídeo'),
  fill('Preencher', 'Preenche toda a moldura (pode cortar)'),
  fit('Encaixar', 'Mostra o vídeo inteiro com barras'),
  expand('Expandir sem cortar', 'Preenche com fundo estendido');

  const ContentFitMode(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

/// Resolve [ContentFitMode.auto] para [ContentFitMode.fill] ou
/// [ContentFitMode.fit] conforme a proporção do conteúdo estiver perto o
/// suficiente da proporção da área — compartilhado entre a exportação
/// (`ffmpeg_service.dart`) e a prévia ao vivo de moldura de imagem
/// (`editor_page.dart`), para as duas nunca divergirem.
ContentFitMode resolveContentFit(
  ContentFitMode mode,
  double contentAspect,
  double areaAspect,
) {
  if (mode != ContentFitMode.auto) return mode;
  final ratio = contentAspect / areaAspect;
  return (ratio >= 0.8 && ratio <= 1.25)
      ? ContentFitMode.fill
      : ContentFitMode.fit;
}

/// Configurações da moldura: estilo, cor, espessura, arredondamento dos
/// cantos, ajuste do conteúdo e transparência do fundo fora da moldura.
///
/// Espessura e raio de canto são guardados/calculados como proporção do
/// canvas de saída (ver [thicknessFor]/[cornerRadiusFor]), nunca como
/// pixels fixos — assim a moldura fica nítida e proporcional em qualquer
/// resolução escolhida em "Resolução", sem esticar nem pixelizar.
class FrameSettings {
  const FrameSettings({
    this.style = FrameStyle.none,
    this.color = const Color(0xFFC9A8FF),
    this.thicknessAtReference = 0,
    this.corner = CornerStyle.sharp,
    this.contentFit = ContentFitMode.auto,
    this.transparentBackground = false,
    this.imageFrame,
  });

  final FrameStyle style;
  final Color color;

  /// Espessura em pixels numa largura de referência ([referenceWidth]).
  final double thicknessAtReference;
  final CornerStyle corner;
  final ContentFitMode contentFit;
  final bool transparentBackground;

  /// Quando não-nula, substitui totalmente a moldura procedural (style/
  /// color/thickness/corner/transparentBackground ficam ignorados) por uma
  /// arte de imagem — a arte já embute cor, espessura, cantos e
  /// transparência das quinas.
  final ImageFrameAsset? imageFrame;

  bool get hasImageFrame => imageFrame != null;

  /// Se há uma proporção de canvas fixa a respeitar — de um [FrameStyle]
  /// procedural com [FrameStyle.targetAspectRatio] ou de uma moldura de
  /// imagem (que sempre tem proporção fixa, a da própria arte).
  bool get hasFixedAspect =>
      imageFrame != null || style.targetAspectRatio != null;

  double? get fixedAspectRatio =>
      imageFrame?.nativeAspectRatio ?? style.targetAspectRatio;

  /// Largura de referência (px) usada para normalizar [thicknessAtReference].
  static const referenceWidth = 480.0;

  /// Nenhuma moldura: mesmo comportamento do app antes desta funcionalidade.
  factory FrameSettings.none() => const FrameSettings();

  /// Espessura em pixels para um canvas de largura [canvasWidth], mantendo a
  /// proporção visual da moldura em qualquer resolução de saída.
  double thicknessFor(double canvasWidth) {
    if (canvasWidth <= 0) return thicknessAtReference;
    return thicknessAtReference * (canvasWidth / referenceWidth);
  }

  /// Raio de canto em pixels para um canvas cujo menor lado mede
  /// [shorterSide].
  double cornerRadiusFor(double shorterSide) {
    if (shorterSide <= 0) return 0;
    return shorterSide * corner.radiusRatio;
  }

  /// Cria uma cópia substituindo apenas os campos informados.
  /// [clearImageFrame] remove a moldura de imagem mesmo que [imageFrame]
  /// não seja passado.
  FrameSettings copyWith({
    FrameStyle? style,
    Color? color,
    double? thicknessAtReference,
    CornerStyle? corner,
    ContentFitMode? contentFit,
    bool? transparentBackground,
    ImageFrameAsset? imageFrame,
    bool clearImageFrame = false,
  }) {
    return FrameSettings(
      style: style ?? this.style,
      color: color ?? this.color,
      thicknessAtReference: thicknessAtReference ?? this.thicknessAtReference,
      corner: corner ?? this.corner,
      contentFit: contentFit ?? this.contentFit,
      transparentBackground:
          transparentBackground ?? this.transparentBackground,
      imageFrame: clearImageFrame ? null : (imageFrame ?? this.imageFrame),
    );
  }
}
