// Ported from Zangetsu (https://github.com/Spyou/Zangetsu), GPL-3.0,
// features/player/player_controls_overlay.dart at upstream commit
// 772fac56d265b238b90118bd68abe2e7353b1f6e.
// Literal copy with integration edits only; each edit is marked ZMIX-EDIT.
// Edits: PlayerCubit/PlayerState replaced by a plain adapter surface (media_kit
// Player + explicit fields/callbacks); l10n lookups replaced by inline Arabic
// strings; features ZMIX does not have (cast, decoder, enhance, colour,
// snapshot, sleep timer, PiP, ambient, chat, info panel, episodes panel,
// sources, subtitle/audio tracks, MegaSkip, settings shortcut) take nullable
// callbacks and drop out through upstream's own null-skip mechanism.
// ZMIX remains GPL-3.0.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_colors.dart';
import 'app_text.dart';
import 'frosted_surface.dart';
import 'player_controls_config.dart';

part 'player_controls_widgets.dart';
part 'player_seek_bar.dart';

/// ZMIX-EDIT: the playback-engine surface the overlay needs. Upstream this
/// was PlayerCubit around media_kit; ZMIX wires media_kit's Player through
/// [MediaKitPlayerSurface], and widget tests substitute a fake (a real
/// media_kit Player needs native libmpv and cannot exist in a VM test).
/// Only the members the ported code actually reads are exposed.
abstract class ZmixPlayerSurface {
  ZmixPlayerSnapshot get state;
  Stream<Duration> get positionStream;
  Stream<Duration> get bufferStream;
  Stream<Duration> get durationStream;
  Stream<int?> get widthStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get playingStream;
}

/// Immutable view of the engine state fields the ported code reads.
class ZmixPlayerSnapshot {
  const ZmixPlayerSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.playing = false,
    this.width,
    this.height,
  });

  final Duration position;
  final Duration duration;
  final bool buffering;
  final bool playing;
  final int? width;
  final int? height;
}

/// Live media_kit-backed surface used by the real player page.
class MediaKitPlayerSurface implements ZmixPlayerSurface {
  MediaKitPlayerSurface(this.player);

  final Player player;

  @override
  ZmixPlayerSnapshot get state => ZmixPlayerSnapshot(
        position: player.state.position,
        duration: player.state.duration,
        buffering: player.state.buffering,
        playing: player.state.playing,
        width: player.state.width,
        height: player.state.height,
      );

  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<Duration> get bufferStream => player.stream.buffer;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
  @override
  Stream<int?> get widthStream => player.stream.width;
  @override
  Stream<bool> get bufferingStream => player.stream.buffering;
  @override
  Stream<bool> get playingStream => player.stream.playing;
}

class PlayerControlsOverlay extends StatelessWidget {
  const PlayerControlsOverlay({
    super.key,
    required this.player, // ZMIX-EDIT
    required this.episodeNumber, // ZMIX-EDIT: 1-based position in the playlist
    required this.episodeTitle, // ZMIX-EDIT: current video's own title
    required this.multiEpisode, // ZMIX-EDIT
    required this.hasNext, // ZMIX-EDIT
    required this.hasQualityChoices, // ZMIX-EDIT
    this.activeQualityLabel, // ZMIX-EDIT
    required this.onTogglePlay, // ZMIX-EDIT
    required this.onSeek, // ZMIX-EDIT: seek callback for the bar
    required this.onNext, // ZMIX-EDIT: null = no next
    required this.showTitle,
    required this.duration,
    required this.onDurationChanged,
    required this.onInteract,
    required this.onBack,
    required this.onSpeed,
    required this.onQuality,
    required this.onLock,
    required this.onRotate,
    required this.portraitMode,
    required this.barConfig,
    required this.onZoom,
    required this.zoomLabel,
    required this.onPrev,
    this.showQuality = false,
    this.visible = true,
  });

  final ZmixPlayerSurface player; // ZMIX-EDIT
  final int episodeNumber; // ZMIX-EDIT
  final String episodeTitle; // ZMIX-EDIT
  final bool multiEpisode; // ZMIX-EDIT
  final bool hasNext; // ZMIX-EDIT
  final bool hasQualityChoices; // ZMIX-EDIT
  final String? activeQualityLabel; // ZMIX-EDIT
  final VoidCallback onTogglePlay; // ZMIX-EDIT
  final void Function(Duration position) onSeek; // ZMIX-EDIT
  final VoidCallback? onNext; // ZMIX-EDIT
  final String? showTitle;
  final Duration duration;
  final ValueChanged<Duration> onDurationChanged;
  final VoidCallback onInteract;
  final VoidCallback onBack;
  final VoidCallback? onSpeed; // ZMIX-EDIT: nullable - null drops the button
  final VoidCallback? onQuality; // ZMIX-EDIT: nullable
  final VoidCallback onLock;
  final VoidCallback?
  onRotate; // flip between locked landscape and locked portrait
  final bool portraitMode; // true while watching upright

