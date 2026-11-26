import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'diagnostics.dart';
import 'launch_gate.dart';
import 'models.dart';
import 'player_page.dart';
import 'storage.dart';
import 'youtube_service.dart';

/// Dev-only: with DEMO_STREAM_URL, demo videos play this sample stream
/// instead of resolving YouTube (CORS blocks resolution in web previews).
const String kDemoStreamUrl = String.fromEnvironment('DEMO_STREAM_URL');

/// Resolve and play a library video, recording history first. Shared by the
/// home shelves and the playlist grid so both launch the player identically.
final LaunchGate _launchGate = LaunchGate();

Future<void> playLibraryVideo(
  BuildContext context, {
  required LibraryStore store,
  required LibraryPlaylist playlist,
  required LibraryVideo video,
}) async {
  // Entries with missing metadata still get a normal playback attempt:
  // YouTube supplies no per-entry reason marker for untitled entries, so
  // absence of a title does not establish unavailability. If the stream
  // truly cannot be resolved, the existing error path below says so.
  if (kIsWeb) {
    // The web preview has no media_kit backend; playback is Android-only.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('التشغيل مش متاح في معاينة الويب - بيشتغل على الموبايل')),
    );
    return;
  }
  final ran = await _launchGate.run((release) async {
    await _launch(context, release,
        store: store, playlist: playlist, video: video);
  });
  if (!ran) Diag.I.ui('تجاهل ضغطة أثناء تحميل فيديو آخر');
}

Future<void> _launch(
  BuildContext context,
  void Function() release, {
  required LibraryStore store,
  required LibraryPlaylist playlist,
  required LibraryVideo video,
}) async {
  final attempt = Diag.I.newAttempt();
  Diag.I.ui('تشغيل فيديو',
      detail: Diag.I.videoLabel(
          index: playlist.videos.indexWhere((v) => v.id == video.id),
          videoId: video.id),
      attemptId: attempt);
  final service = YoutubeService();
  try {
    final stream = kDemoStreamUrl.isNotEmpty
        ? (url: kDemoStreamUrl, quality: 'demo')
        : await service.resolvePlayable(video.id, attemptId: attempt);
    await store.recordPlay(
      videoId: video.id,
      title: video.title,
      thumbUrl: video.thumbUrl,
      playlistName: playlist.name,
    );
    if (!context.mounted) return;
    final pushed = Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          title: video.title,
          streamUrl: stream.url,
          qualityLabel: stream.quality,
          videoId: video.id,
          siblings: playlist.videos,
          videoIndex:
              playlist.videos.indexWhere((v) => v.id == video.id),
          store: store,
          playlistName: playlist.name,
          attemptId: attempt,
        ),
      ),
    );
    // Route is on screen: further taps hit the player, not the grid. Release
    // the gate now (not at pop) so a finished launch never blocks the next.
    release();
    await pushed;
  } catch (e) {
    // Launch-stage failures (history write, navigation) used to toast with
    // zero log trace; record them (redacted) under the same attempt.
    Diag.I.outcome('فشل إطلاق التشغيل',
        stage: 'launch', ok: false, detail: '$e', attemptId: attempt);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('مش قادرين نشغّل الفيديو ده دلوقتي. يوتيوب ممكن يكون حاجبه مؤقتًا.'),
        ),
      );
    }
  } finally {
    service.close();
  }
}
