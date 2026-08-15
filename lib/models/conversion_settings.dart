import 'video_info.dart';

/// Como o GIF distribui o erro de cor ao reduzir a imagem para 256 cores.
///
/// Pontilhado (dither) melhora gradientes, mas cria ruído de alta frequência
/// que atrapalha a compressão LZW — ou seja, quanto mais dither, mais pesado
/// o arquivo. Essa é a troca central entre qualidade e peso no formato GIF.
enum DitherMode {
  /// Sem pontilhado. Menor arquivo, mas gradientes ficam com faixas visíveis.
  none('none', 'Sem pontilhado', 'Arquivo menor, pode listrar céu e sombras'),

  /// Padrão ordenado grosseiro. Bom meio-termo puxando para leve.
  bayer3('bayer:bayer_scale=3', 'Leve', 'Textura sutil, arquivo enxuto'),

  /// Padrão ordenado fino. Recomendado para a maioria dos vídeos.
  bayer5('bayer:bayer_scale=5', 'Equilibrado', 'Melhor relação qualidade/peso'),

  /// Difusão de erro. Melhor gradiente, arquivo bem maior.
  sierra('sierra2_4a', 'Alta', 'Gradientes suaves, arquivo bem maior'),

  /// Difusão clássica. A mais pesada.
  floydSteinberg(
    'floyd_steinberg',
    'Máxima',
    'Qualidade máxima de cor, arquivo mais pesado',
  );

  const DitherMode(this.ffmpegValue, this.label, this.description);

  final String ffmpegValue;
  final String label;
  final String description;
}

/// Estratégia de construção da paleta de cores.
enum PaletteMode {
  /// Uma paleta única para o GIF inteiro, calculada com todos os quadros.
  /// Mais leve e estável; pode errar a cor se a cena mudar muito.
  global('full', 'Paleta única', 'Mais leve, ideal para uma cena só'),

  /// Prioriza as áreas que se movem ao escolher as cores.
  /// Bom quando o fundo é estático e só um objeto se mexe.
  movement('diff', 'Focada no movimento', 'Boa para fundo parado'),

  /// Uma paleta nova por quadro. Melhor cor, arquivo bem maior.
  perFrame('single', 'Paleta por quadro', 'Melhor cor, arquivo maior');

  const PaletteMode(this.statsMode, this.label, this.description);

  final String statsMode;
  final String label;
  final String description;
}

/// Recorte em pixels do vídeo já rotacionado (coordenadas de exibição).
class CropRect {
  const CropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  /// Maior recorte centralizado com a proporção [ratio] que cabe no vídeo.
  factory CropRect.centered(VideoInfo video, double ratio) {
    var w = video.width;
    var h = (w / ratio).round();
    if (h > video.height) {
      h = video.height;
      w = (h * ratio).round();
    }
    w = w - (w % 2);
    h = h - (h % 2);
    return CropRect(
      x: ((video.width - w) / 2).round(),
      y: ((video.height - h) / 2).round(),
      width: w,
      height: h,
    );
  }

  CropRect copyWith({int? x, int? y, int? width, int? height}) => CropRect(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
  );
}

/// Proporções oferecidas na tela de recorte.
class AspectPreset {
  const AspectPreset(this.label, this.ratio, {this.hint = ''});

  final String label;
  final double? ratio; // null = manter a proporção original
  final String hint;

  static const presets = <AspectPreset>[
    AspectPreset('Original', null),
    AspectPreset('1:1', 1.0, hint: 'Quadrado'),
    AspectPreset('4:5', 4 / 5, hint: 'Retrato'),
    AspectPreset('9:16', 9 / 16, hint: 'Stories'),
    AspectPreset('16:9', 16 / 9, hint: 'Paisagem'),
    // Mantidos para compatibilidade com configurações/recortes existentes.
    AspectPreset('4:3', 4 / 3, hint: 'Clássico'),
    AspectPreset('3:2', 3 / 2, hint: 'Foto'),
  ];
}

/// Todos os parâmetros que o usuário controla antes de converter.
class ConversionSettings {
  const ConversionSettings({
    required this.startSeconds,
    required this.endSeconds,
    this.speed = 1.0,
    this.fps = 12,
    this.targetWidth = 480,
    this.crop,
    this.colors = 256,
    this.dither = DitherMode.bayer5,
    this.palette = PaletteMode.global,
    this.loop = true,
  });

  final double startSeconds;
  final double endSeconds;
  final double speed;
  final int fps;
  final int targetWidth;
  final CropRect? crop;
  final int colors;
  final DitherMode dither;
  final PaletteMode palette;
  final bool loop;

  /// Presets exibidos no editor redesenhado.
  static const fpsOptions = <int>[5, 8, 10, 12, 15, 20, 24];
  static const widthOptions = <int>[160, 240, 320, 400, 480, 640, 800];
  static const colorOptions = <int>[32, 64, 96, 128, 192, 256];
  static const primaryColorOptions = <int>[64, 128, 256];
  static const speedOptions = <double>[
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  double get sourceDurationSeconds {
    final d = endSeconds - startSeconds;
    return d < 0 ? 0 : d;
  }

  double get outputDurationSeconds => sourceDurationSeconds / speed;

  int get frameCount {
    final n = (outputDurationSeconds * fps).round();
    return n < 1 ? 1 : n;
  }

  (int, int) outputDimensions(VideoInfo video) {
    final srcWidth = crop?.width ?? video.width;
    final srcHeight = crop?.height ?? video.height;
    if (srcWidth <= 0 || srcHeight <= 0) return (2, 2);

    var w = targetWidth > srcWidth ? srcWidth : targetWidth;
    if (w < 2) w = 2;
    var h = (w * srcHeight / srcWidth).round();

    w -= w % 2;
    h -= h % 2;
    return (w < 2 ? 2 : w, h < 2 ? 2 : h);
  }

  double scaleRatio(VideoInfo video) {
    final srcWidth = crop?.width ?? video.width;
    if (srcWidth <= 0) return 1;
    final (w, _) = outputDimensions(video);
    return (w / srcWidth).clamp(0.05, 1.0).toDouble();
  }

  ConversionSettings copyWith({
    double? startSeconds,
    double? endSeconds,
    double? speed,
    int? fps,
    int? targetWidth,
    CropRect? crop,
    bool clearCrop = false,
    int? colors,
    DitherMode? dither,
    PaletteMode? palette,
    bool? loop,
  }) {
    return ConversionSettings(
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      speed: speed ?? this.speed,
      fps: fps ?? this.fps,
      targetWidth: targetWidth ?? this.targetWidth,
      crop: clearCrop ? null : (crop ?? this.crop),
      colors: colors ?? this.colors,
      dither: dither ?? this.dither,
      palette: palette ?? this.palette,
      loop: loop ?? this.loop,
    );
  }

  factory ConversionSettings.recommendedFor(VideoInfo video) {
    const maxSeconds = 10.0;
    final end = video.durationSeconds < maxSeconds
        ? video.durationSeconds
        : maxSeconds;

    final width = ConversionSettings.widthOptions
        .where((w) => w <= video.width)
        .fold<int>(160, (best, w) => w <= 480 && w > best ? w : best);

    return ConversionSettings(
      startSeconds: 0,
      endSeconds: end,
      targetWidth: width,
    );
  }
}
