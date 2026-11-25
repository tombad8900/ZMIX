import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// ZMIX custom player. Design language adapted from Zangetsu (GPL-3.0):
/// auto-hiding overlay, double-tap seek, long-press speed boost,
/// vertical brightness/volume swipes with a HUD, horizontal scrub.
/// Implementation written for ZMIX on media_kit.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.streamUrl,
    this.qualityLabel,
  });

  final String title;
  final String streamUrl;
  final String? qualityLabel;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with TickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  String? _error;

  // Seek feedback (double-tap and scrub)
  int _seekDelta = 0; // seconds, signed; 0 = hidden
  bool _seekForward = true;
  Timer? _seekResetTimer;

  // Scrub (horizontal drag)
  bool _scrubbing = false;
  Duration _scrubPosition = Duration.zero;

  // HUD (brightness / volume)
  bool _hudVisible = false;
  bool _hudIsBrightness = false;
  double _hudValue = 0; // 0..1
  Timer? _hudTimer;

  // Speed
  double _rate = 1.0;
  double _rateBeforeBoost = 1.0;
  bool _boosting = false;
  static const List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _player.open(Media(widget.streamUrl), play: true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekResetTimer?.cancel();
    _hudTimer?.cancel();
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) => -1.0);
    super.dispose();
  }

  // ── Controls visibility ────────────────────────────────────────────────

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_scrubbing) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  // ── Gestures ───────────────────────────────────────────────────────────

  Future<void> _doubleTapSeek(bool forward) async {
    final position = _player.state.position;
    final duration = _player.state.duration;
    var delta = (_seekDelta.abs() + 10) * (forward ? 1 : -1);
    var target = position + Duration(seconds: delta);
    if (target < Duration.zero) {
      delta = -position.inSeconds;
      target = Duration.zero;
    }
    if (duration > Duration.zero && target > duration) {
      delta = duration.inSeconds - position.inSeconds;
      target = duration;
    }
    await _player.seek(target);
    _seekResetTimer?.cancel();
    setState(() {
      _seekDelta = delta;
      _seekForward = forward;
    });
    _seekResetTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _seekDelta = 0);
    });
  }

  void _startBoost(LongPressStartDetails _) {
    _rateBeforeBoost = _rate;
    if (_rateBeforeBoost <= 0) _rateBeforeBoost = 1.0;
    setState(() => _boosting = true);
    _player.setRate(2.0);
  }

  void _endBoost(LongPressEndDetails _) {
    setState(() => _boosting = false);
    _player.setRate(_rateBeforeBoost);
  }

  void _startScrub(DragStartDetails _) {
    _hideTimer?.cancel();
    setState(() {
      _scrubbing = true;
      _scrubPosition = _player.state.position;
    });
  }

  void _updateScrub(DragUpdateDetails details) {
    final width = MediaQuery.of(context).size.width;
    final duration = _player.state.duration;
    if (duration <= Duration.zero || width <= 0) return;
    final deltaSeconds = (details.primaryDelta ?? 0) / width * 120; // full width = 2 min
    setState(() {
      _scrubPosition += Duration(milliseconds: (deltaSeconds * 1000).round());
      if (_scrubPosition < Duration.zero) _scrubPosition = Duration.zero;
      if (_scrubPosition > duration) _scrubPosition = duration;
    });
  }

  Future<void> _endScrub(DragEndDetails _) async {
    final target = _scrubPosition;
    setState(() => _scrubbing = false);
    await _player.seek(target);
    _scheduleHide();
  }

  Future<void> _startVerticalDrag(DragStartDetails details) async {
    final isLeft = details.localPosition.dx < MediaQuery.of(context).size.width / 2;
    double value = 0.5;
    if (isLeft) {
      try {
        value = await ScreenBrightness.instance.application;
      } catch (_) {}
    } else {
      value = _player.state.volume / 100;
    }
    setState(() {
      _hudIsBrightness = isLeft;
      _hudValue = value.clamp(0.0, 1.0);
      _hudVisible = true;
    });
  }

  void _updateVerticalDrag(DragUpdateDetails details) {
    final height = MediaQuery.of(context).size.height;
    if (height <= 0) return;
    final delta = -(details.primaryDelta ?? 0) / height * 1.2;
    setState(() => _hudValue = (_hudValue + delta).clamp(0.0, 1.0));
    if (_hudIsBrightness) {
      ScreenBrightness.instance.setApplicationScreenBrightness(_hudValue).catchError((_) {});
    } else {
      _player.setVolume(_hudValue * 100);
    }
    _hudTimer?.cancel();
  }

  void _endVerticalDrag(DragEndDetails _) {
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  void _cycleSpeed() {
    final i = _speeds.indexOf(_rate);
    final next = _speeds[(i + 1) % _speeds.length];
    setState(() => _rate = next);
    _player.setRate(next);
    _scheduleHide();
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Video(controller: _controller, controls: NoVideoControls)),
          _gestureLayer(),
          if (_seekDelta != 0) _seekIndicator(),
          if (_hudVisible) _hud(),
          if (_boosting) _boostBadge(),
          if (_controlsVisible) _topBar(),
          if (_controlsVisible) _bottomBar(),
          if (_error != null) _errorBanner(),
        ],
      ),
    );
  }

  Widget _gestureLayer() {
    return Row(
      children: [
        Expanded(child: _gestureHalf(isLeft: true)),
        Expanded(child: _gestureHalf(isLeft: false)),
      ],
    );
  }

  Widget _gestureHalf({required bool isLeft}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTap: () => _doubleTapSeek(!isLeft),
      onLongPressStart: _startBoost,
      onLongPressEnd: _endBoost,
      onHorizontalDragStart: _startScrub,
      onHorizontalDragUpdate: _updateScrub,
      onHorizontalDragEnd: _endScrub,
      onVerticalDragStart: _startVerticalDrag,
      onVerticalDragUpdate: _updateVerticalDrag,
      onVerticalDragEnd: _endVerticalDrag,
      child: const SizedBox.expand(),
    );
  }

  Widget _seekIndicator() {
    return Center(
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 150),
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
                _seekForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '${_seekDelta.abs()} ث',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
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
              _hudIsBrightness ? Icons.wb_sunny_outlined : Icons.volume_up_rounded,
              size: 22,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _hudValue,
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
        child: const Text('2×', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }

  Widget _topBar() {
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
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (widget.qualityLabel != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Text(
                  widget.qualityLabel!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFC9C9D4)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
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
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              initialData: _player.state.position,
              builder: (context, snap) {
                final position = _scrubbing ? _scrubPosition : (snap.data ?? Duration.zero);
                final duration = _player.state.duration;
                return Row(
                  children: [
                    Text(_fmt(position), style: const TextStyle(fontSize: 12)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: duration > Duration.zero
                              ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                              : 0,
                          onChanged: (v) {
                            _hideTimer?.cancel();
                            setState(() {
                              _scrubbing = true;
                              _scrubPosition = Duration(
                                milliseconds: (v * duration.inMilliseconds).round(),
                              );
                            });
                          },
                          onChangeEnd: (v) {
                            final target = Duration(
                              milliseconds: (v * duration.inMilliseconds).round(),
                            );
                            setState(() => _scrubbing = false);
                            _player.seek(target);
                            _scheduleHide();
                          },
                        ),
                      ),
                    ),
                    Text(_fmt(duration), style: const TextStyle(fontSize: 12)),
                  ],
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  initialData: _player.state.playing,
                  builder: (context, snap) => IconButton(
                    iconSize: 40,
                    icon: Icon(
                      (snap.data ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    onPressed: () {
                      _player.playOrPause();
                      _scheduleHide();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _cycleSpeed,
                  child: Text(
                    '${_rate}x',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'حصل خطأ في التشغيل: $_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        ),
      ),
    );
  }
}
