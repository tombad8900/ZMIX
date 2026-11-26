# mpv external-audio header contract (Linux experiment, localhost only)

Not part of the app and not run by CI. No YouTube network.

Setup (all under /tmp/mpvx): a synthetic video `v.mp4` and audio `a.m4a`
(ffmpeg lavfi sources), `server.py` (logs request headers), and an mpv
0.42.0 AppImage (pkgforge-dev/mpv-AppImage). `experiment.py` mimics media_kit
1.2.6: set `http-header-fields`, `loadfile`, then `audio-add`; then reset the
property to empty (media_kit's on_unload) and open another file.

Result (Linux, mpv 0.42.0, 2026-11-26):
- With the property set before `loadfile`, BOTH the video request and the later
  `audio-add` requests carried the custom User-Agent and extra header.
- Control without the property: both requests sent `User-Agent: libmpv`.
- After the property was reset to empty, the next open sent `libmpv` again
  (no leakage across opens).

Limits: media_kit's bundled libmpv and Android were NOT tested; this shows mpv's
option semantics, not that YouTube accepts the pairing.
