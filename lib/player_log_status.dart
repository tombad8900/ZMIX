/// INSTRUMENTATION ONLY. This does not fix bug #6 (YouTube non-muxed
/// streams failing to open). It only turns the raw mpv/ffmpeg error lines
/// into a tiny closed vocabulary (stage + optional HTTP status code) so a
/// later diagnostic report can say WHICH failure happened without ever
/// containing a URL, host, IP, id, header or other free text.
///
/// mpv status availability: with the default log level (error) mpv emits
/// ffmpeg lines such as "HTTP error 403 Forbidden" through Player.stream.log
/// when the demuxer sees them. Whether a real YouTube failure produces such a
/// line is NOT known; this class reports "none" in that case, which is itself
/// information.
class PlayerLogStatus {
  /// Closed set: open_failed, external_file_failed, http_status, tcp_error,
  /// other_error.
  final String kind;

  /// HTTP status code when the line carried one ("HTTP error 403"), else null.
  final int? httpStatus;

  const PlayerLogStatus(this.kind, [this.httpStatus]);

  /// Safe, fixed-format text. Never includes input text.
  String get label => httpStatus == null ? kind : '$kind:$httpStatus';

  @override
  bool operator ==(Object o) =>
      o is PlayerLogStatus && o.kind == kind && o.httpStatus == httpStatus;

  @override
  int get hashCode => Object.hash(kind, httpStatus);

  /// Returns null for non-error levels. For error lines returns a status
  /// built ONLY from fixed words and a 3-digit code found in the line.
  static PlayerLogStatus? classify(String prefix, String level, String text) {
    if (level != 'error' && level != 'fatal') return null;
    final t = text.toLowerCase();
    final m = RegExp(r'http error (\d{3})').firstMatch(t);
    if (m != null) return PlayerLogStatus('http_status', int.parse(m.group(1)!));
    if (t.contains('can not open external file')) {
      return const PlayerLogStatus('external_file_failed');
    }
    if (t.contains('failed to open')) return const PlayerLogStatus('open_failed');
    if (t.startsWith('tcp:') || prefix == 'tcp') {
      return const PlayerLogStatus('tcp_error');
    }
    return const PlayerLogStatus('other_error');
  }
}
