import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Loads the same fonts the real app renders with, so golden pixels carry
/// real glyphs: the bundled Naskh (Noto Naskh Arabic) for text and the SDK's
/// MaterialIcons font for icons. Without these, flutter_test renders the
/// Ahem placeholder font and every glyph is a hollow box.
Future<void> loadGoldenFonts() async {
  Future<ByteData> bytes(String path) => File(path)
      .readAsBytes()
      .then((b) => ByteData.view(b.buffer, b.offsetInBytes, b.lengthInBytes));

  final naskh = FontLoader('Naskh')
    ..addFont(bytes('assets/fonts/NotoNaskhArabic-Regular.ttf'));
  await naskh.load();

  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(
          bytes('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    // Naskh carries Arabic + digits but no Latin letters; on device the OS
    // falls back to Roboto, so mirror that chain in goldens.
    final roboto = FontLoader('Roboto')
      ..addFont(
          bytes('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'));
    await roboto.load();
  }
}

/// Mirrors the production theme in lib/main.dart.
Widget goldenHost(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0B0F),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF4D57),
        brightness: Brightness.dark,
        surface: const Color(0xFF16161C),
      ),
      useMaterial3: true,
      fontFamily: 'Naskh',
      fontFamilyFallback: const ['Roboto'],
    ),
    home: child,
  );
}
