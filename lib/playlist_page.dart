import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import 'grouper.dart';
import 'models.dart';
import 'play_launcher.dart';
import 'storage.dart';
import 'ui/poster_card.dart';

/// One playlist: cinematic artwork header tinted by the artwork itself,
/// then the videos as a Zangetsu-style poster grid (3 columns of wide
/// cards, titles below), with series/season section headers when the
/// grouper finds clear episode markers.
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
    try {
      await playLibraryVideo(
        context,
        store: widget.store,
        playlist: widget.playlist,
        video: video,
      );
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final grouped = groupPlaylist(playlist.videos);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _appBar(playlist),
          if (grouped.series.isEmpty)
            _videoGrid(playlist.videos)
          else ...[
            for (final s in grouped.series) ...[
              _header('${s.title} · ${s.totalEpisodes} حلقة'),
              for (final season in s.sortedSeasons) ...[
                if (s.sortedSeasons.where((x) => x != null).length > 1 &&
                    season != null)
                  _subheader('موسم $season'),
                _videoGrid(s.seasons[season]!),
              ],
            ],
            if (grouped.ungrouped.isNotEmpty) ...[
              _header('فيديوهات · ${grouped.ungrouped.length}'),
              _videoGrid(grouped.ungrouped),
            ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _appBar(LibraryPlaylist playlist) {
    return SliverAppBar(
      expandedHeight: 230,
      pinned: true,
      backgroundColor: const Color(0xFF0B0B0F),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding:
            const EdgeInsetsDirectional.only(start: 16, bottom: 12, end: 16),
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
                    const Color(0xFF0B0B0F),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3-column poster grid, Zangetsu's wide-card grid math
  /// (see ui/poster_card.dart).
  Widget _videoGrid(List<LibraryVideo> videos) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = posterGridColumns(context);
        final cellWidth = posterGridCellWidth(context);
        final aspect = posterCellAspect(
          cellWidth,
          textScaler: MediaQuery.textScalerOf(context),
          wide: true,
        );
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: aspect,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final video = videos[i];
                final resolving = _resolvingId == video.id;
                // YouTube-sourced visibility: untitled entries are shown
                // dimmed with a fallback title; titled-but-hidden entries
                // carry a small note tag. Positions are never reshuffled.
                final untitled = video.isSourceUntitled;
                final hiddenTitled = video.visibility == 'hiddenTitled';
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: untitled ? 0.45 : (hiddenTitled ? 0.8 : 1),
                        child: PosterCard(
                          title:
                              untitled ? 'فيديو غير متاح' : video.title,
                          imageUrl:
                              video.thumbUrl.isEmpty ? null : video.thumbUrl,
                          tags: [
                            if (untitled)
                              'غير متاح'
                            else if (hiddenTitled)
                              'مخفي افتراضيًا',
                            if (video.durationLabel.isNotEmpty)
                              video.durationLabel,
                          ],
                          cellWidth: cellWidth,
                          onTap: () => _play(video),
                        ),
                      ),
                    ),
                    if (resolving)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black54,
                          child: Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
              childCount: videos.length,
            ),
          ),
        );
      },
    );
  }

  Widget _header(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF8A91),
            ),
          ),
        ),
      );

  Widget _subheader(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
          child: Text(
            text,
            style:
                const TextStyle(fontSize: 12.5, color: Color(0xFFA7A7B2)),
          ),
        ),
      );
}
