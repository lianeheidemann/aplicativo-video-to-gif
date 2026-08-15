import 'package:flutter/material.dart';

import 'models/size_estimate.dart';

const _seed = Color(0xFF7C53C9);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Cor associada a cada faixa de peso, usada no painel de estimativa.
Color verdictColor(SizeVerdict verdict, ColorScheme scheme) {
  return switch (verdict) {
    SizeVerdict.light => const Color(0xFF2E7D32),
    SizeVerdict.good => const Color(0xFF558B2F),
    SizeVerdict.heavy => const Color(0xFFE65100),
    SizeVerdict.tooHeavy => scheme.error,
  };
}
