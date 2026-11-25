import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ZmixTrialApp());
}

class ZmixTrialApp extends StatelessWidget {
  const ZmixTrialApp({super.key});

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
        ),
        useMaterial3: true,
      ),
      home: const TrialHome(),
    );
  }
}

class TrialHome extends StatefulWidget {
  const TrialHome({super.key});

  @override
  State<TrialHome> createState() => _TrialHomeState();
}

class _TrialHomeState extends State<TrialHome> {
  final TextEditingController _urlController = TextEditingController(
    text: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
  );
  final List<String> _log = [];
  bool _busy = false;

  void _addLog(String line) {
    setState(() => _log.insert(0, line));
  }

  Future<void> _resolveAndPlay() async {
    if (_busy) return;
    setState(() => _busy = true);
    final yt = YoutubeExplode();
    try {
      final input = _urlController.text.trim();
      _addLog('⏳ بنقرأ الفيديو: $input');
      final videoId = VideoId.parseVideoId(input);
      if (videoId == null) {
        _addLog('❌ مش قادر أفهم الرابط ده كفيديو يوتيوب');
        return;
      }
      final video = await yt.videos.get(VideoId(videoId));
      _addLog('✅ العنوان: ${video.title}');
      _addLog('⏳ بنجهّز رابط التشغيل...');
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      if (manifest.muxed.isEmpty) {
        _addLog('❌ مفيش صيغة تشغيل مدمجة (muxed) متاحة');
        return;
      }
      final stream = manifest.muxed.withHighestBitrate();
      _addLog('✅ الرابط جاهز: ${stream.videoQuality.name} / ${stream.size.totalMegaBytes.toStringAsFixed(1)}MB');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TrialPlayerScreen(
            title: video.title,
            streamUrl: stream.url.toString(),
          ),
        ),
      );
      _addLog('👋 رجعنا من المشغّل');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    } finally {
      yt.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZMIX Trial 0.1'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تجربة تشغيل يوتيوب داخل ZMIX\nالصق رابط فيديو ودوس تشغيل. لو حصل خطأ، ابعت سكرين شوت من اللوج اللي تحت.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFA7A7B2), height: 1.6),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=...',
                hintStyle: const TextStyle(color: Color(0xFF6E6E78)),
                filled: true,
                fillColor: const Color(0xFF17171E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _resolveAndPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(_busy ? 'بنجهّز...' : 'تشغيل'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF121218),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      _log[i],
                      style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFFD8D8DE)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrialPlayerScreen extends StatefulWidget {
  const TrialPlayerScreen({super.key, required this.title, required this.streamUrl});

  final String title;
  final String streamUrl;

  @override
  State<TrialPlayerScreen> createState() => _TrialPlayerScreenState();
}

class _TrialPlayerScreenState extends State<TrialPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _player.open(Media(widget.streamUrl), play: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: _controller),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '❌ خطأ التشغيل: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
