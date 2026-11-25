import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'player_page.dart';
import 'storage.dart';
import 'youtube_service.dart';

/// Watch history, newest first.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store});

  final LibraryStore store;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String? _resolvingId;

  Future<void> _replay(HistoryEntry entry) async {
    if (_resolvingId != null) return;
    setState(() => _resolvingId = entry.videoId);
    final service = YoutubeService();
    try {
      final stream = await service.resolvePlayable(entry.videoId);
      await widget.store.recordPlay(
        videoId: entry.videoId,
        title: entry.title,
        thumbUrl: entry.thumbUrl,
        playlistName: entry.playlistName,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerPage(
            title: entry.title,
            streamUrl: stream.url,
            qualityLabel: stream.quality,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مش قادرين نشغّل الفيديو ده دلوقتي.')),
        );
      }
    } finally {
      service.close();
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مسح السجل؟'),
        content: const Text('كل سجل المشاهدة هيتمسح من الجهاز.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('مسح'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.store.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.store.history;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المشاهدة'),
        backgroundColor: Colors.transparent,
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'مسح السجل',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: history.isEmpty
          ? const Center(
              child: Text(
                'لسه مفيش مشاهدات.\nأول ما تشغّل حاجة هتظهر هنا.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8E8E9A), height: 1.7),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final entry = history[i];
                final resolving = _resolvingId == entry.videoId;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  onTap: () => _replay(entry),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 112,
                      height: 63,
                      child: entry.thumbUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: entry.thumbUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  Container(color: const Color(0xFF1A1726)),
                              placeholder: (_, __) =>
                                  Container(color: const Color(0xFF1A1726)),
                            )
                          : Container(color: const Color(0xFF1A1726)),
                    ),
                  ),
                  title: Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.45),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (entry.playlistName.isNotEmpty) entry.playlistName,
                        DateFormat('d MMM، h:mm a', 'ar').format(entry.playedAt),
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF8E8E9A)),
                    ),
                  ),
                  trailing: resolving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                );
              },
            ),
    );
  }
}
