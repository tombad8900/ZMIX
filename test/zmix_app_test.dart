import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/models.dart';

void main() {
  test('library models round-trip through JSON', () {
    final playlist = LibraryPlaylist(
      id: 'PLx',
      name: 'تجربة',
      url: 'https://www.youtube.com/playlist?list=PLx',
      author: 'قناة',
      thumbUrl: 'https://img.youtube.com/vi/abc/hqdefault.jpg',
      videos: [
        LibraryVideo(
          id: 'abc',
          title: 'فيديو أول',
          thumbUrl: 'https://img.youtube.com/vi/abc/hqdefault.jpg',
          durationSeconds: 754,
        ),
      ],
      addedAt: DateTime(2026, 11, 25),
    );
    final back = LibraryPlaylist.fromJson(playlist.toJson());
    expect(back.id, 'PLx');
    expect(back.name, 'تجربة');
    expect(back.videos.single.durationLabel, '12:34');
  });

  test('history entry round-trips through JSON', () {
    final entry = HistoryEntry(
      videoId: 'abc',
      title: 'فيديو',
      thumbUrl: '',
      playlistName: 'قائمة',
      playedAt: DateTime(2026, 11, 25, 12),
    );
    final back = HistoryEntry.fromJson(entry.toJson());
    expect(back.videoId, 'abc');
    expect(back.playlistName, 'قائمة');
  });
}
