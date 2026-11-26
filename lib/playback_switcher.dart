/// Quality-switch failure handling for the player.
///
/// Pure Dart, no plugin imports: the full open/error/retry/rollback state
/// logic is unit-testable in the VM with failure injection (a real media_kit
/// Player needs native libmpv and cannot exist there; PlayerPage wires this
/// controller to the live player's streams).
///
/// Device evidence behind the design (0.3.4, user screenshots 2026-11-25):
/// any failed quality open left a dead player whose only recovery was
/// exiting, and the error panel printed the raw signed stream URL (which
/// carries the user's IP) on screen.
///
/// Confirmation discipline (review requirement): a candidate stream is
/// NEVER treated as "playing" on metadata alone. A duration value can be
/// container metadata or a stale event from the previous stream. The last
/// confirmed stream is replaced only when ALL of the following hold for the
/// CURRENT open generation:
///   1. mpv's playlist reports the candidate's own URI as its current entry
///      ([onMediaLoaded] — a stale event carries the old URI and is
///      rejected), and
///   2. position advances between two distinct progress events while the
///      player reports playing ([onPlaybackProgress] — a failed open never
///      advances position, and a single stale burst cannot pass).
/// Until then the previous last-good stream is preserved untouched.
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

/// The error belongs to a superseded stream (proved by the failing URL in
/// the error text): leave the current selection untouched.
class IgnoreStaleError implements SwitchDecision {
  const IgnoreStaleError();
}

/// Identity of a stream URL: itag + id + mime when ALL of itag and id are
/// present (percent-encoding is normalized by the query parser), else the
/// whole string, which can only match itself. Two URLs of the same
/// itag/id/mime (a re-extraction with a new signature or expiry) share a
/// key on purpose: if they collide, an error is attributed to the CURRENT
/// open and handled as before, so a collision can never hide a current
/// failure. It can only fail to ignore a stale one.
String streamKey(String url) {
  final u = Uri.tryParse(url);
  final q = u?.queryParameters ?? const <String, String>{};
  final itag = q['itag'];
  final id = q['id'];
  if (itag == null || itag.isEmpty || id == null || id.isEmpty) return url;
  return '$itag|$id|${q['mime'] ?? ''}';
}

/// Stream keys of every http(s) URL embedded in a player error text.
/// mpv prints the failing resource ("Failed to open <url>", "Can not open
/// external file <url>"), so the text itself names the stream it is about.
List<String> streamKeysInText(String text) => [
      for (final m in RegExp(r'https?://[^\s\x27"]+').allMatches(text))
        streamKey(m.group(0)!.replaceAll(RegExp(r'[.,;)]+$'), '')),
    ];

/// Tracks the last stream confirmed playing and decides recovery on error.
class ZmixPlaybackSwitcher {
  // Last-good: replaced ONLY by confirmed playback evidence.
  String? _goodUrl;
  String? _goodQuality;
  bool _goodNeedsAudio = false;

  // Current open generation. Every open attempt invalidates confirmation
  // state gathered under the previous one.
  int _generation = 0;

  // Pending candidate of the current generation.
  String? _pendingUrl;
  String? _pendingQuality;
  bool _pendingNeedsAudio = false;

  // Evidence flags for the current generation.
  bool _mediaLoaded = false;
  Duration? _lastPosition;
  bool _confirmed = false;

  /// The URL a recovery attempt is currently trying, so a second failure on
  /// THAT stream falls through to the error panel instead of looping.
  String? _recoveryUrl;

  // Stream keys of the current open (video URL and external audio URL) and
  // of every superseded open. Used to attribute an error to a stream by the
  // URL in its text, never by timing.
  Set<String> _currentKeys = {};
  final Set<String> _supersededKeys = {};

  /// The current open generation id (for tests and wiring asserts).
  int get generation => _generation;

  /// Whether the pending candidate of the current generation is confirmed.
  bool get confirmed => _confirmed;

  /// A new open attempt begins; returns its generation id. Confirmation
  /// evidence is accepted only for the latest generation, so stale events
  /// from the previous stream cannot confirm the new candidate.
  int beginOpen(String url,
      {String? quality, bool needsAudio = false, String? audioUrl}) {
    _supersededKeys.addAll(_currentKeys);
    _currentKeys = {streamKey(url), if (audioUrl != null) streamKey(audioUrl)};
    _supersededKeys.removeAll(_currentKeys);
    _generation++;
    _pendingUrl = url;
    _pendingQuality = quality;
    _pendingNeedsAudio = needsAudio;
    _mediaLoaded = false;
    _lastPosition = null;
    _confirmed = false;
    return _generation;
  }

  /// mpv's playlist reports [uri] as its current entry. Counts only when it
  /// matches the pending candidate of the current generation; a stale
  /// playlist event from the previous stream carries a different URI and is
  /// ignored. Wrong generation: ignored.
  void onMediaLoaded(String? uri, {required int generation}) {
    if (generation != _generation || uri == null) return;
    if (uri == _pendingUrl) _mediaLoaded = true;
  }

  /// Playback progress evidence. Confirms the candidate as the new
  /// last-good only when the media is loaded (own URI seen), the player is
  /// playing, and position strictly advanced versus the previous accepted
  /// event of this generation — one stale burst can set the baseline but
  /// never confirm by itself. Returns true when this call confirmed.
  bool onPlaybackProgress({
    required int generation,
    required Duration position,
    required bool playing,
  }) {
    if (generation != _generation || !_mediaLoaded || !playing) {
      return false;
    }
    final last = _lastPosition;
    if (last == null) {
      _lastPosition = position;
      return false;
    }
    if (position <= last) return false;
    _lastPosition = position;
    _goodUrl = _pendingUrl;
    _goodQuality = _pendingQuality;
    _goodNeedsAudio = _pendingNeedsAudio;
    _confirmed = true;
    if (_recoveryUrl == _goodUrl) _recoveryUrl = null;
    return true;
  }

  /// Same evidence rules as [onPlaybackProgress], but true only on the call
  /// that moves this generation from unconfirmed to confirmed. For logging:
  /// [onPlaybackProgress] returns true on every advancing tick, so using it
  /// directly as a "first play" signal logs once per position event.
  bool onFirstPlaybackConfirmation({
    required int generation,
    required Duration position,
    required bool playing,
  }) {
    final was = _confirmed;
    final now = onPlaybackProgress(
        generation: generation, position: position, playing: playing);
    return now && !was;
  }

  /// Called with the raw player error text. media_kit's error stream has no
  /// media identity, so attribution comes from the URL mpv embeds in the
  /// text: when it names only streams of SUPERSEDED opens (and none of the
  /// current open), the error is stale and must not cancel or roll back the
  /// current selection. Text with no URL, or naming the current open, is
  /// handled exactly as before, so a genuine current failure is never hidden.
  SwitchDecision onPlayerError(String text, String currentUrl) {
    final keys = streamKeysInText(text);
    if (keys.isNotEmpty &&
        keys.every((k) => !_currentKeys.contains(k)) &&
        keys.any(_supersededKeys.contains)) {
      return const IgnoreStaleError();
    }
    return onError(currentUrl);
  }

  /// Called when the live player reports an error for [failedUrl].
  /// Rolls back to the last confirmed stream when there is a different one;
  /// otherwise (initial open failed, or the rollback itself failed) shows
  /// the sanitized error panel. Never loops a rollback, and a failed
  /// candidate has never overwritten the last-good target (confirmation is
  /// evidence-gated), so the rollback target is always the original.
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
