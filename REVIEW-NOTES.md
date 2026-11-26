# Review branch: diag3 + A + B draft (read-only review, do not merge)

Base: master 32ab5ff (0.3.5, the last public release).
This branch is NOT built or released from here and is NOT merged to master.

Layers on top of 0.3.5:
1. Installed on the user's phone (diag1 -> diag3, versionName 0.3.6-diag3, applicationId app.zmix.zmix.diag):
   local-only diagnostics (off by default, redacted before persistence, never auto-uploaded),
   typed-manifest fix (pickBestMuxed), extra probes in youtube_service/player_page.
2. NOT installed, authorized, tested (suite green):
   A. first-play log fires once per open (PlaybackSwitcher.onFirstPlaybackConfirmation).
   C. diagnostic-only critical events for quality pick / open result / rollback / audio attach.
3. NOT installed, DRAFT, NOT approved by the user:
   B. LaunchGate (lib/launch_gate.dart) + use in lib/play_launcher.dart.
   Scope caveat: covers playLibraryVideo only; other launch paths and in-player
   next/previous are untouched; no route ownership or episode changes.

Known open questions: why quality picks look ineffective (cause unproven).
No secrets in this tree (signing keys / local.properties are not tracked).
