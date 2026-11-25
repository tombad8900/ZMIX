import 'package:flutter/material.dart';

import 'main.dart';
import 'models.dart';
import 'play_launcher.dart';
import 'ui/poster_card.dart';
import 'playlist_page.dart';
import 'storage.dart';
import 'youtube_service.dart';

/// Home: the cinema shelf. Playlist cards with full-bleed artwork.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store});

  final LibraryStore store;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  @override
  void initState() {
    super.initState();
    // Preview-only (kDemoProgress): open the add sheet in a simulated
    // mid-import state for pixel verification of the progress UI.
    if (kDemoProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openAddSheet();
      });
    }
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddPlaylistSheet(store: widget.store),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اتضافت للمكتبة ✅')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ZMIX',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.5,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'سينما البلاي ليستات بتاعتك',
                            style: TextStyle(color: Color(0xFF8E8E9A), fontSize: 13.5),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _openAddSheet,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (store.playlists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyShelf(onAdd: _openAddSheet),
              )
            else
              // Zangetsu home style: one section per playlist - header with
              // name, count and chevron, then a horizontal shelf of the
              // first videos as wide poster cards.
              ...[
                for (final playlist in store.playlists) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(playlist: playlist, store: store),
                  ),
                  SliverToBoxAdapter(
                    child: _VideoShelf(playlist: playlist, store: store),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
          ],
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 72, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 16),
            const Text(
              'المكتبة فاضية لسه',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'هات رابط أي بلاي ليست من يوتيوب\nوهتتحول لرف سينما عندك.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8E8E9A), height: 1.7),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('أضف أول بلاي ليست'),
            ),
          ],
        ),
      ),
    );
  }
}

class AddPlaylistSheet extends StatefulWidget {
  const AddPlaylistSheet({super.key, required this.store});

  final LibraryStore store;

  @override
  State<AddPlaylistSheet> createState() => _AddPlaylistSheetState();
}

class _AddPlaylistSheetState extends State<AddPlaylistSheet> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _busy = kDemoProgress;
  bool _cancelRequested = false;
  String? _status = kDemoProgress ? 'بنستورد... وصلنا لـ 148 فيديو' : null;
  String? _error;

  Future<void> _add() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _error = null;
      _status = 'بنقرأ القائمة من يوتيوب...';
    });
    final service = YoutubeService();
    try {
      final playlist = await service.fetchPlaylist(
        _urlController.text,
        nickname: _nameController.text,
        onProgress: (fetched) {
          if (mounted) {
            setState(() => _status = 'بنستورد... وصلنا لـ $fetched فيديو');
          }
        },
        isCancelled: () => _cancelRequested,
      );
      if (playlist.videos.isEmpty) {
        setState(() {
          _error = 'القائمة دي فاضية أو مش متاحة';
          _status = null;
        });
        return;
      }
      setState(() => _status = 'بنحفظ ${playlist.videos.length} فيديو...');
      await widget.store.addPlaylist(playlist);
      if (!mounted) return;
      if (!playlist.importComplete) {
        // Partial import stays visibly partial; never implied complete.
        final detail = playlist.importNote == 'short_of_declared'
            ? 'اتجاب ${playlist.videos.length} مدخل من أصل ${playlist.totalCountHint} معلنة في يوتيوب. الفرق غالبًا فيديوهات يوتيوب نفسه مش بيقدمها حتى في عرض "إظهار غير المتاح" - مش مؤكد إن الباقي متاح.'
            : 'اتحفظ ${playlist.videos.length} فيديو بس - الاستيراد مكملش للآخر. إعادة إضافة القايمة بتستكملها.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(detail),
          duration: const Duration(seconds: 7),
        ));
      } else if (playlist.hiddenUntitledCount > 0 ||
          playlist.hiddenTitledCount > 0) {
        // Complete import with YouTube-hidden entries: honest counts.
        final parts = <String>[
          if (playlist.hiddenUntitledCount > 0)
            '${playlist.hiddenUntitledCount} بلا عنوان عند يوتيوب (من غير سبب معلن)',
          if (playlist.hiddenTitledCount > 0)
            '${playlist.hiddenTitledCount} يوتيوب بيخفيهم من العرض الافتراضي',
        ];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'اتحفظت القايمة كاملة: ${playlist.videos.length} مدخل - منهم ${parts.join(' و')}. تشغيل أي مدخل بيتحدد عند فتحه.'),
          duration: const Duration(seconds: 7),
        ));
      }
      Navigator.pop(context, true);
    } on FormatException catch (e) {
      setState(() {
        _error = e.message;
        _status = null;
      });
    } catch (_) {
      setState(() {
        _error = 'مش قادرين نوصل للقائمة دي دلوقتي. جرّب تاني أو اتأكد من النت.';
        _status = null;
      });
    } finally {
      service.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إضافة بلاي ليست',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: _fieldDeco('https://www.youtube.com/playlist?list=...'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: _fieldDeco('اسم على مزاجك (اختياري)'),
          ),
          const SizedBox(height: 16),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _status!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF4D57), fontSize: 13),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _add,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(_busy ? 'بنجيب...' : 'إضافة للمكتبة'),
          ),
          if (_busy)
            TextButton(
              onPressed: () => setState(() => _cancelRequested = true),
              child: const Text('إلغاء الاستيراد والاحتفاظ باللي اتجاب'),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6E6E78), fontSize: 13.5),
        filled: true,
        fillColor: const Color(0xFF0B0B0F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );
}

