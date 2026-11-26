import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/player_queue.dart';

// Exercises the exact helper PlayerPage's _loadQualities/_loadCaptions use,
// with a controllable fetch and a mutable "current id", to model an episode
// switch while a request is in flight. PlayerPage itself cannot be pumped in
// the VM (native Player), so this covers the decision, not the setState.
void main() {
  test('returns the result when the same video is still playing', () async {
    final r = await fetchIfStillCurrent<int>(
      requestedId: 'a', currentId: () => 'a', isMounted: () => true,
      fetch: () async => 7);
    expect(r, 7);
  });

  test('drops the result when the episode changed during the fetch', () async {
    String? current = 'a';
    final gate = Completer<int>();
    final f = fetchIfStillCurrent<int>(
      requestedId: 'a', currentId: () => current, isMounted: () => true,
      fetch: () => gate.future);
    current = 'b'; // user hit next while loading
    gate.complete(1);
    expect(await f, isNull);
  });

  test('currentId is read after the await, not before', () async {
    String? current = 'a';
    final r = await fetchIfStillCurrent<int>(
      requestedId: 'a', currentId: () => current, isMounted: () => true,
      fetch: () async { current = 'b'; return 1; });
    expect(r, isNull);
  });

  test('drops when unmounted', () async {
    expect(await fetchIfStillCurrent<int>(
      requestedId: 'a', currentId: () => 'a', isMounted: () => false,
      fetch: () async => 1), isNull);
  });

  test('a slow old request cannot overwrite a newer one', () async {
    String? current = 'a';
    final slowA = Completer<String>();
    final fa = fetchIfStillCurrent<String>(
      requestedId: 'a', currentId: () => current, isMounted: () => true,
      fetch: () => slowA.future);
    current = 'b';
    final fb = fetchIfStillCurrent<String>(
      requestedId: 'b', currentId: () => current, isMounted: () => true,
      fetch: () async => 'B');
    expect(await fb, 'B');
    slowA.complete('A');
    expect(await fa, isNull);
  });

  test('fetch errors propagate to the caller (page keeps its catch)', () async {
    expect(fetchIfStillCurrent<int>(
      requestedId: 'a', currentId: () => 'a', isMounted: () => true,
      fetch: () async => throw StateError('x')), throwsStateError);
  });
}
