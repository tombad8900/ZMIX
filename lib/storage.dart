import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Local JSON persistence for the library. Everything stays on the device.
class LibraryStore extends ChangeNotifier {
  LibraryStore();

  static const String _fileName = 'zmix_library.json';
  static const int _historyLimit = 300;

  final List<LibraryPlaylist> playlists = [];
  final List<HistoryEntry> history = [];

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        playlists
          ..clear()
          ..addAll((j['playlists'] as List<dynamic>? ?? [])
              .map((p) => LibraryPlaylist.fromJson(p as Map<String, dynamic>)));
        history
          ..clear()
          ..addAll((j['history'] as List<dynamic>? ?? [])
              .map((h) => HistoryEntry.fromJson(h as Map<String, dynamic>)));
      }
    } catch (_) {
      // Corrupt or unreadable store: start empty rather than crash.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'history': history.map((h) => h.toJson()).toList(),
      }));
    } catch (_) {
      // Persistence failure must not break playback.
    }
  }

  bool hasPlaylist(String id) => playlists.any((p) => p.id == id);

  Future<void> addPlaylist(LibraryPlaylist p) async {
    playlists.removeWhere((x) => x.id == p.id);
    playlists.insert(0, p);
    notifyListeners();
    await _save();
  }

  Future<void> removePlaylist(String id) async {
    playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final p = playlists.where((p) => p.id == id).firstOrNull;
    if (p == null) return;
    p.name = newName.trim().isEmpty ? p.name : newName.trim();
    notifyListeners();
    await _save();
  }

  Future<void> recordPlay({
    required String videoId,
    required String title,
    required String thumbUrl,
    required String playlistName,
  }) async {
    history.removeWhere((h) => h.videoId == videoId);
    history.insert(
      0,
      HistoryEntry(
        videoId: videoId,
        title: title,
        thumbUrl: thumbUrl,
        playlistName: playlistName,
        playedAt: DateTime.now(),
      ),
    );
    if (history.length > _historyLimit) {
      history.removeRange(_historyLimit, history.length);
    }
    notifyListeners();
    await _save();
  }

  Future<void> clearHistory() async {
    history.clear();
    notifyListeners();
    await _save();
  }

  Future<void> clearAll() async {
    playlists.clear();
    history.clear();
    notifyListeners();
    await _save();
  }
}
