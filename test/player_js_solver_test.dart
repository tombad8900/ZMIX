import 'package:flutter_test/flutter_test.dart';
import 'package:zmix/js_solver/player_js_solver.dart';

/// Pure-Dart tests for the environment builder. Engine execution is covered
/// by the offline probe in tool/offline_solver_probe.md (real QuickJS
/// 2021-03-27 binary + archived real player + yt-dlp committed vectors);
/// flutter_test's VM has no native QuickJS library to load.
///
/// The synthetic fixture below mimics the STRUCTURE of a modern YouTube
/// player (wrapper IIFE, an n-entry function marked by set("alr","yes"),
/// a URL class) without copying any Google code.
const _syntheticPlayer = '''
var _yt_player={};(function(g){var window=this;
var ZU=function(){};
ZU.prototype.set=function(k,v){this[k]=v;return this;};
ZU.prototype.get=function(k){return this[k];};
ZU.prototype.Bx=function(){this.set("n",this.get("n").split("").reverse().join(""));return this;};
n8=function(Z,k,N){var L=Z&&Z.alr;Z=new ZU(Z,!0);Z.set("alr","yes");L&&N&&Z.set(k,N);return Z};
var extra=function(){ return {ok:true}; };
})(_yt_player);
''';

void main() {
  group('extractNFunctionName', () {
    test('finds the function marked by set("alr","yes")', () {
      expect(PlayerJsEnvironment.extractNFunctionName(_syntheticPlayer),
          'n8');
    });

    test(r'captures \$-prefixed entry points (current player shape)', () {
      const currentShape = r'\$o=function(a,b,c){a=new g.Xo(a,!0);a.set("alr","yes");c&&x(a)};';
      expect(PlayerJsEnvironment.extractNFunctionName(currentShape), r'$o');
    });

    test('returns null when no entry point exists', () {
      expect(PlayerJsEnvironment.extractNFunctionName('var a=1;'), isNull);
    });
  });

  group('stripWrapper', () {
    test('removes the player wrapper prefix and suffix', () {
      final stripped = PlayerJsEnvironment.stripWrapper(_syntheticPlayer);
      expect(stripped.contains('_yt_player'), isFalse);
      expect(stripped.contains('n8=function'), isTrue);
    });

    test('leaves unwrapped code untouched', () {
      const plain = 'var x = 1;';
      expect(PlayerJsEnvironment.stripWrapper(plain), plain);
    });
  });

  group('matchToClosingBrace', () {
    test('extracts a balanced brace body', () {
      const js = 'function f(a){ if(a){return {b:1};} return 2; }';
      expect(PlayerJsEnvironment.matchToClosingBrace(js, 'function f(a)'),
          '{ if(a){return {b:1};} return 2; }');
    });

    test('throws when the start is missing', () {
      expect(() => PlayerJsEnvironment.matchToClosingBrace('var a=1;', 'zz'),
          throwsFormatException);
    });

    test('throws on unbalanced braces', () {
      expect(
          () => PlayerJsEnvironment.matchToClosingBrace(
              'function f(){ return 1;', 'function f()'),
          throwsFormatException);
    });
  });

  group('buildInitScript', () {
    test('assembles polyfill + shims + stripped player + helper', () {
      final script =
          PlayerJsEnvironment.buildInitScript(_syntheticPlayer, 'n8');
      expect(script.contains('Object.hasOwn'), isTrue);
      expect(script.contains('var g = {};'), isTrue);
      expect(script.contains('_yt_player'), isFalse);
      expect(script.contains('function deobfuscate_n_param(n){'), isTrue);
      expect(script.contains('const url = n8('), isTrue);
      expect(script.endsWith('}\n'), isTrue);
    });
  });
}
