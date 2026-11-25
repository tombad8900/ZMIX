import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/grouper.dart';
import 'package:zmix/models.dart';

LibraryVideo v(String id, String title) =>
    LibraryVideo(id: id, title: title, thumbUrl: '', durationSeconds: 100);

void main() {
  test('clear Arabic episode titles group, ordered by episode number', () {
    final g = groupPlaylist([
      v('a1', 'مسلسل الطيبين الحلقة ٣'),
      v('a2', 'مسلسل الطيبين الحلقة ١'),
      v('a3', 'فيلم غرام الشيوخ - Gharam Elsheyoukh Movie'),
    ]);
    expect(g.series.length, 1);
    expect(g.series.single.title, 'مسلسل الطيبين');
    expect(g.series.single.episodes.map((e) => e.id), ['a2', 'a1']);
    expect(g.ungrouped.map((e) => e.id), ['a3']);
  });

  test('SxxExx and Season/Episode markers carry season numbers', () {
    final g = groupPlaylist([
      v('b1', 'Breaking Bad S02E05'),
      v('b2', 'Breaking Bad S01E03'),
      v('b3', 'Breaking Bad S01E01'),
    ]);
    expect(g.series.length, 1);
    final seasons = g.series.single.seasons;
    expect(seasons[1]!.map((e) => e.id), ['b3', 'b2']);
    expect(seasons[2]!.map((e) => e.id), ['b1']);
  });

  test('films, music and marker-less titles stay ungrouped', () {
    final g = groupPlaylist([
      v('c1', 'Me at the zoo'),
      v('c2', 'PSY - GANGNAM STYLE M/V'),
      v('c3', 'أجمل حلقات ساكن قصادي هز الهلال يا سيد (حلقة رمضان)'),
    ]);
    expect(g.series, isEmpty);
    expect(g.ungrouped.length, 3);
  });

  test('a lone episode is not a group; it stays ungrouped in place', () {
    final g = groupPlaylist([
      v('d1', 'فيلم قديم'),
      v('d2', 'مسلسل وحيد الحلقة 12'),
      v('d3', 'أغنية قديمة'),
    ]);
    expect(g.series, isEmpty);
    expect(g.ungrouped.map((e) => e.id), ['d1', 'd2', 'd3']);
  });

  test('parts of a film group together as parts', () {
    final g = groupPlaylist([
      v('e1', 'فيلم الناظر الجزء ٢'),
      v('e2', 'فيلم الناظر الجزء ١'),
    ]);
    expect(g.series.length, 1);
    expect(g.series.single.episodes.map((e) => e.id), ['e2', 'e1']);
  });

  test('ambiguous title with two markers is rejected, not guessed', () {
    final g = groupPlaylist([
      v('f1', 'مسلسل كذا الحلقة 1 الحلقة 2'),
      v('f2', 'مسلسل كذا الحلقة 3'),
    ]);
    expect(g.series, isEmpty);
    expect(g.ungrouped.length, 2);
  });

  test('repeated identical titles both stay in the group', () {
    final g = groupPlaylist([
      v('g1', 'مسلسل مكرر الحلقة 1'),
      v('g2', 'مسلسل مكرر الحلقة 1'),
      v('g3', 'مسلسل مكرر الحلقة 2'),
    ]);
    expect(g.series.length, 1);
    expect(g.series.single.totalEpisodes, 3);
  });
}
