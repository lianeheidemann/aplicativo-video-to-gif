import 'dart:ui' show Color;

import 'image_frame.dart';

/// Estilo de moldura desenhado ao redor do GIF. Cada estilo é só um atalho
/// para um par de valores — espessura da borda e arredondamento dos cantos —
/// que o usuário ainda pode ajustar livremente nos dois sliders da seção
/// "Moldura". O tamanho e a proporção do GIF são definidos na aba "Ajustar",
/// nunca aqui.
enum FrameStyle {
  none('Sem moldura', defaultThickness: 0, defaultCornerRatio: 0),
  thin('Moldura fina', defaultThickness: 4, defaultCornerRatio: 0.06),
  medium('Moldura média', defaultThickness: 10, defaultCornerRatio: 0.12),
  thick('Moldura grossa', defaultThickness: 18, defaultCornerRatio: 0.20);

  const FrameStyle(
    this.label, {
    required this.defaultThickness,
    required this.defaultCornerRatio,
  });

  final String label;

  /// Espessura sugerida (px numa largura de referência de 480px).
  final double defaultThickness;

  /// Arredondamento sugerido, como razão do menor lado do canvas — ver
  /// [FrameSettings.cornerRatio].
  final double defaultCornerRatio;
}

/// Como o vídeo se encaixa dentro da área de conteúdo da moldura quando a
/// proporção da área é diferente da proporção do recorte feito em "Ajustar".
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
    this.cornerRatio = 0,
    this.contentFit = ContentFitMode.auto,
    this.transparentBackground = true,
    this.imageFrame,
  });

  final FrameStyle style;
  final Color color;

  /// Espessura em pixels numa largura de referência ([referenceWidth]).
  /// No mínimo (0) a moldura vira só o arredondamento dos cantos.
  final double thicknessAtReference;

  /// Arredondamento dos cantos como razão do menor lado do canvas — por ser
  /// proporcional (não pixels fixos), o arredondamento continua parecendo o
  /// mesmo em qualquer resolução de saída. `0` é canto reto;
  /// [maxCornerRatio] é a forma completamente arredondada.
  final double cornerRatio;

  final ContentFitMode contentFit;

  /// Ligado (padrão), a área fora da moldura sai transparente no GIF.
  /// Desligado, ela sai preta — ver `paintFrame` e `FfmpegService`.
  final bool transparentBackground;

  /// Quando não-nula, substitui totalmente a moldura procedural (style/
  /// color/thickness/cornerRatio ficam ignorados) por uma arte de imagem — a
  /// arte já embute cor, espessura e cantos. [transparentBackground]
  /// continua valendo: é ele que decide se a área fora da arte sai
  /// transparente ou preta.
  final ImageFrameAsset? imageFrame;

  bool get hasImageFrame => imageFrame != null;

  /// Somente molduras de imagem têm canvas próprio. Molduras procedurais
  /// respeitam sempre o formato de janela escolhido pelo usuário.
  bool get hasFixedAspect => imageFrame != null;

  double? get fixedAspectRatio => imageFrame?.nativeAspectRatio;

  /// Largura de referência (px) usada para normalizar [thicknessAtReference].
  static const referenceWidth = 480.0;

  /// Arredondamento máximo: metade do menor lado, ou seja, a forma
  /// completamente arredondada (um círculo, num canvas quadrado).
  static const maxCornerRatio = 0.5;

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
    return shorterSide * cornerRatio.clamp(0.0, maxCornerRatio);
  }

  /// Cria uma cópia substituindo apenas os campos informados.
  /// [clearImageFrame] remove a moldura de imagem mesmo que [imageFrame]
  /// não seja passado.
  FrameSettings copyWith({
    FrameStyle? style,
    Color? color,
    double? thicknessAtReference,
    double? cornerRatio,
    ContentFitMode? contentFit,
    bool? transparentBackground,
    ImageFrameAsset? imageFrame,
    bool clearImageFrame = false,
  }) {
    return FrameSettings(
      style: style ?? this.style,
      color: color ?? this.color,
      thicknessAtReference: thicknessAtReference ?? this.thicknessAtReference,
      cornerRatio: cornerRatio ?? this.cornerRatio,
      contentFit: contentFit ?? this.contentFit,
      transparentBackground:
          transparentBackground ?? this.transparentBackground,
      imageFrame: clearImageFrame ? null : (imageFrame ?? this.imageFrame),
    );
  }
}
