/// EXPERIMENTAL, UNWIRED (gate: kSolverExperimentEnabled in youtube_service).
///
/// On-device YouTube JS-challenge solver for Flutter, porting the ALGORITHM
/// of TeamNewPipe/NewPipeExtractor v0.26.3 (GPL-3.0, same license as ZMIX)
/// to Dart + flutter_js (QuickJS) instead of its JVM Rhino engine:
///   extractor/src/main/java/org/schabi/newpipe/extractor/services/youtube/
///   YoutubeThrottlingParameterUtils.java, YoutubeSignatureUtils.java,
///   YoutubeJavaScriptExtractor.java, utils/jsextractor/JavaScriptExtractor
///
/// Why this and not youtube_explode's EJS path: EJS (yt-dlp solver 0.8.0)
/// parses the whole ~2.7 MB player with a bundled AST parser. Measured on
/// the EXACT engine flutter_js 0.8.7 ships on Android (QuickJS 2021-03-27,
/// fastdev-jsruntimes-quickjs:0.3.6), that parse did not finish in 110 s.
/// The NewPipe approach plain-evals the player once (measured 228 ms on the
/// same engine) and calls the extracted n-transform through the player's own
/// URL class; against the archived real player 74edf1a3 (Wayback snapshot,
/// yt-dlp/ejs committed test vectors) all three known n-challenges solved
/// to the expected values. See tool/offline_solver_probe.md.
///
/// Engine coverage gaps of QuickJS 2021-03-27 (no Object.hasOwn / .at) are
/// covered by the two-line polyfill prepended to the environment.
library;

import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/js_challenge.dart';

/// Pure-Dart builder of the JS environment the solver evaluates.
/// Everything here is engine-independent and unit-testable in the VM.
class PlayerJsEnvironment {
  PlayerJsEnvironment._();

  /// QuickJS 2021-03-27 lacks these ES2022 members; the player code and the
  /// solver helpers touch Object.hasOwn.
  static const kPolyfill = '''
if (typeof Object.hasOwn !== "function") {
  Object.hasOwn = function (o, k) { return Object.prototype.hasOwnProperty.call(o, k); };
}
if (!Array.prototype.at) {
  Array.prototype.at = function (i) {
    var n = this.length >>> 0, k = i >= 0 ? i : n + i;
    return k < 0 || k >= n ? undefined : this[k];
  };
}
''';

  /// Port of YoutubeThrottlingParameterUtils.buildHelperFunction's shims.
  static const kShims = '''
var g = {};
if (typeof globalThis.XMLHttpRequest === "undefined") {
  globalThis.XMLHttpRequest = { prototype: {} };
}
if (typeof URL === "undefined") {
  globalThis.location = {
    hash: "", host: "www.youtube.com", hostname: "www.youtube.com",
    href: "https://www.youtube.com/", origin: "https://www.youtube.com",
    password: "", pathname: "/", port: "", protocol: "https:",
    search: "", username: "",
  };
} else {
  globalThis.location = new URL("https://www.youtube.com");
}
if (typeof globalThis.document === "undefined") { globalThis.document = Object.create(null); }
if (typeof globalThis.navigator === "undefined") { globalThis.navigator = Object.create(null); }
if (typeof globalThis.self === "undefined") { globalThis.self = globalThis; }
if (typeof globalThis.window === "undefined") { globalThis.window = globalThis; }
''';

  static const _wrapperPrefix = 'var _yt_player={};(function(g){var window=this;';
  static const _wrapperSuffix = '})(_yt_player);';

  /// Port of buildHelperFunction's wrapper strip.
  static String stripWrapper(String playerCode) {
    return playerCode
        .replaceAll(_wrapperPrefix, '')
        .replaceAll(_wrapperSuffix, '');
  }

  /// Port of DEOBFUSCATION_FUNCTION_NAME_REGEXES[0]: the n-transform entry
  /// point is the function whose body contains `set("alr","yes")`.
  static final _nNamePattern =
      RegExp(r'(\w*)=function\(.*\)\{.*set\("alr","yes"\);\w&&');

  /// Array-indirection variant, ported from getDeobfuscationFunctionName:
  /// `NAME=function(...)` matched, with a second group selecting from a
  /// `var NAME = [...]` array of candidate names.
  static String? extractNFunctionName(String playerCode) {
    final m = _nNamePattern.firstMatch(playerCode);
    if (m == null) return null;
    var name = m.group(1)!;
    if (m.groupCount > 1 && m.group(2) != null) {
      final arrayNum = int.parse(m.group(2)!);
      final arrayPattern = RegExp(
          '${RegExp.escape('var ')}${RegExp.escape(name)}\\s*=\\s*\\[(.+?)][;,]');
      final am = arrayPattern.firstMatch(playerCode);
      if (am == null) return null;
      name = am.group(1)!.split(',')[arrayNum].trim();
    }
    return name;
  }

  /// Port of YoutubeThrottlingParameterUtils.buildHelperFunction's caller:
  /// the n-transform lives in the player's own URL class; invoking the first
  /// prototype method that is not constructor/set/get/clone runs it.
  static String buildNHelper(String functionName) {
    return '''
function deobfuscate_n_param(n){
  const url = $functionName("https://www.youtube.com/", "s", undefined);
  url.set("n", n);
  const proto = Object.getPrototypeOf(url);
  const keys = Object.keys(proto).concat(Object.getOwnPropertyNames(proto));
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    if (!["constructor", "set", "get", "clone"].includes(key)) {
      url[key]();
      break;
    }
  }
  return url.get("n");
}
''';
  }

