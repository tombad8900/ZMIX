import 'package:flutter/material.dart';

/// ZMIX-specific player overlays that have no counterpart in Zangetsu's
/// controls overlay: double-tap seek indicator, brightness/volume HUD, the
/// 2x boost badge, the lock-state unlock button, and the playback error
/// panel (whose LAYOUT follows Zangetsu's drm_player_screen error state:
/// centered icon + message + Close / Try again on a dark backing).
const accent = Color(0xFFFF4D57);

class SeekIndicator extends StatelessWidget {
  const SeekIndicator({super.key, required this.delta, required this.forward});

  final int delta;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              '${delta.abs()} ث',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerHud extends StatelessWidget {
  const PlayerHud({
    super.key,
    required this.isBrightness,
    required this.value,
  });

  final bool isBrightness;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBrightness ? Icons.wb_sunny_outlined : Icons.volume_up_rounded,
              size: 22,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BoostBadge extends StatelessWidget {
  const BoostBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('2×',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }
}

/// Error presentation from Zangetsu's player (drm_player_screen.dart lines
/// ~275-318): a centered icon + message + Close / Try again buttons,
/// replacing the center transport instead of overlapping actionable
/// controls. Dark backing keeps it readable over bright frames.
class PlayerErrorPanel extends StatelessWidget {
  const PlayerErrorPanel({
    super.key,
    required this.errorText,
    required this.onBack,
    required this.onRetry,
  });

  final String errorText;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xE60B0B0F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              'حصل خطأ في التشغيل: $errorText',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onBack,
                  child: const Text('إغلاق',
                      style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onRetry,
                  child: const Text('حاول تاني'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The one control visible while controls are locked, matching the ported
/// `_RoundIconButton` (black 0.5 circle, 12px padding, 24px icon).
class LockOverlay extends StatelessWidget {
  const LockOverlay({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onUnlock,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.lock_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