/// Section header: playlist name, video count, chevron into the full grid.
/// Mirrors Zangetsu's home row headers (title + chevron_right affordance).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.playlist, required this.store});

  final LibraryPlaylist playlist;
  final LibraryStore store;

  /// Rename/delete actions, carried over verbatim from the old playlist card.
  Future<void> _onLongPress(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF16161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تغيير الاسم'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('حذف من المكتبة',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('حذف القائمة؟'),
          content: const Text(
              'القائمة هتتشال من المكتبة. سجل المشاهدة هيفضل زي ما هو.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      if (ok == true) await store.removePlaylist(playlist.id);
    } else if (action == 'rename') {
      final controller = TextEditingController(text: playlist.name);
      final newName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('اسم القائمة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'اكتب الاسم الجديد'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (newName != null) await store.renamePlaylist(playlist.id, newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistPage(playlist: playlist, store: store),
        ),
      ),
      onLongPress: () => _onLongPress(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                  Text(
                    '${playlist.videos.length} فيديو',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFA7A7B2)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Color(0xFFA7A7B2)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal shelf of the playlist's first videos as wide poster cards
/// (Zangetsu wide shelf cell width: 184).
class _VideoShelf extends StatelessWidget {
  const _VideoShelf({required this.playlist, required this.store});

  final LibraryPlaylist playlist;
  final LibraryStore store;

  static const int _maxCards = 12;

  @override
  Widget build(BuildContext context) {
    final videos = playlist.videos.take(_maxCards).toList();
    return SizedBox(
      height: posterRowHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final video = videos[i];
          return SizedBox(
            width: posterRowWidth(context),
            child: PosterCard(
              title: video.isSourceUntitled ? 'فيديو بلا عنوان' : video.title,
              imageUrl: video.thumbUrl.isEmpty ? null : video.thumbUrl,
              tags: [
                if (video.isSourceUntitled)
                  'بلا عنوان'
                else if (video.visibility == 'hiddenTitled')
                  'مخفي افتراضيًا',
                if (video.durationLabel.isNotEmpty) video.durationLabel,
              ],
              onTap: () => playLibraryVideo(
                context,
                store: store,
                playlist: playlist,
                video: video,
              ),
            ),
          );
        },
      ),
    );
  }
}
