/// One-at-a-time gate for starting playback. Held from the tap until the
/// player route has been pushed (NOT for the player's whole lifetime), so
/// extra taps during the slow stream resolution cannot each push their own
/// player. Always released via [leave] in a finally block.
class LaunchGate {
  bool _busy = false;
  int ignored = 0;

  bool get busy => _busy;

  /// True when the caller may proceed; false (and counts) when a launch is
  /// already in flight.
  bool tryEnter() {
    if (_busy) {
      ignored++;
      return false;
    }
    _busy = true;
    return true;
  }

  void leave() => _busy = false;

  /// Runs [body] under the gate. Returns false (body NOT run) when a launch
  /// is already in flight. [body] gets an idempotent `release` it may call
  /// early (route pushed); whatever happens (return, throw), the hold is
  /// released exactly once in finally, and a stale release from an older
  /// launch can never free a newer launch's hold.
  Future<bool> run(
      Future<void> Function(void Function() release) body) async {
    if (!tryEnter()) return false;
    var held = true;
    void release() {
      if (held) {
        held = false;
        leave();
      }
    }

    try {
      await body(release);
    } finally {
      release();
    }
    return true;
  }
}
