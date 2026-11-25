import 'package:flutter/material.dart';

import 'player_hud.dart';

/// Shared player pieces that are NOT part of the literal Zangetsu controls
/// port (lib/player/): the fit-mode trio (same order as Zangetsu's `_fits`
/// in player_screen.dart: contain / cover / fill) and the quality bottom
/// sheet (adapted from Zangetsu's quality sheet: title, one row per
/// quality, check on the active row). The overlay itself, its seek bar,
/// widgets, HUD, error panel and lock overlay now live in lib/player/
/// (literal port) and lib/player_hud.dart (ZMIX-specific extras).
// ── Fit modes and quality picker ─────────────────────────────────────────

/// Fit modes, same trio and order as Zangetsu's `_fits` in
/// player_screen.dart: contain (fit) / cover (zoom, crop) / fill (stretch).
const List<(BoxFit, String)> kPlayerFits = [
  (BoxFit.contain, 'ملاءمة'),
  (BoxFit.cover, 'توسيع'),
  (BoxFit.fill, 'تمديد'),
];

/// Next fit in Zangetsu's cycle order.
int nextFitIndex(int current) => (current + 1) % kPlayerFits.length;

/// Quality picker list, adapted from Zangetsu's quality bottom sheet:
/// a title, one row per available quality, check mark on the active row.
/// Shown by the caller inside a modal bottom sheet.
class QualityListSheet extends StatelessWidget {
  const QualityListSheet({
    super.key,
    required this.qualities,
    required this.activeQuality,
    required this.onPick,
  });

  final List<String> qualities;
  final String activeQuality;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('جودة التشغيل',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          for (final q in qualities)
            ListTile(
              title: Text(q),
              trailing: q == activeQuality
                  ? const Icon(Icons.check_rounded,
                      color: accent)
                  : null,
              onTap: () => onPick(q),
            ),
        ],
      ),
    );
  }
}
