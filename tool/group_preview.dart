/// 分组预览：读 alerts.json / alerts_store.json，用新 extractObjectKey 规则分组，
/// 打印 top 分组，验证对象提取是否正确。
///
/// 用法：flutter pub run tool/group_preview.dart /path/to/alerts_store.json
library;

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:smsmanager/models/alert.dart';
import 'package:smsmanager/services/object_key.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('用法：flutter pub run tool/group_preview.dart <alerts.json>');
    exit(1);
  }
  final data = jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
  final raw = (data['alerts'] as List).cast<Map<String, dynamic>>();

  final alerts = <SmsAlert>[];
  for (final m in raw) {
    final atMs = m['at'] as int? ??
        DateTime.tryParse(m['receivedAt'] as String? ?? '')?.millisecondsSinceEpoch ??
        0;
    alerts.add(SmsAlert(
      id: (m['id'] as num?)?.toInt() ?? 0,
      sender: m['sender'] as String? ?? '',
      body: m['body'] as String? ?? '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(atMs),
      type: AlertType.unknown,
      severity: AlertSeverity.unknown,
    ));
  }

  final groups = <String, int>{};
  for (final a in alerts) {
    final k = extractAlertObjectKey(a.body);
    groups[k] = (groups[k] ?? 0) + 1;
  }
  final sorted = groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  print('共 ${alerts.length} 条 → ${groups.length} 个对象分组\n');
  for (final e in sorted.take(30)) {
    print('${e.value.toString().padLeft(4)}  ${e.key.length > 60 ? '${e.key.substring(0, 60)}…' : e.key}');
  }
  // 兜底分组占比
  final fallback = sorted.where((e) => e.key.length <= 30 && !e.key.contains(RegExp(r'[a-z0-9_]'))).fold(0, (s, e) => s + e.value);
  print('\n疑似兜底(无小写字母/数字结构的 key) 合计约 $fallback 条');
}
