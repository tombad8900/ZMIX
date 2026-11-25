/// YouTube captions -> SRT for media_kit's external-subtitle loader.
///
/// Pure Dart, no plugin imports, so the conversion is unit-testable in the
/// VM (a real media_kit Player needs native libmpv and cannot exist there).
///
/// Data comes from youtube_explode's ClosedCaptionClient: each caption has
/// full cue text (YouTube's timedtext already resolves the rolling
/// word-by-word accumulation into `parts`), a start offset and a duration.
/// Verified against real auto-generated Arabic tracks from the user's
/// playlists (tool/caption_probe.dart, 2026-11-25).
library;

/// One timed line of dialogue.
typedef SrtCue = ({String text, Duration start, Duration end});

/// Renders cues as an SRT document.
///
/// - empty/whitespace cues are dropped;
/// - a cue whose end is not after its start gets a 2s default window;
/// - a cue overlapping the next one is clamped to the next cue's start, so
///   the renderer never stacks two lines (auto-generated tracks occasionally
///   carry long "[موسيقى]" windows that run into the next line).
String captionsToSrt(Iterable<SrtCue> cues) {
  final clean = <SrtCue>[
    for (final c in cues)
      if (c.text.trim().isNotEmpty) c,
  ];
  final out = StringBuffer();
  for (var i = 0; i < clean.length; i++) {
    var cue = clean[i];
    final start = cue.start.isNegative ? Duration.zero : cue.start;
    var end = cue.end;
    if (end <= start) {
      end = start + const Duration(seconds: 2);
    }
    if (i + 1 < clean.length && end > clean[i + 1].start) {
      end = clean[i + 1].start;
    }
    out
      ..writeln(i + 1)
      ..writeln('${_stamp(start)} --> ${_stamp(end)}')
      ..writeln(cue.text.trim())
      ..writeln();
  }
  return out.toString();
}

/// 0:03:07.500 -> "00:03:07,500" (SRT wants comma milliseconds).
String _stamp(Duration d) {
  final ms = d.inMilliseconds < 0 ? 0 : d.inMilliseconds;
  final h = (ms ~/ 3600000).toString().padLeft(2, '0');
  final m = ((ms ~/ 60000) % 60).toString().padLeft(2, '0');
  final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
  final milli = (ms % 1000).toString().padLeft(3, '0');
  return '$h:$m:$s,$milli';
}
