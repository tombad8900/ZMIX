import 'diagnostics.dart';

/// Sets the player's audio source: a URL string attaches that external track,
/// null selects the stream's own audio (AudioTrack.auto()).
typedef AudioSourceSetter = Future<void> Function(String? externalUrl);

/// Test seam extracted from PlayerPage._reapplyAudio with NO behavior change.
///
/// - Video-only stream with a known audio URL: attach it. A failure is caught
///   and logged (critical line), then execution continues: no rollback, no
///   notice, the caller cannot tell.
/// - Otherwise: select the built-in audio. A failure here is NOT caught and
///   propagates to the caller (same as before the extraction).
Future<void> reapplyExternalAudio({
  required bool currentNeedsAudio,
  required String? audioUrl,
  required AudioSourceSetter setAudio,
  required String? attemptId,
  Diag? diag,
}) async {
  final d = diag ?? Diag.I;
  final audio = audioUrl;
  if (currentNeedsAudio && audio != null) {
    try {
      await setAudio(audio);
      d.outcome('إرفاق مسار الصوت الخارجي',
          stage: 'audio',
          detail: 'host=${Diag.hostOf(audio)}',
          attemptId: attemptId,
          critical: true);
    } catch (e) {
      d.outcome('فشل إرفاق مسار الصوت',
          stage: 'audio', ok: false, detail: '$e', attemptId: attemptId);
    }
  } else {
    await setAudio(null);
  }
}
