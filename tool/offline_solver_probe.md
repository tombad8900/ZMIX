# Offline solver probe (reproducible, no YouTube requests)

Proves the PlayerJsSolver algorithm end-to-end on the EXACT JavaScript
engine flutter_js 0.8.7 ships on Android, without contacting YouTube.
Nothing here is committed except this document: the player fixture stays
out of the repo (it is Google-copyrighted code; fetch it on demand from
the Wayback Machine as shown below).

## Inputs

1. Engine: QuickJS 2021-03-27 built from Bellard's source
   (`quickjs-2021-03-27.tar.xz`). This is the version pinned by
   fastdev/android-js-runtimes quickjs:0.3.6 (CONFIG_VERSION "2021-03-27"),
   which flutter_js 0.8.7 bundles for Android.
2. Player fixture (public provenance, YouTube itself is never contacted):
   `http://web.archive.org/web/20260605180235id_/https://www.youtube.com/s/player/74edf1a3/player_ias.vflset/en_US/base.js`
   Provenance cross-check: its signature timestamp (sts 20522) matches the
   yt-dlp/ejs fixture comment for player `74edf1a3`.
3. Expected answers: yt-dlp/ejs committed test vectors
   (`src/yt/solver/test/tests.ts`, player "74edf1a3"):
   - n: `IlLiA21ny7gqA2m4p37` -> `9nRTxrbM1f0yHg`
   - n: `eabGFpsUKuWHXGh6FR4` -> `izmYqDEY6kl7Sg`
   - n: `eabGF/ps%UK=uWHXGh6FR4` -> `LACmqlhaBpiPlgE-a`

## Procedure

Build the init script exactly as `PlayerJsEnvironment.buildInitScript`
does (polyfill + shims + stripped player + deobfuscate_n_param helper),
evaluate it once in `qjs`, then call
`deobfuscate_n_param("<challenge>")` for each vector.

## Measured result (2026-11-25)

- Player environment eval: 228 ms (server CPU; expect low single-digit
  seconds worst case on a phone, cached per player version at runtime).
- All three n-challenges: outputs match the committed vectors exactly
  (`ALL MATCH: true`), each solve ~1 ms.

## Negative result kept for the record

The alternative EJS path (youtube_explode's BaseEJSSolver + yt-dlp ejs
0.8.0 bundled modules) was validated on V8/Node (all 4 vectors match in
1.5 s) but its whole-player AST parse did not finish in 110 s on QuickJS
2021-03-27 (no JIT). Not viable on-device; that is why the solver ports
NewPipe's plain-eval approach instead.

## What remains unproven (by design)

- The regex patterns and URL-class instantiation must match TODAY's
  player, not the June 2026 snapshot: needs one permitted live player
  fetch or a device run (gated on project-owner approval).
- Whether deciphered adaptive URLs then play on the user's network:
  device test only.
