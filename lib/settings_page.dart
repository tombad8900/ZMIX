import 'package:flutter/material.dart';

import 'storage.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});

  final LibraryStore store;

  static const String appVersion = '0.2.1';

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String actionLabel,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (ok == true) await action();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('مسح سجل المشاهدة'),
            subtitle: const Text('المكتبة هتفضل زي ما هي'),
            onTap: () => _confirm(
              context,
              title: 'مسح السجل؟',
              body: 'كل سجل المشاهدة هيتمسح من الجهاز.',
              actionLabel: 'مسح',
              action: store.clearHistory,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
            title: const Text('حذف كل البيانات', style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('المكتبة والسجل مع بعض'),
            onTap: () => _confirm(
              context,
              title: 'حذف كل حاجة؟',
              body: 'كل البلاي ليستات والسجل هيتمسحوا من الجهاز نهائيًا.',
              actionLabel: 'حذف',
              action: store.clearAll,
            ),
          ),
          const Divider(height: 32),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('ZMIX'),
            subtitle: Text(
              'نسخة $appVersion\nمكتبتك السينمائية لقوائم يوتيوب. بيانات المكتبة محفوظة على جهازك، وجلب القوائم والتشغيل بيتم من خلال يوتيوب.\nالشكل مستوحى من Zangetsu وCloudstream، والكود مفتوح المصدر تحت GPL-3.0.',
              style: TextStyle(height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}
