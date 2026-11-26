import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/grouper.dart';

void main() {
  test('episode and part markers in one title are ambiguous (null)', () {
    expect(classifyTitle('مسلسل الضي الحلقة ٣ الجزء ١'), isNull);
    expect(classifyTitle('Show X Episode 3 Part 1'), isNull);
  });
  test('season+episode in one title is still one clear marker', () {
    final i = classifyTitle('مسلسل الضي موسم 2 الحلقة 5');
    expect(i?.season, 2);
    expect(i?.number, 5);
  });
  test('a plain single marker still classifies', () {
    expect(classifyTitle('مسلسل الضي الحلقة 7')?.number, 7);
    expect(classifyTitle('Show X Part 2')?.kind, EpisodeKind.part);
  });
}