  /// The user's control arrangement — which bar each control sits on, in what
  /// order. Drives both bars; anything not placed is reachable via ⋮ More.
  final PlayerControlsConfig barConfig;

  final VoidCallback? onZoom; // ZMIX-EDIT: nullable
  final String zoomLabel;
  final VoidCallback? onPrev; // null = no previous episode
  final bool
  showQuality; // plain quality text on the top-bar right (with controls)
  final bool visible; // drives the bars' slide-in (top drops, bottom rises)

  /// Overflow panel that slides in from the RIGHT (like the episodes panel) —
  /// holds the occasional actions so the control bars stay clean.
  /// ZMIX-EDIT: upstream's panel rows target features ZMIX does not have
  /// (decoder, enhance, colour, snapshot, sleep, PiP, minimize, engine
  /// switch, ambient). They are omitted, not hidden behind dead buttons;
  /// the panel keeps upstream's surface/motion so future rows drop in.
  void _showMore(BuildContext context) {
    onInteract();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'More',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, _, _) {
        // Same width and surface as the episodes panel — this slides in from
        // the same edge with the same motion, so looking different was just
        // two panels wearing two skins. 40% was wider than it needed to be
        // for a short list of labels, too.
        final w = (MediaQuery.of(ctx).size.width * 0.33).clamp(250.0, 360.0);
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Material(
            color: Colors.transparent,
            child: FrostedSurface(
              blur: true,
              opacity: 0.88,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              child: SafeArea(
                left: false,
                child: SizedBox(
                  width: w,
                  height: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 8, 9),
                        child: Row(
                          children: [
                            Expanded(
                              // ZMIX-EDIT: inline Arabic (was ctx.l10n.more)
                              child: Text('المزيد', style: AppText.title),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textSecondary,
                              ),
                              tooltip: 'إغلاق', // ZMIX-EDIT (was ctx.l10n.close)
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: AppColors.hairline, height: 1),
                      const SizedBox(height: 4),
                      // ZMIX-EDIT: no occasional-action rows exist yet; the
                      // panel opens only when a future feature adds one.
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  /// Whether [id] sits on any bar. Used so a control that's already placed
  /// doesn't also get drawn by one of the player's own conditional buttons.
  bool _placedAnywhere(String id) => barConfig.slotOf(id) != ControlSlot.hidden;

  /// Top-bar versions of the arrangeable controls. Plain [IconButton]s rather
  /// than the bottom bar's chips, so anything moved up here matches the row
  /// it lands in instead of importing the bottom bar's look.
  List<Widget> _topButtons(BuildContext context, List<String> ids) {
    final out = <Widget>[];
    for (final id in ids) {
      // ZMIX-EDIT: upstream's special-cased 'cast'/'info' rows target
      // features ZMIX does not have; every id resolves through _specFor.
      final spec = _specFor(context, id);
      if (spec != null) {
        out.add(
          IconButton(
            icon: Icon(spec.$1, color: Colors.white),
            tooltip: spec.$2,
            onPressed: spec.$3,
          ),
        );
      }
    }
    return out;
  }

  /// Icon, tooltip and action for the controls that render the same wherever
  /// they're placed. Returns null when the control isn't available right now
  /// (no second quality to pick, a single-episode item, no PiP support).
  (IconData, String, VoidCallback)? _specFor(BuildContext context, String id) {
    // ZMIX-EDIT: only the controls ZMIX's YouTube player can act on resolve.
    // Unsupported ids (tracks/sources/episodes/decoder/enhance/colour/
    // snapshot/sleep/pip/...) fall through to null - upstream's own
    // mechanism for "not available right now", so a saved layout naming
    // them simply skips them. Labels are inline Arabic (was l10n).
    switch (id) {
      case 'speed':
        if (onSpeed == null) return null;
        return (Icons.speed_rounded, 'سرعة التشغيل', onSpeed!);
      case 'quality':
        // Nothing to switch inside the stream that's playing -> no button,
        // rather than a menu of other servers pretending to be qualities.
        if (!hasQualityChoices || onQuality == null) return null;
        return (Icons.high_quality_rounded, 'الجودة', onQuality!);
      case 'more':
        // ZMIX-EDIT: the More panel has no rows yet (every upstream row
        // targets a feature ZMIX does not have), so the button that would
        // open an empty panel drops out instead. Restore this spec the day
        // a real row lands in _showMore.
        return null;
      case 'fit':
        if (onZoom == null) return null;
        return (_fitIcon(zoomLabel), 'نسبة العرض · $zoomLabel', onZoom!);
      case 'rotate':
        if (onRotate == null) return null;
        return (
          Icons.screen_rotation_rounded,
          portraitMode ? 'أفقي' : 'رأسي',
          onRotate!,
        );
    }
    return null; // unknown id — a layout from a newer build
  }

  /// Turns saved control ids into real buttons.
  ///
  /// The availability rules that were baked into the old fixed row still
  /// apply on top of the user's arrangement — Quality with nothing to pick
  /// between, Episodes on a single-episode item and PiP where the device
  /// doesn't support it drop out even if they've been placed on the bar.
  /// Anything unrecognised is skipped rather than crashing, which is what
  /// makes a layout saved by a newer build safe to load.
  List<Widget> _barButtons(BuildContext context, List<String> ids) {
    return [
      for (final id in ids)
        if (_specFor(context, id) case (final icon, final tip, final tap))
          _BarButton(icon: icon, tooltip: tip, onTap: tap),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // ZMIX-EDIT: episode facts arrive as plain fields (no PlayerCubit).
    final epNum = episodeNumber;
    // The episode's own name, but only when it's more than a generic
    // "Episode N" / bare number (many sources just echo the number there).
    final epName = episodeTitle.trim();
    final hasEpName =
        epName.isNotEmpty &&
        epName.toLowerCase() != 'episode $epNum' &&
        epName != '$epNum';
    // Line 1 = show name (falls back to "Episode N" when no show title).
    final primaryTitle = showTitle ?? 'Episode $epNum';
    // Line 2 = "E5 · Episode Name" — only when there's a show name above it to
    // pair with (otherwise line 1 already carries the episode number).
    final secondaryTitle = showTitle == null
        ? null
        : 'E$epNum${hasEpName ? ' · $epName' : ''}';
    // Quality appended to the E-line when enabled — prefers
    // the source's quality label, else the live video height (e.g. "1080p").
    String? qualityLabel;
    if (showQuality) {
      // ZMIX-EDIT: the resolved label arrives as a field; the live-height
      // fallback still reads media_kit's player state directly.
      final q = activeQualityLabel?.trim();
      if (q != null && q.isNotEmpty && q.toLowerCase() != 'auto') {
        qualityLabel = q;
      } else {
        final h = player.state.height ?? 0;
        if (h > 0) qualityLabel = '${h}p';
      }
    }
    final secondaryLine = qualityLabel == null
        ? secondaryTitle
        : (secondaryTitle == null
              ? qualityLabel
              : '$secondaryTitle · $qualityLabel');
    // ZMIX-EDIT: hasNext / multiEpisode arrive as fields. Upstream's note
    // stands: an episode nothing has yet is not a next episode, and one-off
    // items get a lone play button rather than two dead arrows.

    return Stack(
      fit: StackFit.expand,
      children: [
        // Top scrim.
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 110,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x59000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
        // Bottom scrim. There were two of these stacked at each end — 0xCC over
        // 0x99 up top, 0xE6 over 0xB3 down here — which is why showing the
        // controls dropped a heavy curtain over the video. One gentle pass each
        // way is plenty to keep white text legible on a bright frame.
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 170,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x8C000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),

        // Top bar.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            // Vertical insets only. Now that the window draws into the display
            // cutout, the horizontal safe inset is the camera's — and it exists
            // on one edge only, so honouring it shunts the whole bar sideways
            // and the margins stop matching. The cutout sits mid-edge; this bar
            // is pinned to the top, so they never meet.
            left: false,
            right: false,
            child: Padding(
              // 32, not the bottom block's 44, and the difference is on
              // purpose: these are IconButtons, which reserve 12px around the
              // glyph before it draws (8 default padding, plus 4 stretching the
              // 40px button out to the 48px minimum touch target). 32 + 12 puts
              // the back arrow on 44 — the exact line the bottom capsules start
              // at. Writing 44 here would land it at 56 and overshoot inward.
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'رجوع', // ZMIX-EDIT (was context.l10n.back)
                    onPressed: onBack,
                  ),
                  // Text hit-tests as opaque (RenderParagraph.hitTestSelf is
                  // true), so the title used to eat taps aimed at the video —
                  // a wide dead strip across the top where tapping did nothing.
                  // Nothing here is interactive, so let taps fall through to the
                  // zones below and toggle the controls like anywhere else.
                  Expanded(
                    child: IgnorePointer(
                      child: _ShowAfterFirstFrame(
                        // Show / episode names stay hidden behind the startup
                        // loader, then fade in.
                        player: player, // ZMIX-EDIT
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    primaryTitle,
                                    style: AppText.headline.copyWith(
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // ZMIX-EDIT: the Jikan filler badge is
                                // omitted - YouTube videos carry no filler
                                // lookup.
                              ],
                            ),
                            if (secondaryLine != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  secondaryLine,
                                  style: AppText.caption.copyWith(
                                    color: Colors.white70,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Whatever the user put up here, in their order. Cast and
                  // the ⓘ stats toggle live here by default; anything else in
                  // the registry can be moved up in Settings.
                  ..._topButtons(context, barConfig.top),
                  // ZMIX-EDIT: the armed-sleep moon, the Settings shortcut
                  // and the room-chat button are omitted - none of those
                  // features exist in ZMIX.
                  // Episodes and ⋮ More live in the bottom bar now — a second
                  // copy up here just split the same action across two places.
                  // Lock stays: it's the one control you want reachable without
                  // looking down at the bar you're about to hide.
                  IconButton(
                    icon: const Icon(
                      Icons.lock_open_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'قفل', // ZMIX-EDIT (was context.l10n.lockControls)
                    onPressed: onLock,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Centre transport — episode step either side of play/pause. The ±10s
        // buttons used to live here, but they jumped a hardcoded 10s while
        // double-tap honoured the user's Double-tap skip setting, so the two
        // disagreed; seeking is covered by double-tap, drag-to-seek and the
        // MegaSkip pill, all of which read the same preference.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (multiEpisode) ...[
                _TransportButton(
                  icon: Icons.skip_previous_rounded,
                  label: 'السابق', // ZMIX-EDIT (was context.l10n.previousEpisode)
                  onTap: onPrev,
                ),
                const SizedBox(width: 24),
              ],
              StreamBuilder<int?>(
                stream: player.widthStream, // ZMIX-EDIT
                initialData: player.state.width,
                builder: (context, frame) {
                  return StreamBuilder<bool>(
                    stream: player.bufferingStream,
                    builder: (context, bSnap) {
                      final buffering = bSnap.data ?? player.state.buffering;
                      // While buffering, show the spinner IN PLACE OF the play/pause
                      // button — no more spinner-over-button overlap. 58px matches
                      // _AnimatedPlayPause's disc exactly, so the episode arrows
                      // don't twitch every time playback stalls.
                      if (buffering) {
                        if ((frame.data ?? 0) <= 0) {
                          return const SizedBox(width: 58, height: 58);
                        }
                        return const SizedBox(
                          width: 58,
                          height: 58,
                          child: Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<bool>(
                        stream: player.playingStream,
                        builder: (context, snap) {
                          final playing = snap.data ?? player.state.playing;
                          return _AnimatedPlayPause(
                            playing: playing,
                            onTap: () {
                              onTogglePlay(); // ZMIX-EDIT
                              onInteract();
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
              if (multiEpisode) ...[
                const SizedBox(width: 24),
                _TransportButton(
                  icon: Icons.skip_next_rounded,
                  label: 'التالي', // ZMIX-EDIT (was context.l10n.nextEpisode2)
                  onTap: hasNext && onNext != null
                      ? () {
                          onNext!(); // ZMIX-EDIT
                          onInteract();
                        }
                      : null,
                ),
              ],
            ],
          ),
        ),

        // Bottom: seek row + buttons. Rises into place as it fades in — the
        // motion reads as instant even when the tap resolves a beat later.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.14),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: SafeArea(
              top: false,
              // Vertical inset only — the bottom one keeps the bar clear of the
              // gesture nav. See the top bar for why the horizontal cutout inset
              // is skipped: it lands on one edge only and pushed this whole block
              // sideways, leaving a fat gap on the camera side and a thin one
              // opposite. The camera sits mid-edge, well clear of this bar.
              left: false,
              right: false,
              child: Padding(
                // One margin for the whole block — timestamp, progress bar and
                // both button groups share it, so every edge lines up. Kept wide
                // so the controls sit clear of the screen edges.
                padding: const EdgeInsets.fromLTRB(44, 0, 44, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Duration tracker (off-screen listener via StreamBuilder).
                    StreamBuilder<Duration>(
                      stream: player.durationStream, // ZMIX-EDIT
                      initialData: player.state.duration,
                      builder: (context, snap) {
                        final d = snap.data ?? duration;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (d > Duration.zero) onDurationChanged(d);
                        });
                        return PlayerSeekBar(
                          player: player, // ZMIX-EDIT
                          onSeek: onSeek, // ZMIX-EDIT
                          duration: d > Duration.zero ? d : duration,
                          onInteract: onInteract,
                          // ZMIX-EDIT: MegaSkip (Aniyomi jump-forward pill)
                          // omitted - ZMIX has no skip preference to honour.
                          trailing: null,
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                    // Control bar under the progress bar: the pickers ride in one
                    // translucent group on the left, episode list + fit mode in
                    // another on the right. Two groups rather than seven floating
                    // chips — the split reads at a glance, and every button is the
                    // same width so nothing shifts as the video changes.
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Rendered from the user's saved arrangement rather than
                        // a fixed row. Untouched prefs give the defaults, which
                        // are the exact layout that shipped before the Settings
                        // screen existed — so nobody's bar moves unless they
                        // move it.
                        final left = _barButtons(context, barConfig.left);
                        final right = _barButtons(context, barConfig.right);
                        // Buttons are a uniform 48 (12 padding + 24 icon + 12)
                        // and each group adds 8 of its own, so the width the bar
                        // wants is arithmetic rather than something to measure.
                        const buttonWidth = 48.0;
                        const groupPadding = 8.0;
                        double groupWidth(int n) =>
                            n == 0 ? 0 : n * buttonWidth + groupPadding;
                        final wanted =
                            groupWidth(left.length) + groupWidth(right.length);

                        if (wanted <= constraints.maxWidth) {
                          return Row(
                            children: [
                              if (left.isNotEmpty) _BarGroup(children: left),
                              const Spacer(),
                              if (right.isNotEmpty) _BarGroup(children: right),
                            ],
                          );
                        }
                        // Narrower than the bar wants — portrait, or a bar the
                        // user has loaded up in Settings. The Spacer pins the
                        // groups to opposite edges and can't give any width back,
                        // so the right-hand group would run off-screen and take
                        // its buttons out of reach. Scroll the pair instead:
                        // everything stays tappable, and nothing about the
                        // landscape layout above changes.
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (left.isNotEmpty) _BarGroup(children: left),
                              if (left.isNotEmpty && right.isNotEmpty)
                                const SizedBox(width: 8),
                              if (right.isNotEmpty) _BarGroup(children: right),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seek row — current time + slider (stream-bound) + total time.
// ─────────────────────────────────────────────────────────────────────────────

/// Fades its child in once the first video frame is up — or playback has
/// started, so audio-only media (no frame, ever) isn't left without a title.
/// Latches: a later source switch resetting the width doesn't hide it again.
class _ShowAfterFirstFrame extends StatefulWidget {
  const _ShowAfterFirstFrame({required this.player, required this.child});

  final ZmixPlayerSurface player; // ZMIX-EDIT
  final Widget child;

  @override
  State<_ShowAfterFirstFrame> createState() => _ShowAfterFirstFrameState();
}

class _ShowAfterFirstFrameState extends State<_ShowAfterFirstFrame> {
  late bool _shown = _ready();
  final _subs = <StreamSubscription<Object?>>[];

  bool _ready() {
    final p = widget.player.state;
    return (p.width ?? 0) > 0 || p.playing;
  }

  void _check() {
    if (!_shown && mounted && _ready()) setState(() => _shown = true);
  }

  @override
  void initState() {
    super.initState();
    _subs
      // ZMIX-EDIT: surface getters (was media_kit's player.stream).
      ..add(widget.player.widthStream.listen((_) => _check()))
      ..add(widget.player.playingStream.listen((_) => _check()));
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _shown ? 1 : 0,
    duration: const Duration(milliseconds: 250),
    child: widget.child,
  );
}
