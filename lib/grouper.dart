import 'models.dart';

/// Series/season/episode grouping for playlist videos, based ONLY on clear
/// markers in the user's own titles. Nothing is invented: a video whose
/// title carries no explicit episode/part marker stays ungrouped, and the
/// series name is the user's own title text, trimmed - never a fetched or
/// guessed name.
class EpisodeInfo {
  EpisodeInfo({
    required this.seriesKey,
    required this.seriesTitle,
    required this.number,
    this.season,
    this.kind = EpisodeKind.episode,
  });

  /// Normalized grouping key (case/diacritic-insensitive).
  final String seriesKey;

  /// Display name taken from the user's own title text.
  final String seriesTitle;
  final int number;
  final int? season;
  final EpisodeKind kind;
}

enum EpisodeKind { episode, part }

class SeriesGroup {
  SeriesGroup({required this.title});

  final String title;

  /// Null season = the titles carried no season marker.
  final Map<int?, List<LibraryVideo>> seasons = {};

  int get totalEpisodes =>
      seasons.values.fold(0, (sum, list) => sum + list.length);

  List<LibraryVideo> get episodes => [
        for (final season in sortedSeasons) ...seasons[season]!,
      ];

  List<int?> get sortedSeasons {
    final keys = seasons.keys.toList()
      ..sort((a, b) => (a ?? 0).compareTo(b ?? 0));
    return keys;
  }
}

class GroupedPlaylist {
  GroupedPlaylist({required this.series, required this.ungrouped});

  /// Groups with at least two members, sorted by title.
  final List<SeriesGroup> series;

  /// Everything else, in original playlist order.
  final List<LibraryVideo> ungrouped;
}

/// Converts Arabic-Indic digits to Latin so 'الحلقة ٥' matches.
String _latinDigits(String s) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in s.codeUnits) {
    final c = String.fromCharCode(ch);
    final i = eastern.indexOf(c);
    buf.write(i >= 0 ? '$i' : c);
  }
  return buf.toString();
}

/// Normalizes for grouping keys only (display keeps the original).
String _normalize(String s) {
  var out = _latinDigits(s).toLowerCase();
  out = out
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[\u064B-\u0652]'), '') // harakat
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return out;
}

class _Pattern {
  _Pattern(this.regex, this.hasSeason, this.kind);
  final RegExp regex;
  final bool hasSeason;
  final EpisodeKind kind;
}

final List<_Pattern> _patterns = [
  _Pattern(RegExp(r'[Ss](\d{1,2})\s*[Ee](\d{1,3})'), true, EpisodeKind.episode),
  _Pattern(RegExp(r'[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,3})'), true,
      EpisodeKind.episode),
  _Pattern(RegExp(r'موسم\s*(\d{1,2})\s*[-–|]?\s*الحلقة\s*(\d{1,4})'), true,
      EpisodeKind.episode),
  _Pattern(RegExp(r'\b[Ee]pisode\s*(\d{1,4})\b'), false, EpisodeKind.episode),
  _Pattern(RegExp(r'\b[Ee]p\.?\s*(\d{1,4})\b'), false, EpisodeKind.episode),
  _Pattern(RegExp(r'الحلقة\s*(\d{1,4})\b'), false, EpisodeKind.episode),
  _Pattern(RegExp(r'\b[Pp]art\s*(\d{1,3})\b'), false, EpisodeKind.part),
  _Pattern(RegExp(r'الجزء\s*(\d{1,3})\b'), false, EpisodeKind.part),
];

/// Returns episode info when [title] carries ONE clear episode/part marker,
/// else null. Ambiguous titles (multiple different markers, no usable series
/// prefix) are rejected rather than guessed.
EpisodeInfo? classifyTitle(String title) {
  final t = _latinDigits(title);
  _Pattern? matched;
  RegExpMatch? match;
  for (final p in _patterns) {
    final m = p.regex.firstMatch(t);
    if (m == null) continue;
    // A second, different marker makes the title ambiguous: skip it.
    final second = p.regex.allMatches(t).length > 1;
    if (second) return null;
    matched = p;
    match = m;
    break;
  }
  if (matched == null || match == null) return null;
  // An episode marker AND a part marker in one title ("الحلقة 3 الجزء 1") is
  // ambiguous: which number orders it is a guess, so it stays ungrouped.
  for (final p in _patterns) {
    if (p.kind != matched.kind && p.regex.hasMatch(t)) return null;
  }

  final prefix = t.substring(0, match.start);
  final seriesTitle = prefix
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[-–—|:،\(\)\[\]. ]+$'), '')
      .trim();
  if (seriesTitle.length < 2) return null; // no usable series name

  final int? season =
      matched.hasSeason ? int.tryParse(match.group(1)!) : null;
  final int? number =
      int.tryParse(match.group(matched.hasSeason ? 2 : 1)!);
  if (number == null) return null;

  return EpisodeInfo(
    seriesKey: _normalize(seriesTitle),
    seriesTitle: seriesTitle,
    number: number,
    season: season,
    kind: matched.kind,
  );
}

/// Groups a playlist's videos into clear series and an ungrouped remainder.
/// Original order is preserved inside episodes-of-same-number and ungrouped.
GroupedPlaylist groupPlaylist(List<LibraryVideo> videos) {
  final infos = videos.map((v) => classifyTitle(v.title)).toList();
  final byKey = <String, _GroupBuilder>{};
  for (var i = 0; i < videos.length; i++) {
    final info = infos[i];
    if (info == null) continue;
    byKey
        .putIfAbsent(info.seriesKey, () => _GroupBuilder(info.seriesTitle))
        .add(i, info);
  }
  final inGroup = <int>{};
  final groups = <SeriesGroup>[];
  for (final b in byKey.values) {
    if (b.count < 2) continue; // a lone episode is not a group
    groups.add(b.build(videos, infos, inGroup));
  }
  groups.sort((a, b) => a.title.compareTo(b.title));
  final ungrouped = [
    for (var i = 0; i < videos.length; i++)
      if (!inGroup.contains(i)) videos[i],
  ];
  return GroupedPlaylist(series: groups, ungrouped: ungrouped);
}

class _GroupBuilder {
  _GroupBuilder(this.title);
  final String title;
  final List<int> indices = [];
  final List<int?> seasons = [];
  int get count => indices.length;

  void add(int index, EpisodeInfo info) {
    indices.add(index);
    seasons.add(info.season);
  }

  SeriesGroup build(
      List<LibraryVideo> videos, List<EpisodeInfo?> infos, Set<int> inGroup) {
    final g = SeriesGroup(title: title);
    final bySeason = <int?, List<int>>{};
    for (final i in indices) {
      inGroup.add(i);
      bySeason.putIfAbsent(seasons[indices.indexOf(i)], () => []).add(i);
    }
    bySeason.forEach((season, idxs) {
      // Ties (duplicate episode numbers) keep playlist order: List.sort is
      // not guaranteed stable, so break them on the original index.
      idxs.sort((a, b) {
        final c = (infos[a]?.number ?? 0).compareTo(infos[b]?.number ?? 0);
        return c != 0 ? c : a.compareTo(b);
      });
      g.seasons[season] = [for (final i in idxs) videos[i]];
    });
    return g;
  }
}
