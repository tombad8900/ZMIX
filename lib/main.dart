import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'history_page.dart';
import 'library_page.dart';
import 'models.dart';
import 'settings_page.dart';
import 'storage.dart';

/// Dev-only seed for UI verification builds (flutter run/build with
/// --dart-define DEMO_SEED=true). Never enabled in release APKs.
const bool kDemoSeed = bool.fromEnvironment('DEMO_SEED');

/// Preview-only: auto-open the add-playlist sheet in a mid-import progress
/// state for pixel verification. Never enabled in release APKs.
const bool kDemoProgress = bool.fromEnvironment('DEMO_PROGRESS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // media_kit's native video backend has no web implementation in this build;
  // initializing it on web kills startup (blank preview). Android path only.
  if (!kIsWeb) MediaKit.ensureInitialized();
  final store = LibraryStore();
  await store.load();
  if (kDemoSeed && store.playlists.isEmpty) {
    _seedDemo(store);
  }
  runApp(ZmixApp(store: store));
}

void _seedDemo(LibraryStore store) {
  LibraryVideo demoVideo(String id, String title, int seconds) => LibraryVideo(
        id: id,
        title: title,
        thumbUrl: ThumbnailSet(id).highResUrl,
        durationSeconds: seconds,
      );
  store.playlists.addAll([
    LibraryPlaylist(
      id: 'demo1',
      name: 'كلاسيكيات يوتيوب',
      url: 'https://www.youtube.com/playlist?list=PLdemo1',
      author: 'YouTube',
      thumbUrl: ThumbnailSet('jNQXAC9IVRw').highResUrl,
      videos: [
        demoVideo('jNQXAC9IVRw', 'Me at the zoo', 19),
        demoVideo('dQw4w9WgXcQ',
            'Rick Astley - Never Gonna Give You Up (Official Video)', 213),
      ],
      addedAt: DateTime.now(),
    ),
    LibraryPlaylist(
      id: 'demo2',
      name: 'موسيقى',
      url: 'https://www.youtube.com/playlist?list=PLdemo2',
      author: 'YouTube Music',
      thumbUrl: ThumbnailSet('9bZkp7q19f0').highResUrl,
      videos: [
        demoVideo('9bZkp7q19f0', 'PSY - GANGNAM STYLE(강남스타일) M/V', 253),
      ],
      addedAt: DateTime.now(),
    ),
    if (kDemoProgress)
      LibraryPlaylist(
        id: 'demo3',
        name: 'قائمة تجريبية كبيرة',
        url: 'https://www.youtube.com/playlist?list=PLdemo3',
        author: 'Demo Channel',
        thumbUrl: ThumbnailSet('jNQXAC9IVRw').highResUrl,
        videos: List.generate(
          298,
          (i) => demoVideo(
              'dQw4w9WgXcQ', 'فيلم كلاسيكي رقم ${i + 1}', 5400 + i * 7),
        ),
        addedAt: DateTime.now(),
        importComplete: false,
        totalCountHint: 625,
        importNote: 'short_of_declared',
      ),
  ]);
}

class ZmixApp extends StatelessWidget {
  const ZmixApp({super.key, required this.store});

  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZMIX',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E13),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6CFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF14141B),
        ),
        useMaterial3: true,
        fontFamily: 'Naskh',
      ),
      home: ZmixShell(store: store),
    );
  }
}

class ZmixShell extends StatefulWidget {
  const ZmixShell({super.key, required this.store});

  final LibraryStore store;

  @override
  State<ZmixShell> createState() => _ZmixShellState();
}

class _ZmixShellState extends State<ZmixShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryPage(store: widget.store),
      HistoryPage(store: widget.store),
      SettingsPage(store: widget.store),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: const Color(0xFF14141B),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: 'المكتبة',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'السجل',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}
