import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'models.dart';
import 'player_page.dart';
import 'storage.dart';
import 'youtube_service.dart';

/// Dev-only: with DEMO_STREAM_URL, demo videos play this sample stream
/// instead of resolving YouTube (CORS blocks resolution in web previews).
const String kDemoStreamUrl = String.fromEnvironment('DEMO_STREAM_URL');

/// Resolve and play a library video, recording history first. Shared by the
/// home shelves and the playlist grid so both launch the player identically.
Future<void> playLibraryVideo(
  BuildContext context, {
  required LibraryStore store,
  required LibraryPlaylist playlist,
  required LibraryVideo video,
}) async {
  if (video.isSourceUntitled) {
    // YouTube serves this entry with no title even in its own
    // "show unavailable" view: deleted or private in practice, with no
    // playable stream to resolve.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'الفيديو ده متعلّم عند يوتيوب كغير متاح (محذوف أو خاص) ومفيش له صيغة تشغيل.')),
    );
    return;
  }
  if (kIsWeb) {
    // The web preview has no media_kit backend; playback is Android-only.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('التشغيل مش متاح في معاينة الويب - بيشتغل على الموبايل')),
    );
    return;
  }
  final service = YoutubeService();
  try {
    final stream = kDemoStreamUrl.isNotEmpty
        ? (url: kDemoStreamUrl, quality: 'demo')
        : await service.resolvePlayable(video.id);
    await store.recordPlay(
      videoId: video.id,
      title: video.title,
      thumbUrl: video.thumbUrl,
      playlistName: playlist.name,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
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
        ),
      ),
    );
  } catch (_) {
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
