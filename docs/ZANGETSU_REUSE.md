# Zangetsu code reuse map

Upstream: https://github.com/Spyou/Zangetsu
Upstream commit: `772fac56d265b238b90118bd68abe2e7353b1f6e`
("feat(player): sleep timer on the native player", 2026-11-25)
License: GPL-3.0 (upstream LICENSE). ZMIX is GPL-3.0 and public, so reuse is
license-compatible; upstream copyright applies to the adapted files.

The user instruction was literal copy/paste of the original source as the
foundation, with only the edits needed to integrate it into ZMIX. Where a
verbatim copy was impossible, this document names the dependency that forced
the edit instead of silently rewriting. Full per-file evidence: unified
diffs (upstream file vs ZMIX file) in `docs/diffs/` for every
upstream-derived file that is WIRED INTO THE APK:
`poster_card.diff`, `player_controls_overlay.diff`, `player_seek_bar.diff`,
`player_controls_widgets.diff`, `player_controls_config.diff`,
`app_text.diff`, `app_colors.diff`, `frosted_surface.diff`.

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

## Player: lib/player/ — LITERAL port, wired into the APK

As of the wiring commit the player controls are a literal copy of upstream's
player UI files, with integration edits only (each marked `ZMIX-EDIT` in
place). `lib/player_page.dart` mounts `PlayerControlsOverlay` exactly the
way upstream's `player_screen.dart` does: only when unlocked, inside the
production `ControlsGate` (AnimatedOpacity 160ms in / 240ms out +
IgnorePointer when hidden), with `PlayerControlsConfig.defaults` as the bar
layout.

| ZMIX file (wired) | Upstream file | Edits |
|---|---|---|
| lib/player/player_controls_overlay.dart | features/player/player_controls_overlay.dart | PlayerCubit/PlayerState replaced by the `ZmixPlayerSurface` seam (`MediaKitPlayerSurface` in production, fakes in widget tests — a real media_kit Player needs native libmpv and cannot exist in a VM test); l10n lookups replaced by inline Arabic; episode facts arrive as plain fields; `transportHidden` flag added so ZMIX's centered double-tap seek pill never overlaps the center transport; `_fitIcon` maps ZMIX's Arabic fit labels; the 'more' spec returns null while its panel has no rows |
| lib/player/player_seek_bar.dart | features/player/player_seek_bar.dart | `part of` kept; scrub-preview bubble (SeekPreview storyboard frames) omitted — ZMIX has no storyboard source; the time bubble and all slider logic kept |
| lib/player/player_controls_widgets.dart | features/player/player_controls_widgets.dart | `part of` kept; see above for `_fitIcon` |
| lib/player/player_controls_config.dart | features/player/player_controls_config.dart | near-verbatim; unsupported ids fall through to null via upstream's own skip mechanism |
| lib/player/app_text.dart | core/theme/app_text.dart | near-verbatim (styles carry their own CJK/sans-serif fallback chain) |
| lib/player/app_colors.dart | core/theme/app_colors.dart | near-verbatim (accent #FF4D57) |
| lib/player/frosted_surface.dart | core/ui/frosted_surface.dart | near-verbatim (used by the More panel) |

Material upstream omissions (features ZMIX does not have; they take nullable
callbacks / fall through upstream's null-skip rather than pretending):
cast, decoder switch, enhance, colour profiles, snapshot, sleep timer, PiP,
minimize, engine switch, ambient mode, room chat, info panel, episodes
panel, sources, subtitle/audio tracks, MegaSkip pill, settings shortcut,
Jikan filler badge, scrub storyboard previews, the TV controls variant, and
upstream's speed/sleep/settings sheets (ZMIX keeps its own speed cycling;
rotate is dropped because ZMIX is landscape-locked). The 'more' overflow
panel is ported but has no rows yet, so its button drops out until one
exists. Dormant upstream elements carried with the literal copy and not
currently rendered: `_showMore`, `_placedAnywhere`, `_MegaSkipPill`,
`_RoundIconButton`, `_MoreRow` (analyzer documents them as unused elements).

ZMIX-specific player extras with NO upstream counterpart, in
`lib/player_hud.dart` and `lib/player_page.dart`: double-tap ±10s seek with
the centered `SeekIndicator` pill, drag-anywhere scrub (live throttled
seek, since the ported bar renders the position stream), vertical-drag
brightness/volume with `PlayerHud`, long-press 2x boost with `BoostBadge`,
`LockOverlay` for the locked state, pinch-to-zoom 1-4x with pan (ported
earlier from player_screen.dart), and `PlayerErrorPanel` whose layout
follows upstream `drm_player_screen.dart`'s error state (centered icon +
message + Close/Try again on a dark backing). The fit trio
(contain/cover/fill) lives in `lib/player_chrome.dart` as `kPlayerFits`
(verbatim trio and order) alongside the `QualityListSheet` below.

## Quality picker

Zangetsu lists the resolved muxed qualities in a bottom sheet with a check on
the active row. ZMIX's `QualityListSheet` follows that sheet; the stream list
comes from ZMIX's own InnerTube resolver (muxed qualities only).
