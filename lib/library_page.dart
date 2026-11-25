import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'models.dart';
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
  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141B),
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
                              color: Color(0xFFEDE9FF),
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
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _PlaylistCard(
                      playlist: store.playlists[i],
                      store: store,
                    ),
                    childCount: store.playlists.length,
                  ),
                ),
              ),
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

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.store});

  final LibraryPlaylist playlist;
  final LibraryStore store;

  Future<void> _onLongPress(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF14141B),
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
              title: const Text('حذف من المكتبة', style: TextStyle(color: Colors.redAccent)),
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
          content: const Text('القائمة هتتشال من المكتبة. سجل المشاهدة هيفضل زي ما هو.'),
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
    return GestureDetector(
      onLongPress: () => _onLongPress(context),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlaylistPage(playlist: playlist, store: store),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'pl_${playlist.id}',
              child: playlist.thumbUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: playlist.thumbUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const _ArtFallback(),
                      placeholder: (_, __) => const _ArtFallback(),
                    )
                  : const _ArtFallback(),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3000000), Color(0xE6000000)],
                  stops: [0.45, 0.75, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _countLabel(playlist),
                    style: TextStyle(
                      fontSize: 12,
                      color: playlist.importComplete
                          ? const Color(0xFFC9C9D4)
                          : const Color(0xFFFFC36B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _countLabel(LibraryPlaylist playlist) {
  if (playlist.importComplete) return '${playlist.videos.length} فيديو';
  final got = playlist.videos.length;
  switch (playlist.importNote) {
    case 'short_of_declared':
      return '$got من ${playlist.totalCountHint} معلنة - الباقي مش متاح من يوتيوب';
    case 'cancelled':
      return '$got فيديو - الاستيراد اتلغى';
    case 'network':
      return '$got فيديو - الاستيراد وقف في النص';
    default:
      return '$got فيديو - ناقصة';
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF3B2F8F), Color(0xFF1A1726)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.play_circle_outline, size: 44, color: Color(0x55FFFFFF)),
      ),
    );
  }
}

/// Bottom sheet: paste a YouTube playlist link, optional nickname, add.
class AddPlaylistSheet extends StatefulWidget {
  const AddPlaylistSheet({super.key, required this.store});

  final LibraryStore store;

  @override
  State<AddPlaylistSheet> createState() => _AddPlaylistSheetState();
}

class _AddPlaylistSheetState extends State<AddPlaylistSheet> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _busy = false;
  bool _cancelRequested = false;
  String? _status;
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
            ? 'يوتيوب بيعلن ${playlist.totalCountHint} فيديو لكن اللي بيقدمه فعليًا ${playlist.videos.length} بس (غالبًا فيه فيديوهات محذوفة أو خاصة جوه القايمة).'
            : 'اتحفظ ${playlist.videos.length} فيديو بس - الاستيراد مكملش للآخر. إعادة إضافة القايمة بتستكملها.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(detail),
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
                style: const TextStyle(color: Color(0xFF9E97FF), fontSize: 13),
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
        fillColor: const Color(0xFF0E0E13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );
}
