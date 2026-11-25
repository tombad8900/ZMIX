import 'package:flutter/material.dart';

/// Player overlay for ZMIX.
///
/// The layout architecture is adapted from Zangetsu's player controls
/// (https://github.com/Spyou/Zangetsu), GPL-3.0:
///  - top scrim + two-line title bar (primary title, secondary quality line)
///    with a lock button;
///  - centre transport: previous / play-pause disc / next;
///  - one bottom block: seek row (position · slider · total-or-remaining)
///    above a row of translucent button capsules (pickers left, fit right);
///  - coral accent #FF4D57 and the scrim alpha values from the same source.
///
/// Adapted to ZMIX's stateless-chrome/player-page split and RTL Arabic UI;
/// ZMIX remains GPL-3.0. No code is copied verbatim without adaptation.
class PlayerChrome extends StatelessWidget {
  const PlayerChrome({
    super.key,
    required this.title,
    required this.position,
    required this.duration,
    required this.playing,
    required this.rate,
    this.secondaryText,
    this.buffering = false,
    this.controlsVisible = true,
    this.locked = false,
    this.fitLabel = '',
    this.hasPrev = false,
    this.hasNext = false,
    this.seekDelta = 0,
    this.seekForward = true,
    this.hudVisible = false,
    this.hudIsBrightness = false,
    this.hudValue = 0,
    this.boosting = false,
    this.errorText,
    this.onBack,
    this.onPlayPause,
    this.onPrev,
    this.onNext,
    this.onCycleSpeed,
    this.onQuality,
    this.onCycleFit,
    this.onToggleLock,
    this.onScrubChanged,
    this.onScrubEnd,
  });

  static const Color accent = Color(0xFFFF4D57);

  final String title;
  final String? secondaryText;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final double rate;
  final bool controlsVisible;
  final bool locked;
  final String fitLabel;
  final bool hasPrev;
  final bool hasNext;
  final int seekDelta;
  final bool seekForward;
  final bool hudVisible;
  final bool hudIsBrightness;
  final double hudValue;
  final bool boosting;
  final String? errorText;
  final VoidCallback? onBack;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onCycleSpeed;
  final VoidCallback? onQuality;
  final VoidCallback? onCycleFit;
  final VoidCallback? onToggleLock;
  final ValueChanged<double>? onScrubChanged;
  final ValueChanged<double>? onScrubEnd;

  static String fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Scrim values adapted from Zangetsu's _ControlsOverlay.
        if (controlsVisible && !locked) ...[
          const Positioned(
            top: 0, left: 0, right: 0, height: 110,
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
          const Positioned(
            bottom: 0, left: 0, right: 0, height: 170,
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
        ],
        if (seekDelta != 0 && !locked) _seekIndicator(),
        if (hudVisible && !locked) _hud(),
        if (boosting && !locked) _boostBadge(),
        if (controlsVisible || locked) _topBar(),
        if (controlsVisible && !locked) _centerTransport(),
        if (controlsVisible && !locked) _bottomBlock(context),
        if (errorText != null && !locked) _errorBanner(),
      ],
    );
  }

  Widget _topBar() {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: locked ? null : onBack,
              ),
              Expanded(
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (secondaryText != null && secondaryText!.isNotEmpty)
                        Text(
                          secondaryText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: locked ? accent : Colors.white,
                ),
                onPressed: onToggleLock,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centerTransport() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPrev) ...[
            _TransportButton(
                icon: Icons.skip_previous_rounded, onTap: onPrev),
            const SizedBox(width: 24),
          ],
          if (buffering)
            const SizedBox(
              width: 58,
              height: 58,
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3),
                ),
              ),
            )
          else
            _PlayPauseDisc(playing: playing, onTap: onPlayPause),
          if (hasNext) ...[
            const SizedBox(width: 24),
            _TransportButton(icon: Icons.skip_next_rounded, onTap: onNext),
          ],
        ],
      ),
    );
  }

  Widget _bottomBlock(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          // One shared margin so every edge lines up (Zangetsu uses 44/14).
          padding: const EdgeInsets.fromLTRB(44, 0, 44, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SeekRow(
                position: position,
                duration: duration,
                onChanged: onScrubChanged,
                onChangeEnd: onScrubEnd,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _BarGroup(children: [
                    _BarButton(
                      onTap: onCycleSpeed,
                      child: Text(
                        '${rate}x',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Colors.white),
                      ),
                    ),
                    _BarButton(
                      onTap: onQuality,
                      child: const Icon(Icons.hd_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ]),
                  const Spacer(),
                  _BarGroup(children: [
                    _BarButton(
                      onTap: onCycleFit,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.aspect_ratio_rounded,
                              color: Colors.white, size: 20),
                          if (fitLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              fitLabel,
                              style: const TextStyle(
                                  fontSize: 12.5, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seekIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              seekForward
                  ? Icons.fast_forward_rounded
                  : Icons.fast_rewind_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              '${seekDelta.abs()} ث',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hud() {
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hudIsBrightness
                  ? Icons.wb_sunny_outlined
                  : Icons.volume_up_rounded,
              size: 22,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: hudValue,
                minHeight: 5,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boostBadge() {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('2×',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }

  Widget _errorBanner() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'حصل خطأ في التشغيل: $errorText',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
      ),
    );
  }
}

/// Seek row: position · slider · total/remaining (tap the trailing time to
/// flip between the two, CloudStream-style, as Zangetsu's PlayerSeekBar does).
class _SeekRow extends StatefulWidget {
  const _SeekRow({
    required this.position,
    required this.duration,
    this.onChanged,
    this.onChangeEnd,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<_SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends State<_SeekRow> {
  bool _showRemaining = false;

  @override
  Widget build(BuildContext context) {
    final fraction = widget.duration > Duration.zero
        ? (widget.position.inMilliseconds / widget.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final trailing = _showRemaining
        ? '-${PlayerChrome.fmt(widget.duration - widget.position)}'
        : PlayerChrome.fmt(widget.duration);
    return Row(
      children: [
        Text(
          PlayerChrome.fmt(widget.position),
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: PlayerChrome.accent,
              thumbColor: PlayerChrome.accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: fraction,
              onChanged: widget.onChanged,
              onChangeEnd: widget.onChangeEnd,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _showRemaining = !_showRemaining),
          child: Text(
            trailing,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// 58px centre play/pause disc (Zangetsu's _AnimatedPlayPause footprint).
class _PlayPauseDisc extends StatelessWidget {
  const _PlayPauseDisc({required this.playing, this.onTap});

  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon,
              color: onTap == null ? Colors.white38 : Colors.white, size: 26),
        ),
      ),
    );
  }
}

/// Translucent capsule grouping bar buttons (Zangetsu's _BarGroup).
class _BarGroup extends StatelessWidget {
  const _BarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );
  }
}
