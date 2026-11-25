import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'player_chrome.dart';

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


  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Video(controller: _controller, controls: NoVideoControls)),
          _gestureLayer(),
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (context, posSnap) {
              return StreamBuilder<bool>(
                stream: _player.stream.playing,
                initialData: _player.state.playing,
                builder: (context, playSnap) {
                  return PlayerChrome(
                    title: widget.title,
                    qualityLabel: widget.qualityLabel,
                    position: _scrubbing
                        ? _scrubPosition
                        : (posSnap.data ?? Duration.zero),
                    duration: _player.state.duration,
                    playing: playSnap.data ?? false,
                    rate: _rate,
                    controlsVisible: _controlsVisible,
                    seekDelta: _seekDelta,
                    seekForward: _seekForward,
                    hudVisible: _hudVisible,
                    hudIsBrightness: _hudIsBrightness,
                    hudValue: _hudValue,
                    boosting: _boosting,
                    errorText: _error,
                    onBack: () => Navigator.of(context).pop(),
                    onPlayPause: () {
                      _player.playOrPause();
                      _scheduleHide();
                    },
                    onCycleSpeed: _cycleSpeed,
                    onScrubChanged: (v) {
                      _hideTimer?.cancel();
                      setState(() {
                        _scrubbing = true;
                        _scrubPosition = Duration(
                          milliseconds:
                              (v * _player.state.duration.inMilliseconds)
                                  .round(),
                        );
                      });
                    },
                    onScrubEnd: (v) {
                      final target = Duration(
                        milliseconds:
                            (v * _player.state.duration.inMilliseconds).round(),
                      );
                      setState(() => _scrubbing = false);
                      _player.seek(target);
                      _scheduleHide();
                    },
                  );
                },
              );
            },
          ),
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

}
