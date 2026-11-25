import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'models.dart';
import 'player_page.dart';
import 'storage.dart';
import 'youtube_service.dart';

/// One playlist: cinematic artwork header tinted by the artwork itself,
/// then the video list.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.playlist, required this.store});

  final LibraryPlaylist playlist;
  final LibraryStore store;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  Color _tint = const Color(0xFF3B2F8F);
  String? _resolvingId;

  @override
  void initState() {
    super.initState();
    _extractTint();
  }

  Future<void> _extractTint() async {
    if (widget.playlist.thumbUrl.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(widget.playlist.thumbUrl),
        maximumColorCount: 8,
      );
      final color = palette.darkVibrantColor?.color ??
          palette.darkMutedColor?.color ??
          palette.dominantColor?.color;
      if (color != null && mounted) {
        setState(() => _tint = color);
      }
    } catch (_) {
      // Keep the default tint.
    }
  }

  Future<void> _play(LibraryVideo video) async {
    if (_resolvingId != null) return;
    setState(() => _resolvingId = video.id);
    final service = YoutubeService();
    try {
      final stream = await service.resolvePlayable(video.id);
      await widget.store.recordPlay(
        videoId: video.id,
        title: video.title,
        thumbUrl: video.thumbUrl,
        playlistName: widget.playlist.name,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerPage(title: video.title, streamUrl: stream.url),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('مش قادرين نشغّل الفيديو ده دلوقتي. يوتيوب ممكن يكون حاجبه مؤقتًا.'),
          ),
        );
      }
    } finally {
      service.close();
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 230,
            pinned: true,
            backgroundColor: const Color(0xFF0E0E13),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 12, end: 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                    ),
                  ),
                  Text(
                    [
                      '${playlist.videos.length} فيديو',
                      if (playlist.author.isNotEmpty) playlist.author,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFD9D9E2),
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                ],
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'pl_${playlist.id}',
                    child: playlist.thumbUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: playlist.thumbUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: _tint),
                            placeholder: (_, __) => Container(color: _tint),
                          )
                        : Container(color: _tint),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          _tint.withValues(alpha: 0.55),
                          const Color(0xFF0E0E13),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.separated(
            itemCount: playlist.videos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final video = playlist.videos[i];
              final resolving = _resolvingId == video.id;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                onTap: () => _play(video),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 112,
                    height: 63,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        video.thumbUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: video.thumbUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    Container(color: const Color(0xFF1A1726)),
                                placeholder: (_, __) =>
                                    Container(color: const Color(0xFF1A1726)),
                              )
                            : Container(color: const Color(0xFF1A1726)),
                        if (resolving)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        if (video.durationLabel.isNotEmpty && !resolving)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                video.durationLabel,
                                style: const TextStyle(fontSize: 10.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                title: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
