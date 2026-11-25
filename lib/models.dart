/// Data models for the ZMIX library, with JSON (de)serialization for
/// on-device persistence. No fabricated metadata: every field comes from
/// YouTube's own data or from the user's input.
class LibraryVideo {
  LibraryVideo({
    required this.id,
    required this.title,
    required this.thumbUrl,
    this.durationSeconds,
  });

  final String id;
  final String title;
  final String thumbUrl;
  final int? durationSeconds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'thumbUrl': thumbUrl,
        'durationSeconds': durationSeconds,
      };

  factory LibraryVideo.fromJson(Map<String, dynamic> j) => LibraryVideo(
        id: j['id'] as String,
        title: j['title'] as String,
        thumbUrl: j['thumbUrl'] as String? ?? '',
        durationSeconds: j['durationSeconds'] as int?,
      );

  String get durationLabel {
    final d = durationSeconds;
    if (d == null) return '';
    final h = d ~/ 3600;
    final m = (d % 3600) ~/ 60;
    final s = d % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}

class LibraryPlaylist {
  LibraryPlaylist({
    required this.id,
    required this.name,
    required this.url,
    required this.author,
    required this.thumbUrl,
    required this.videos,
    required this.addedAt,
  });

  final String id;

  /// User-chosen nickname; defaults to the YouTube playlist title.
  String name;
  final String url;
  final String author;
  final String thumbUrl;
  final List<LibraryVideo> videos;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'author': author,
        'thumbUrl': thumbUrl,
        'videos': videos.map((v) => v.toJson()).toList(),
        'addedAt': addedAt.toIso8601String(),
      };

  factory LibraryPlaylist.fromJson(Map<String, dynamic> j) => LibraryPlaylist(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        author: j['author'] as String? ?? '',
        thumbUrl: j['thumbUrl'] as String? ?? '',
        videos: (j['videos'] as List<dynamic>? ?? [])
            .map((v) => LibraryVideo.fromJson(v as Map<String, dynamic>))
            .toList(),
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class HistoryEntry {
  HistoryEntry({
    required this.videoId,
    required this.title,
    required this.thumbUrl,
    required this.playlistName,
    required this.playedAt,
  });

  final String videoId;
  final String title;
  final String thumbUrl;
  final String playlistName;
  final DateTime playedAt;

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'thumbUrl': thumbUrl,
        'playlistName': playlistName,
        'playedAt': playedAt.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        videoId: j['videoId'] as String,
        title: j['title'] as String,
        thumbUrl: j['thumbUrl'] as String? ?? '',
        playlistName: j['playlistName'] as String? ?? '',
        playedAt: DateTime.tryParse(j['playedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
