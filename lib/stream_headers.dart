import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// HTTP request headers that match the YouTube API client that produced a
/// stream URL.
///
/// HYPOTHESIS, NOT A VERIFIED CAUSE: googlevideo URLs issued to a given API
/// client may be expected to be fetched with that client's user agent, while
/// mpv sends its own default. The pinned youtube_explode_dart 3.1.0 declares
/// the user agent inside each client's payload
/// (`context.client.userAgent`); this reads that declared value and never
/// invents one. Clients that declare none (e.g. androidVr) yield null.
Map<String, String>? streamHeadersFor(YoutubeApiClient client) {
  final ctx = client.payload['context'];
  if (ctx is! Map) return null;
  final c = ctx['client'];
  if (c is! Map) return null;
  final ua = c['userAgent'];
  if (ua is! String || ua.trim().isEmpty) return null;
  return {'user-agent': ua};
}

/// Headers to pass to `Media(...)` for one open. Only adaptive (video-only)
/// opens get them: the muxed path is the one known to play on the device, so
/// it is left byte-for-byte unchanged.
Map<String, String>? headersForOpen({
  required bool needsExternalAudio,
  required Map<String, String>? clientHeaders,
}) =>
    needsExternalAudio ? clientHeaders : null;
