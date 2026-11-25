import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Does a different public InnerTube client context serve more of a
/// playlist than the WEB context's default view?
/// Run with: dart run tool/diag_client.dart <playlistId>
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/diag_client.dart <playlistId>');
    exitCode = 2;
    return;
  }
  final playlistId = args.first;
  final client = http.Client();
  final url = Uri.https(
      'www.youtube.com', '/youtubei/v1/browse', {'prettyPrint': 'false'});
  const headers = {'content-type': 'application/json'};

  final contexts = <String, Map<String, dynamic>>{
    'ANDROID': {
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '19.09.37',
        'androidSdkVersion': 30,
        'hl': 'ar',
        'gl': 'EG',
      }
    },
    'IOS': {
      'client': {
        'clientName': 'IOS',
        'clientVersion': '19.09.3',
        'deviceModel': 'iPhone16,2',
        'hl': 'ar',
        'gl': 'EG',
      }
    },
    'TVHTML5': {
      'client': {'clientName': 'TVHTML5', 'clientVersion': '7.20250219.14.00'}
    },
  };

  for (final entry in contexts.entries) {
    final name = entry.key;
    try {
      final ids = <String>{};
      Map<String, dynamic> body = {
        'context': entry.value,
        'browseId': 'VL$playlistId'
      };
      var pages = 0;
      while (pages < 12) {
        pages++;
        final resp = await client
            .post(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) {
          stdout.writeln('$name page$pages: HTTP ${resp.statusCode}');
          break;
        }
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        // collect any videoRenderer-style ids too
        final idsThisPage = <String>[];
        collectIds(decoded, idsThisPage);
        var newOnes = 0;
        for (final id in idsThisPage) {
          if (ids.add(id)) newOnes++;
        }
        final tokens = <String>[];
        findTokens(decoded, tokens);
        if (tokens.isEmpty || newOnes == 0) {
          stdout.writeln(
              '$name page$pages: idsThisPage=${idsThisPage.length} new=$newOnes unique=${ids.length} - END (tokens=${tokens.length})');
          break;
        }
        body = {'context': entry.value, 'continuation': tokens.first};
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      stdout.writeln('=== $name: pages=$pages uniqueVideoIds=${ids.length}');
    } catch (e) {
      stdout.writeln('$name: ERROR $e');
    }
  }
  client.close();
}

void collectIds(dynamic node, List<String> out) {
  if (node is Map<String, dynamic>) {
    node.forEach((k, v) {
      if ((k == 'contentId' || k == 'videoId') &&
          v is String &&
          v.length == 11) {
        out.add(v);
      }
      collectIds(v, out);
    });
  } else if (node is List<dynamic>) {
    for (final item in node) {
      collectIds(item, out);
    }
  }
}

void findTokens(dynamic node, List<String> hits) {
  if (node is Map<String, dynamic>) {
    node.forEach((k, v) {
      if (k == 'continuationCommand' &&
          v is Map<String, dynamic> &&
          v['token'] is String) {
        hits.add(v['token'] as String);
      }
      findTokens(v, hits);
    });
  } else if (node is List<dynamic>) {
    for (final item in node) {
      findTokens(item, hits);
    }
  }
}
