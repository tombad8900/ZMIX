# Zangetsu code reuse map

Upstream: https://github.com/Spyou/Zangetsu
Upstream commit: `772fac56d265b238b90118bd68abe2e7353b1f6e`
("feat(player): sleep timer on the native player", 2026-11-25)
License: GPL-3.0 (upstream LICENSE). ZMIX is GPL-3.0 and public, so reuse is
license-compatible; upstream copyright applies to the adapted files.

The user instruction was literal copy/paste of the original source as the
foundation, with only the edits needed to integrate it into ZMIX. Where a
verbatim copy was impossible, this document names the dependency that forced
the edit instead of silently rewriting. Full per-file evidence:
`docs/diffs/poster_card.diff` and `docs/diffs/player_controls_overlay.diff`
(unified diffs, upstream file vs ZMIX file).

## Cards: lib/ui/poster_card.dart <- upstream lib/core/ui/poster_card.dart

Copied verbatim or near-verbatim:

| Upstream symbol | ZMIX | Status |
|---|---|---|
| `_posterTextScrim` (colors 0x8C/0x2E/0x00 0B0B0F, stops 0/0.26/0.68) | same | verbatim |
| `_responsiveColumns` | same | verbatim |
| `posterGridColumns` / `posterGridCellWidth` | same, `wide` made a parameter (ZMIX art is always 16:9) | adapted |
| `posterRowWidth` (184 wide / 116) | same | verbatim values |
| `PosterCard` state: press handlers + AnimatedScale 0.97 / 120ms / easeOut | same | verbatim |
| build(): ClipRSuperellipse r12, StackFit.expand art, scrim, bottom-left badge row, fixed two-line title box | same structure | adapted (see forced edits) |
| `_PosterTag` | same | verbatim except inline text style |
| `_kTitleGap` = 8, `posterCellHeight`, `posterCellAspect`, `_posterTitleHeight` | same | verbatim |
| `PosterCardTitle` text path (13px, height 1.3, 2 lines, ellipsis) | same | verbatim values |

Forced edits (dependency does not exist in ZMIX):

- `MediaItem` / `logoItem` / `TitleLogoService` (catalogue identity and title
  artwork): dropped; ZMIX cards show plain text titles.
- `PlaybackPrefs` / `PosterCardScope` / `posterLayout` (user poster-size and
  layout preferences): ZMIX has no such settings; cards take `wide`
  explicitly, title placement fixed below the art.
- `AppImageCache.manager`, Aniyomi/Mihon image providers (Cloudflare-carrying
  fetchers): plain `CachedNetworkImage`; YouTube thumbnails need neither.
- `AppColors.surface2/textPrimary` -> literal values (0xFF20212A / white).
- TV grid variants (`tvPosterGridColumns` etc.): not ported, ZMIX is phone-only.
- `_ScoreTag` / `_CountChip` (catalogue score/behind badges): not ported,
  ZMIX has no catalogue metadata; duration label rides the `tags` slot.

## Player: lib/player_chrome.dart <- upstream lib/features/player/player_controls_overlay.dart (+ player_seek_bar.dart, player_screen.dart)

Zangetsu's overlay is bound to its PlayerCubit/bloc/get_it/l10n stack, so the
file cannot be dropped in as-is; the layout, values and behaviors below are
taken from the upstream source and re-bound to ZMIX's stateless chrome +
player-page split:

| Upstream source | ZMIX | Status |
|---|---|---|
| Top scrim gradient (0x59 -> 0, height 110) and bottom scrim (0x8C -> 0, height 170) | player_chrome.dart build | verbatim values |
| Two-line top bar: primary title + secondary line, back button, lock button | same | adapted binding |
| Center transport: previous / 58px play-pause disc / next | same | adapted binding |
| Bottom block: seek row above a row of `_BarGroup` translucent capsules (pickers left, fit right), padding 44/14 | same | adapted binding |
| player_seek_bar.dart: coral slider, tap total<->remaining time, 250ms position sampling | _SeekRow | adapted binding |
| player_screen.dart `_fits`: contain / cover / fill cycle | `kPlayerFits` + `nextFitIndex` in player_chrome.dart | verbatim trio and order |
| Accent #FF4D57 (app_colors.dart) | `PlayerChrome.accent` | verbatim value |

Not yet ported: continuous pinch-zoom 1-4x (player_screen.dart ~2408-2460)
and the native sleep timer. Tracked as remaining work.

## Quality picker

Zangetsu lists the resolved muxed qualities in a bottom sheet with a check on
the active row. ZMIX's `QualityListSheet` follows that sheet; the stream list
comes from ZMIX's own InnerTube resolver (muxed qualities only).
