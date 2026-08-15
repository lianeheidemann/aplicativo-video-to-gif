import 'package:flutter/material.dart';

import 'licenses.dart';
import 'theme.dart';
import 'ui/home_page.dart';

void main() {
  // Exigência da LGPL do FFmpeg: o aviso precisa estar acessível no app.
  registerThirdPartyLicenses();
  runApp(const VideoToGifApp());
}

class VideoToGifApp extends StatelessWidget {
  const VideoToGifApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vídeo em GIF',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const HomePage(),
    );
  }
}
