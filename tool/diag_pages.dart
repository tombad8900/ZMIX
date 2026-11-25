import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Diagnostic: per-page breakdown of what YouTube's browse endpoint serves
/// for a playlist - how many lockupViewModel entries, which contentTypes,
/// how many our parser accepts, duplicates, and the continuation chain.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/diag_pages.dart <playlistId>');
    exitCode = 2;
    return;
  }
  final playlistId = args.first;
  const extraParams = bool.hasEnvironment('PARAMS') ? String.fromEnvironment('PARAMS') : 'wgYCCAA=';
  final client = http.Client();
  final url = Uri.https(
      'www.youtube.com', '/youtubei/v1/browse', {'prettyPrint': 'false'});
  const headers = {
    'content-type': 'application/json',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  };
  const context = {
    'client': {'clientName': 'WEB', 'clientVersion': '2.20250219.01.00'}
  };

  final seenIds = <String>{};
  var dupesAcrossPages = 0;
  Map<String, dynamic> body = {
    'context': context,
    'browseId': 'VL$playlistId'
  };
  var page = 0;
  while (page < 30) {
    page++;
    final resp = await client
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    if (page == 1) stdout.writeln('params in use: $extraParams');
    stdout.writeln('--- page $page: HTTP ${resp.statusCode}, '
        '${resp.bodyBytes.length} bytes');
    if (resp.statusCode != 200) break;
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));

    final lockups = <Map<String, dynamic>>[];
    findAll(decoded, 'lockupViewModel', lockups);
    final typeCounts = <String, int>{};
    var accepted = 0;
    var dupesThisPage = 0;
    var noId = 0;
    var noTitle = 0;
    for (final l in lockups) {
      final type = (l['contentType'] as String?) ?? '?';
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      if (type != 'LOCKUP_CONTENT_TYPE_VIDEO') continue;
      final id = l['contentId'] as String?;
      if (id == null || id.length != 11) {
        noId++;
        continue;
      }
      if (!seenIds.add(id)) {
        dupesThisPage++;
        dupesAcrossPages++;
        continue;
      }
      final title = l['metadata']?['lockupMetadataViewModel']?['title']
          ?['content'] as String?;
      if (title == null || title.isEmpty) {
        noTitle++;
        continue;
      }
      accepted++;
    }
    stdout.writeln('    lockups=${lockups.length} types=$typeCounts '
        'accepted=$accepted dupesThisPage=$dupesThisPage noId=$noId noTitle=$noTitle '
        'totalAccepted=${seenIds.length}');

    final tokens = <String>[];
    findContinuationTokens(decoded, tokens);
    stdout.writeln(
        '    continuationTokens=${tokens.length} ${tokens.map((t) => '${t.substring(0, t.length < 20 ? t.length : 20)}...len${t.length}').toList()}');
    if (tokens.isEmpty) {
      stdout.writeln('    NO CONTINUATION - genuine end');
      break;
    }
    body = {'context': context, 'continuation': tokens.first};
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  stdout.writeln('=== pages=$page uniqueVideos=${seenIds.length} '
      'dupesAcrossPages=$dupesAcrossPages');
  client.close();
}

void findAll(dynamic node, String key, List<Map<String, dynamic>> hits) {
  if (node is Map<String, dynamic>) {
    node.forEach((k, v) {
      if (k == key && v is Map<String, dynamic>) hits.add(v);
      findAll(v, key, hits);
    });
  } else if (node is List<dynamic>) {
    for (final item in node) {
      findAll(item, key, hits);
    }
  }
}

void findContinuationTokens(dynamic node, List<String> hits) {
  if (node is Map<String, dynamic>) {
    node.forEach((k, v) {
      if (k == 'continuationCommand' &&
          v is Map<String, dynamic> &&
          v['token'] is String) {
        hits.add(v['token'] as String);
      }
      findContinuationTokens(v, hits);
    });
  } else if (node is List<dynamic>) {
    for (final item in node) {
      findContinuationTokens(item, hits);
    }
  }
}
