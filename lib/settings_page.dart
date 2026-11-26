import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'diagnostics.dart';
import 'storage.dart';

/// One honest line about loss/write state for the diagnostics tile:
/// drops (per class), failed writes, and events still waiting to be written.
String _diagStatsSubtitle(DiagStats s) {
  final lost = s.droppedNormal + s.droppedCritical;
  final parts = <String>[
    if (lost == 0 && s.writeFailures == 0 && s.pending == 0)
      'مفيش أحداث اتحذفت',
    if (lost > 0)
      'اتحذفت $lost أحداث${s.droppedCritical > 0 ? ' (منها حرجة: ${s.droppedCritical})' : ''}',
    if (s.writeFailures > 0) 'كتابات فاشلة: ${s.writeFailures}',
    if (s.pending > 0) 'لم تُكتب بعد: ${s.pending}',
  ];
  return parts.join(' · ');
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});

  final LibraryStore store;

  static const String appVersion = '0.3.6';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyReport() async {
    final report = await Diag.I.buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) _toast('التقرير اتنسخ — الصقه في أي مكان');
  }

  Future<void> _saveReport() async {
    try {
      final path = await Diag.I.saveReportToFile();
      if (mounted) {
        _toast('التقرير اتحفظ في:\n$path');
      }
    } catch (_) {
      if (mounted) _toast('مش قادرين نحفظ الملف دلوقتي');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = Diag.I.stats();
    final kb = (stats.bytes / 1024).toStringAsFixed(0);
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
              action: widget.store.clearHistory,
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
              action: widget.store.clearAll,
            ),
          ),
          const Divider(height: 32),
          const ListTile(
            leading: Icon(Icons.troubleshoot_rounded),
            title: Text('التشخيص'),
            subtitle: Text(
              'سجل أحداث محلي ومنقّح: الروابط تتحفظ كاسم مضيف بس، ولا يُرسل أي حاجة لأي حد تلقائيًا.',
              style: TextStyle(height: 1.7),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('تفعيل التشخيص'),
            subtitle: const Text('يسجّل طلباتك ونتايج التشغيل من دلوقتي'),
            value: Diag.I.enabled,
            onChanged: (v) async {
              await Diag.I.setEnabled(v);
              setState(() {});
            },
          ),
          if (Diag.I.enabled) ...[
            SwitchListTile(
              secondary: const Icon(Icons.format_list_bulleted_rounded),
              title: const Text('سجل مفصّل'),
              subtitle: const Text('يضيف الأزرار العادية والتخزين المؤقت'),
              value: Diag.I.verbose,
              onChanged: (v) async {
                await Diag.I.setVerbose(v);
                setState(() {});
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.tag_rounded),
              title: const Text('تضمين معرّفات الفيديو'),
              subtitle: const Text('مقفول = أقصى تنقيح (أرقام ترتيب بس)'),
              value: Diag.I.includeVideoIds,
              onChanged: (v) async {
                await Diag.I.setIncludeVideoIds(v);
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.query_stats_rounded),
              title: Text('الأحداث: ${stats.events} · الحجم: $kb ك.ب'),
              subtitle: Text(_diagStatsSubtitle(stats)),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ التقرير'),
              subtitle: const Text('منقّح وجاهز للصق'),
              onTap: _copyReport,
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('حفظ التقرير كملف'),
              subtitle: const Text('ملف نصي على الجهاز'),
              onTap: _saveReport,
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('مسح سجل التشخيص'),
              onTap: () => _confirm(
                context,
                title: 'مسح سجل التشخيص؟',
                body: 'كل أحداث التشخيص المحفوظة هتتمسح من الجهاز.',
                actionLabel: 'مسح',
                action: () async {
                  await Diag.I.clear();
                  setState(() {});
                },
              ),
            ),
          ],
          const Divider(height: 32),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('ZMIX'),
            subtitle: Text(
              'نسخة ${SettingsPage.appVersion}\nمكتبتك السينمائية لقوائم يوتيوب. بيانات المكتبة محفوظة على جهازك، وجلب القوائم والتشغيل بيتم من خلال يوتيوب.\nواجهة المشغّل وبطاقات المحتوى معدّلة من كود مشروع Zangetsu (GPL-3.0)، وفكرة تشغيل يوتيوب من Cloudstream (GPL-3.0). كود ZMIX مفتوح المصدر تحت GPL-3.0 مع الحفاظ على إشعارات حقوقهم.',
              style: TextStyle(height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}
