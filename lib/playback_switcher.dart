/// Quality-switch failure handling for the player.
///
/// Pure Dart, no plugin imports: the full open/error/retry/rollback state
/// logic is unit-testable in the VM with failure injection (a real media_kit
/// Player needs native libmpv and cannot exist there; PlayerPage wires this
/// controller to the live player's error stream).
///
/// Device evidence behind the design (0.3.4, user screenshots 2026-11-25):
/// any failed quality open left a dead player whose only recovery was
/// exiting, and the error panel printed the raw signed stream URL (which
/// carries the user's IP) on screen.
library;

/// What the player should do after a failed open.
sealed class SwitchDecision {}

/// Re-open the last stream that actually played.
class RollbackToLastGood implements SwitchDecision {
  const RollbackToLastGood(this.url, this.quality, this.needsAudio);
  final String url;
  final String? quality;
  final bool needsAudio;
}

/// Show the error panel with [message] (already sanitized).
class ShowError implements SwitchDecision {
  const ShowError(this.message);
  final String message;
}

/// Tracks the last stream confirmed playing and decides recovery on error.
class ZmixPlaybackSwitcher {
  String? _goodUrl;
  String? _goodQuality;
  bool _goodNeedsAudio = false;

  /// The URL a recovery attempt is currently trying, so a second failure on
  /// THAT stream falls through to the error panel instead of looping.
  String? _recoveryUrl;

  /// Called when a stream is confirmed playing (first duration > 0 after
  /// open). Becomes the rollback target for later failures.
  void markPlaying(String url, {String? quality, bool needsAudio = false}) {
    _goodUrl = url;
    _goodQuality = quality;
    _goodNeedsAudio = needsAudio;
    if (_recoveryUrl == url) _recoveryUrl = null;
  }

  /// Called when the live player reports an error for [failedUrl].
  /// Rolls back to the last confirmed stream when there is a different one;
  /// otherwise (initial open failed, or the rollback itself failed) shows
  /// the sanitized error panel. Never loops a rollback.
  SwitchDecision onError(String failedUrl) {
    final good = _goodUrl;
    if (good != null && failedUrl != good && _recoveryUrl == null) {
      _recoveryUrl = good;
      return RollbackToLastGood(good, _goodQuality, _goodNeedsAudio);
    }
    _recoveryUrl = null;
    return const ShowError(kSafePlaybackError);
  }
}

/// User-facing playback error text. Raw transport exceptions are never
/// shown: mpv's message embeds the signed stream URL, which carries the
/// user's IP address and session tokens.
const String kSafePlaybackError =
    'مش قادرين نشغّل الجودة دي دلوقتي. جرّب جودة تانية أو ارجع للمشغّل من جديد.';
