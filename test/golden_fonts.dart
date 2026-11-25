import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
    // falls back to Roboto, so mirror that chain in goldens. The ported
    // AppText styles carry their OWN fallback chain ending in 'sans-serif'
    // (an explicit style fallback overrides the theme's), which Android
    // resolves to Roboto - so register Roboto under that alias too, or
    // Latin letters and some punctuation in overlay captions render tofu
    // here while rendering fine on device.
    final robotoPath =
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';
    final roboto = FontLoader('Roboto')..addFont(bytes(robotoPath));
    await roboto.load();
    final sansSerif = FontLoader('sans-serif')..addFont(bytes(robotoPath));
    await sansSerif.load();
    // In the test engine the generic 'sans-serif' name resolves to the Ahem
    // placeholder before custom registrations, so the FIRST family in
    // AppText's chain that we control must carry Latin: register Roboto
    // under 'Hiragino Sans' (which on a real device carries the Latin the
    // chain is for anyway).
    final hiragino = FontLoader('Hiragino Sans')..addFont(bytes(robotoPath));
    await hiragino.load();
  }
}

/// Mirrors the production theme in lib/main.dart.
Widget goldenHost(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    // Mirror production Directionality: Arabic locale + delegates give RTL.
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
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