  /// Port of JavaScriptExtractor.matchToClosingBrace (simplified: counts
  /// braces; player code has no braces inside strings/comments at the
  /// function level in practice — the Java version uses a full lexer, kept
  /// as a fallback there too).
  static String matchToClosingBrace(String jsCode, String start) {
    var startIndex = jsCode.indexOf(start);
    if (startIndex < 0) {
      throw FormatException('Start not found: $start');
    }
    startIndex += start.length;
    var depth = 0;
    var visitedOpen = false;
    for (var i = startIndex; i < jsCode.length; i++) {
      final c = jsCode[i];
      if (c == '{') {
        depth++;
        visitedOpen = true;
      } else if (c == '}') {
        depth--;
        if (visitedOpen && depth == 0) {
          return jsCode.substring(startIndex, i + 1);
        }
      }
    }
    throw const FormatException('Could not find matching braces');
  }

  /// Builds the full init script: polyfill + shims + stripped player +
  /// n-transform caller. Sig support is added separately when extraction
  /// succeeds (see player_js_solver.dart's _sig handling).
  static String buildInitScript(String playerCode, String nFunctionName) {
    return kPolyfill +
        kShims +
        stripWrapper(playerCode) +
        '\n' +
        buildNHelper(nFunctionName);
  }
}

/// BaseJSChallengeSolver backed by a flutter_js QuickJS runtime evaluating
/// the environment from [PlayerJsEnvironment].
///
/// LIFECYCLE (reviewed): YoutubeService creates and closes a YoutubeExplode
/// per operation, and YoutubeExplode.close() calls solver.dispose(). The
/// QuickJS runtime is expensive to recreate (player env is cached inside
/// it), so this solver is SHARED: dispose() is a deliberate no-op and real
/// cleanup happens via [shutdown] (currently never called — the runtime
/// lives as long as the process, same as a cached HTTP client).
class PlayerJsSolver extends BaseJSChallengeSolver {
  PlayerJsSolver._(this._runtime);

  final JavascriptRuntime _runtime;

  /// Player URLs whose environment has been evaluated into the runtime.
  final Set<String> _readyEnvironments = {};

  static PlayerJsSolver? _shared;

  /// Shared instance (see LIFECYCLE above).
  static Future<PlayerJsSolver> shared() async {
    final existing = _shared;
    if (existing != null) return existing;
    final solver = PlayerJsSolver._(getJavascriptRuntime(xhr: false));
    _shared = solver;
    return solver;
  }

  /// Real engine cleanup; dispose() stays a no-op on purpose.
  static void shutdown() {
    _shared?._runtime.dispose();
    _shared = null;
  }

  @override
  void dispose() {
    // Deliberate no-op: the runtime is shared across YoutubeExplode
    // instances, each of which disposes its solver on close().
  }

  @override
  Future<String> solve(
      String playerUrl, JSChallengeType type, String challenge) async {
    final results = await solveBulk(playerUrl, {
      type: [challenge]
    });
    final decoded = results[challenge];
    if (decoded == null) {
      throw Exception('No data for challenge: $challenge');
    }
    return decoded;
  }

  @override
  Future<Map<String, String?>> solveBulk(String playerUrl,
      Map<JSChallengeType, List<String>> requests) async {
    await _ensureEnvironment(playerUrl);
    final out = <String, String?>{};
    for (final entry in requests.entries) {
      for (final challenge in entry.value) {
        final call = switch (entry.key) {
          JSChallengeType.n =>
            'deobfuscate_n_param(${jsonEncode(challenge)})',
          // Sig extraction is not wired yet: returning null keeps
          // youtube_explode's documented fallback (URL left as-is).
          JSChallengeType.sig => null,
        };
        out[challenge] = call == null ? null : _evalString(call);
      }
    }
    return out;
  }

  Future<void> _ensureEnvironment(String playerUrl) async {
    if (_readyEnvironments.contains(playerUrl)) return;
    final response = await http.get(Uri.parse(playerUrl));
    if (response.statusCode != 200) {
      throw Exception('Player script fetch failed: ${response.statusCode}');
    }
    final nName = PlayerJsEnvironment.extractNFunctionName(response.body);
    if (nName == null) {
      throw Exception('n-transform entry point not found in player script');
    }
    final initScript =
        PlayerJsEnvironment.buildInitScript(response.body, nName);
    // Engine eval runs the stripped player once (~230 ms measured on the
    // shipped QuickJS 2021-03-27; see tool/offline_solver_probe.md).
    final result = _runtime.evaluate(initScript);
    if (result.isError) {
      throw Exception('Player environment failed to load: '
          '${result.stringResult.substring(0, result.stringResult.length.clamp(0, 200) as int)}');
    }
    _readyEnvironments.add(playerUrl);
  }

  String _evalString(String code) {
    final result = _runtime.evaluate(code);
    if (result.isError) {
      throw Exception('Solver call failed: ${result.stringResult}');
    }
    return result.stringResult;
  }
}
