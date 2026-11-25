import 'package:flutter/material.dart';

/// Pure presentation layer of the ZMIX player overlay: top bar, bottom
/// controls, seek indicator, brightness/volume HUD, speed-boost badge and
/// error banner. No media_kit dependency: PlayerPage feeds it live state,
/// and tests/goldens render the exact same widget with fixed state.
class PlayerChrome extends StatelessWidget {
  const PlayerChrome({
    super.key,
    required this.title,
    required this.position,
    required this.duration,
    required this.playing,
    required this.rate,
    this.qualityLabel,
    this.controlsVisible = true,
    this.seekDelta = 0,
    this.seekForward = true,
    this.hudVisible = false,
    this.hudIsBrightness = false,
    this.hudValue = 0,
    this.boosting = false,
    this.errorText,
    this.onBack,
    this.onPlayPause,
    this.onCycleSpeed,
    this.onScrubChanged,
    this.onScrubEnd,
  });

  final String title;
  final Duration position;
  final Duration duration;
  final bool playing;
  final double rate;
  final String? qualityLabel;
  final bool controlsVisible;
  final int seekDelta;
  final bool seekForward;
  final bool hudVisible;
  final bool hudIsBrightness;
  final double hudValue;
  final bool boosting;
  final String? errorText;
  final VoidCallback? onBack;
  final VoidCallback? onPlayPause;
  final VoidCallback? onCycleSpeed;
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
        if (seekDelta != 0) _seekIndicator(),
        if (hudVisible) _hud(),
        if (boosting) _boostBadge(),
        if (controlsVisible) _topBar(context),
        if (controlsVisible) _bottomBar(context),
        if (errorText != null) _errorBanner(context),
      ],
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
    return Center(
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
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: hudValue,
                minHeight: 5,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF7C6CFF)),
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
          color: const Color(0xFF7C6CFF).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('2×',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (qualityLabel != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Text(
                  qualityLabel!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFC9C9D4)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final fraction = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(fmt(position), style: const TextStyle(fontSize: 12)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: fraction,
                      onChanged: onScrubChanged,
                      onChangeEnd: onScrubEnd,
                    ),
                  ),
                ),
                Text(fmt(duration), style: const TextStyle(fontSize: 12)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  onPressed: onPlayPause,
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onCycleSpeed,
                  child: Text(
                    '${rate}x',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'حصل خطأ في التشغيل: $errorText',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
