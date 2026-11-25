import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'models.dart';
import 'player/player_controls_config.dart';
import 'player/player_controls_overlay.dart';
import 'player_chrome.dart';
import 'player_hud.dart';
import 'storage.dart';
import 'youtube_service.dart';

/// ZMIX custom player. The controls overlay is a literal port of Zangetsu's
/// PlayerControlsOverlay + PlayerSeekBar + widgets (GPL-3.0, lib/player/),
/// wired to media_kit through [MediaKitPlayerSurface]; ZMIX-specific extras
/// (double-tap seek indicator, brightness/volume HUD, 2x boost badge, lock
/// overlay, error panel) live in player_hud.dart. Playback on media_kit.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.streamUrl,
    this.qualityLabel,
    this.videoId,
    this.siblings,
    this.videoIndex = 0,
    this.store,
    this.playlistName,
  });

  final String title;
  final String streamUrl;
  final String? qualityLabel;
  final String? videoId;

  /// Ordered videos of the containing playlist, for prev/next transport.
  final List<LibraryVideo>? siblings;
  final int videoIndex;
  final LibraryStore? store;
  final String? playlistName;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with TickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;

  late String _title;
  late int _index;
  String? _currentQuality;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  String? _error;

  // Fit trio lives in player_chrome.dart (kPlayerFits).
  int _fitIndex = 0;

  bool _locked = false;

  // The URL currently loaded in the player (stream or chosen quality).
  late String _currentUrl;

  // Available muxed qualities (best first), fetched after open.
  List<({String url, String quality})> _qualities = [];

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
    _title = widget.title;
    _index = widget.videoIndex;
    _currentQuality = widget.qualityLabel;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _currentUrl = widget.streamUrl;
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
    });
    _player.open(Media(widget.streamUrl), play: true);
    _loadQualities();
    _scheduleHide();
  }

  Future<void> _loadQualities() async {
    final id = widget.videoId ??
        ((_index < (widget.siblings?.length ?? 0))
            ? widget.siblings![_index].id
            : null);
    if (id == null || kIsWeb) return;
    final service = YoutubeService();
    try {
      final list = await service.resolvePlayableList(id);
      if (mounted) setState(() => _qualities = list);
    } catch (_) {
      // Quality picker stays hidden; playback continues on the opened stream.
    } finally {
      service.close();
    }
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
    if (_locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  /// Upstream's _bumpControls: any interaction with the overlay shows the
  /// controls again and restarts the auto-hide countdown.
  void _bumpControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      if (_locked) _controlsVisible = false;
    });
    if (!_locked) {
      setState(() => _controlsVisible = true);
      _scheduleHide();
    }
  }

  void _cycleFit() {
    setState(() => _fitIndex = nextFitIndex(_fitIndex));
    _scheduleHide();
  }

  // ── Pinch-to-zoom (ported from Zangetsu player_screen.dart, GPL-3.0) ────
  // Raw-pointer driven so it never fights the 1-finger gestures. Two fingers
  // down -> start; their spread sets the zoom and their midpoint pans;
  // releasing a finger ends it (snapping back to fit when near 1x).
  double _zoom = 1.0;
  Offset _zoomPan = Offset.zero;
  bool _pinching = false;
  final Map<int, Offset> _pointers = {};
  double _pinchBaseDist = 0;
  double _pinchBaseZoom = 1.0;
  Offset _pinchBaseFocal = Offset.zero;
  Offset _pinchBasePan = Offset.zero;

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && !_locked) _startPinch();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pinching && _pointers.length >= 2) _updatePinch();
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _pinching) _endPinch();
  }

  void _startPinch() {
    final p = _pointers.values.toList();
    _pinchBaseDist = (p[0] - p[1]).distance;
    _pinchBaseFocal = Offset((p[0].dx + p[1].dx) / 2, (p[0].dy + p[1].dy) / 2);
    _pinchBaseZoom = _zoom;
    _pinchBasePan = _zoomPan;
    setState(() {
      _pinching = true;
      _scrubbing = false; // cancel any 1-finger scrub the first finger started
      _hudVisible = false; // and any brightness/volume HUD
    });
  }

  void _updatePinch() {
    if (_pinchBaseDist <= 0) return;
    final p = _pointers.values.toList();
    final dist = (p[0] - p[1]).distance;
    final focal = Offset((p[0].dx + p[1].dx) / 2, (p[0].dy + p[1].dy) / 2);
    final z = (_pinchBaseZoom * dist / _pinchBaseDist).clamp(1.0, 4.0);
    setState(() {
      _zoom = z;
      _zoomPan = _clampPan(_pinchBasePan + (focal - _pinchBaseFocal), z);
    });
  }

  void _endPinch() {
    setState(() {
      _pinching = false;
      if (_zoom < 1.08) {
        // pinched back near fit -> snap cleanly to 1x and recentre
        _zoom = 1.0;
        _zoomPan = Offset.zero;
      }
    });
  }

  /// Keep the panned, zoomed video from sliding past its own edges.
  Offset _clampPan(Offset pan, double zoom) {
    final size = MediaQuery.of(context).size;
    final maxX = (zoom - 1) * size.width / 2;
    final maxY = (zoom - 1) * size.height / 2;
    return Offset(
      pan.dx.clamp(-maxX, maxX).toDouble(),
      pan.dy.clamp(-maxY, maxY).toDouble(),
    );
  }

  /// Retry after a playback error: reopen the current stream from scratch.
  void _retry() {
    setState(() => _error = null);
    _player.open(Media(_currentUrl), play: true);
    _loadQualities();
    _scheduleHide();
  }

  // ── Quality ────────────────────────────────────────────────────────────

  void _openQualitySheet() {
    if (_qualities.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return QualityListSheet(
          qualities: [for (final q in _qualities) q.quality],
          activeQuality: _currentQuality ?? '',
          onPick: (label) {
            final q = _qualities.firstWhere((q) => q.quality == label);
            Navigator.of(sheetContext).pop();
            _switchQuality(q);
          },
        );
      },
    );
  }

  Future<void> _switchQuality(({String url, String quality}) q) async {
    if (q.quality == _currentQuality) return;
    final resume = _player.state.position;
    final wasPlaying = _player.state.playing;
    setState(() {
      _currentQuality = q.quality;
      _error = null;
    });
    _currentUrl = q.url;
    await _player.open(Media(q.url), play: wasPlaying);
    if (resume > Duration.zero) {
      // Seek only once the new stream knows its duration.
      late StreamSubscription sub;
      sub = _player.stream.duration.listen((d) {
        if (d > Duration.zero) {
          sub.cancel();
          _player.seek(resume < d ? resume : d);
        }
      });
    }
  }

  // ── Previous / next in playlist ────────────────────────────────────────

  Future<void> _goToSibling(int delta) async {
    final siblings = widget.siblings;
    if (siblings == null || siblings.isEmpty) return;
    final next = _index + delta;
    if (next < 0 || next >= siblings.length) return;
    final video = siblings[next];
    final service = YoutubeService();
    try {
      final stream = await service.resolvePlayable(video.id);
      await widget.store?.recordPlay(
        videoId: video.id,
        title: video.title,
        thumbUrl: video.thumbUrl,
        playlistName: widget.playlistName ?? '',
      );
      if (!mounted) return;
      setState(() {
        _index = next;
        _title = video.title;
        _currentQuality = stream.quality;
        _error = null;
        _qualities = [];
        _zoom = 1.0;
        _zoomPan = Offset.zero;
      });
      _currentUrl = stream.url;
      await _player.open(Media(stream.url), play: true);
      _loadQualities();
      _scheduleHide();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'مش قادرين نشغّل الفيديو ده دلوقتي');
      }
    } finally {
      service.close();
    }
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
    // The ported seek bar renders the live position stream, so the
    // drag-anywhere scrub seeks live (throttled) instead of drawing a
    // preview value of its own.
    final now = DateTime.now();
    if (_lastLiveSeek == null ||
        now.difference(_lastLiveSeek!) > const Duration(milliseconds: 150)) {
      _lastLiveSeek = now;
      _player.seek(_scrubPosition);
    }
  }

  DateTime? _lastLiveSeek;

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
  Widget build(BuildContext context) {
    final siblings = widget.siblings;
    final hasPrev = siblings != null && _index > 0;
    final hasNext = siblings != null && _index < siblings.length - 1;
    final multiEpisode = siblings != null && siblings.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              // Zoomed/panned exactly as upstream: translate then scale.
              child: Transform.translate(
                offset: _zoomPan,
                child: Transform.scale(
                  scale: _zoom,
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    fit: kPlayerFits[_fitIndex].$1,
                  ),
                ),
              ),
            ),
          if (!_locked) _gestureLayer(),
          // Literal Zangetsu controls overlay (lib/player/), mounted exactly
          // as upstream's player_screen mounts it: only when unlocked, under
          // AnimatedOpacity + IgnorePointer gated on controls visibility.
          if (!_locked)
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: Duration(
                milliseconds: _controlsVisible ? 160 : 240,
              ),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: PlayerControlsOverlay(
                  player: MediaKitPlayerSurface(_player),
                  episodeNumber: _index + 1,
                  episodeTitle: _title,
                  multiEpisode: multiEpisode,
                  hasNext: hasNext,
                  hasQualityChoices: _qualities.length > 1,
                  activeQualityLabel: _currentQuality,
                  onTogglePlay: () {
                    _player.playOrPause();
                    _scheduleHide();
                  },
                  onSeek: (pos) {
                    _player.seek(pos);
                    _scheduleHide();
                  },
                  onNext: hasNext ? () => _goToSibling(1) : null,
                  onPrev: hasPrev ? () => _goToSibling(-1) : null,
                  showTitle: widget.playlistName,
                  duration: _player.state.duration,
                  onDurationChanged: (_) {},
                  onInteract: _bumpControls,
                  onBack: () => Navigator.of(context).pop(),
                  onSpeed: _cycleSpeed,
                  onQuality: _qualities.length > 1 ? _openQualitySheet : null,
                  onLock: _toggleLock,
                  // ZMIX is landscape-locked (see initState): the
                  // portrait/landscape flip does not apply, so upstream's
                  // own null-skip drops the rotate button.
                  onRotate: null,
                  portraitMode: false,
                  barConfig: PlayerControlsConfig.defaults,
                  onZoom: _cycleFit,
                  zoomLabel: kPlayerFits[_fitIndex].$2,
                  showQuality: true,
                  visible: _controlsVisible,
                ),
              ),
            ),
          // ZMIX-specific extras with no upstream counterpart (player_hud.dart).
          if (_seekDelta != 0 && !_locked)
            SeekIndicator(delta: _seekDelta, forward: _seekForward),
          if (_hudVisible && !_locked)
            PlayerHud(isBrightness: _hudIsBrightness, value: _hudValue),
          if (_boosting && !_locked) const BoostBadge(),
          if (_locked) LockOverlay(onUnlock: _toggleLock),
          if (_error != null && !_locked)
            PlayerErrorPanel(
              errorText: _error!,
              onBack: () => Navigator.of(context).pop(),
              onRetry: _retry,
            ),
          ],
        ),
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
