// Ported from Zangetsu (https://github.com/Spyou/Zangetsu), GPL-3.0,
// lib/core/ui/poster_card.dart at upstream commit
// 772fac56d265b238b90118bd68abe2e7353b1f6e.
//
// This file is a copy of the upstream code with only integration edits:
//  - dropped dependencies that do not exist in ZMIX: MediaItem/logoItem
//    (catalogue identity + title-logo artwork), PlaybackPrefs/PosterCardScope
//    (poster size/layout preferences - ZMIX has no such settings, so cards
//    take `wide` explicitly and title placement is fixed below the art),
//    AppImageCache.manager and the Aniyomi/Mihon image providers (YouTube
//    thumbnails need no custom cache manager or CF-carrying fetchers),
//    TV grid variants, and l10n/AppText (inline style with the same values:
//    caption = 13px, height 1.3).
//  - AppColors.surface2 -> Color(0xFF20212A), textPrimary -> white,
//    accent -> #FF4D57 (same values as upstream app_colors.dart).
// Everything else - _posterTextScrim, _responsiveColumns, posterGridColumns
// math, posterCellHeight/Aspect, press-scale, ClipRSuperellipse, the badge
// stack and _PosterTag - follows the upstream source.
//
// ZMIX is GPL-3.0; upstream copyright and license notices are preserved.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// ignore: constant_identifier_names
const _posterTextScrim = LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [Color(0x8C0B0B0F), Color(0x2E0B0B0F), Color(0x000B0B0F)],
  stops: [0, 0.26, 0.68],
);

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.onTap,
    this.onLongPress,
    this.tags = const [],
    this.cellWidth = 180,
    this.showTitle = true,
    this.wide = true,
  });
  final String title;
  final String? imageUrl;

  /// Test seam: when set (golden/widget tests only), artwork is decoded from
  /// this provider instead of the network so renders carry real images.
  static ImageProvider Function(String url)? debugImageProvider;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Small overlay badges drawn at the bottom-left of the art (upstream uses
  /// SUB/DUB tags; ZMIX passes the video duration label).
  final List<String> tags;
  final double cellWidth;

  /// When false, omit the external title.
  final bool showTitle;

  /// Landscape 16:9 art (ZMIX videos) vs portrait poster art.
  final bool wide;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

// Upstream _responsiveColumns, verbatim.
int _responsiveColumns(
  int desired, {
  required double availableWidth,
  required double minimumCellWidth,
  required double spacing,
  required int maxColumns,
}) {
  final widthLimit = ((availableWidth + spacing) / (minimumCellWidth + spacing))
      .floor()
      .clamp(1, maxColumns);
  return desired.clamp(1, widthLimit).toInt();
}

/// Upstream posterGridColumns. ZMIX's catalogue is all 16:9 video art, so
/// the wide parameters are the default; desired base is 3 to match the
/// reference three-column grid on phones.
int posterGridColumns(BuildContext context, {bool wide = true, int desired = 3}) {
  final availableWidth = MediaQuery.sizeOf(context).width - 32;
  return _responsiveColumns(
    desired,
    availableWidth: availableWidth,
    minimumCellWidth: wide ? 110 : 72,
    spacing: 12,
    maxColumns: 6,
  );
}

double posterGridCellWidth(BuildContext context, {bool wide = true}) {
  final columns = posterGridColumns(context, wide: wide);
  return (MediaQuery.sizeOf(context).width - 32 - 12 * (columns - 1)) / columns;
}

/// Upstream posterRowWidth: wide shelf cards are 184 logical px wide.
double posterRowWidth(BuildContext context, {bool wide = true}) =>
    (wide ? 184 : 116) * 1.0;

double posterRowHeight(BuildContext context, {bool wide = true}) {
  return posterCellHeight(
    posterRowWidth(context, wide: wide),
    textScaler: MediaQuery.textScalerOf(context),
    wide: wide,
  );
}

class _PosterCardState extends State<PosterCard> {
  bool _pressed = false;

  void _handleTapDown(TapDownDetails _) => setState(() => _pressed = true);
  void _handleTapUp(TapUpDetails _) => setState(() => _pressed = false);
  void _handleTapCancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    final titleBoxHeight = _posterTitleHeight(MediaQuery.textScalerOf(context));
    final artUrl = widget.imageUrl;
    const artFit = BoxFit.cover;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = (widget.cellWidth * dpr).round();
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final hasBottomBadges = widget.tags.isNotEmpty;
    final bottomBadges = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final tag in widget.tags)
          _PosterTag(tag, maxWidth: widget.cellWidth - 22),
      ],
    );
    Widget networkArtwork(String url) {
      final debugProvider = PosterCard.debugImageProvider;
      if (debugProvider != null) {
        return Image(
          image: ResizeImage(debugProvider(url), width: memW),
          fit: artFit,
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: Color(0xFF20212A)),
        );
      }
      return CachedNetworkImage(
        imageUrl: url,
        memCacheWidth: memW,
        fit: artFit,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (_, _) => const ColoredBox(color: Color(0xFF20212A)),
        errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF20212A)),
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: interactive ? _handleTapDown : null,
        onTapUp: interactive ? _handleTapUp : null,
        onTapCancel: interactive ? _handleTapCancel : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (artUrl == null)
                        const ColoredBox(color: Color(0xFF20212A))
                      else
                        networkArtwork(artUrl),
                      if (hasBottomBadges)
                        const DecoratedBox(
                          decoration: BoxDecoration(gradient: _posterTextScrim),
                        ),
                      if (hasBottomBadges)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          right: 6,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (hasBottomBadges) bottomBadges,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.showTitle) ...[
                const SizedBox(height: _kTitleGap),
                // Upstream: a FIXED two-line box, even for a one-line title,
                // so posters in the same row keep equal heights.
                SizedBox(
                  height: titleBoxHeight,
                  child: PosterCardTitle(
                    title: widget.title,
                    width: widget.cellWidth,
                    maxHeight: titleBoxHeight,
                    inside: false,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Upstream PosterCardTitle, text path only (ZMIX has no title-logo
/// artwork service).
class PosterCardTitle extends StatelessWidget {
  const PosterCardTitle({
    super.key,
    required this.title,
    required this.width,
    required this.maxHeight,
    this.inside = true,
    this.maxLines = 2,
    this.textStyle,
  });

  final String title;
  final double width;
  final double maxHeight;
  final bool inside;
  final int maxLines;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) => _text();

  Widget _text() => Text(
    title,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style:
        textStyle ??
        const TextStyle(
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w500,
        ).copyWith(
          color: const Color(0xFFFFFFFF),
          fontWeight: inside ? FontWeight.w700 : FontWeight.w500,
        ),
  );
}

/// Upstream _posterTitleHeight: two caption lines (13px, height 1.3),
/// rounded up per line.
double _posterTitleHeight(TextScaler textScaler) =>
    (textScaler.scale(13) * 1.3).ceilToDouble() * 2;

/// Gap between the poster art and its title (upstream _kTitleGap).
const double _kTitleGap = 8;

/// Upstream posterCellHeight.
double posterCellHeight(
  double cellWidth, {
  TextScaler textScaler = TextScaler.noScaling,
  bool wide = false,
  bool titleInside = false,
  double? artAspectRatio,
}) {
  final artHeight = artAspectRatio != null
      ? cellWidth / artAspectRatio
      : wide
      ? cellWidth * 9 / 16
      : cellWidth * 1.5;
  final titleHeight = titleInside
      ? 0.0
      : _kTitleGap + _posterTitleHeight(textScaler);
  final height = artHeight + titleHeight;
  return titleHeight == 0 ? height : height.ceilToDouble();
}

double posterCellAspect(
  double cellWidth, {
  TextScaler textScaler = TextScaler.noScaling,
  bool wide = false,
  bool titleInside = false,
}) =>
    cellWidth /
    posterCellHeight(
      cellWidth,
      textScaler: textScaler,
      wide: wide,
      titleInside: titleInside,
    );

/// Upstream _PosterTag, verbatim apart from the inline text style.
class _PosterTag extends StatelessWidget {
  const _PosterTag(this.text, {this.maxWidth});
  final String text;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
