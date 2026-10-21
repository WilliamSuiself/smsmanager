/// 建行告警 - 历史短信离线分析脚本（**只看告警**）
///
/// 外汇 / 账户信息 / 营销等非告警短信在解析层就被立即丢弃，
/// 本脚本的输出中也**绝不展示**任何非告警内容。
///
/// 用法：
///   flutter pub run tool/analyze.dart < history.jsonl        # 从文件读
///   cat history.jsonl | flutter pub run tool/analyze.dart -   # 从 stdin 读
///
/// 输入格式：每行一个 JSON 对象
///   {"sender":"95533", "body":"短信原文", "date":1696584000000}
///
/// date 是 epoch 毫秒，可选；id 可选。
///
/// 输出：**只**展示告警统计（总览 / 按类型 / 按月）。非告警只汇总成"已过滤"计数。
library;

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:smsmanager/models/alert.dart';
import 'package:smsmanager/services/ccb_parser.dart';

void main(List<String> args) async {
  final input = (args.isNotEmpty && args[0] != '-')
      ? await File(args[0]).readAsString()
      : await stdin.transform(utf8.decoder).join();

  final alerts = <SmsAlert>[];
  int filteredCount = 0;
  int totalLines = 0;
  int parseErrors = 0;

  for (final raw in input.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    totalLines++;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (e) {
      parseErrors++;
      continue;
    }

    final sender = (json['sender'] as String?) ?? '';
    final body = (json['body'] as String?) ?? '';
    final id = (json['id'] as int?) ?? totalLines;
    final dateMs = (json['date'] as int?);

    // 只关心告警：非告警直接丢弃，不进入 alerts list。
    // 丢弃的短信在内存里只活到本次循环结束（局部变量 m 出作用域即 GC 候选），
    // 不写文件、不写日志、不进入任何 UI / 状态。
    if (!CcbParser.isAlertCandidate(body)) {
      filteredCount++;
      continue;
    }

    alerts.add(
      CcbParser.parse(
        id: id,
        sender: sender,
        body: body,
        receivedAt: dateMs != null
            ? DateTime.fromMillisecondsSinceEpoch(dateMs)
            : DateTime.now(),
      ),
    );
  }

  _printReport(alerts, filteredCount, totalLines, parseErrors);
}

void _printReport(
  List<SmsAlert> alerts,
  int filteredCount,
  int totalLines,
  int parseErrors,
) {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('  建行告警 - 历史短信分析报告');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');
  print('总览');
  print('  输入短信        ${totalLines.toString().padLeft(4)} 条');
  print('  解析失败        ${parseErrors.toString().padLeft(4)} 条');
  print('  非告警（已过滤）  ${filteredCount.toString().padLeft(4)} 条');
  print('  纳入告警        ${alerts.length.toString().padLeft(4)} 条');
  print('');

  if (alerts.isEmpty) {
    print('(无告警数据)');
    return;
  }

  print('按告警类型');
  final byType = <AlertType, List<SmsAlert>>{};
  for (final a in alerts) {
    byType.putIfAbsent(a.type, () => []).add(a);
  }
  for (final type in AlertType.values) {
    final items = byType[type];
    if (items == null || items.isEmpty) continue;
    final total = items.fold<double>(0, (sum, a) => sum + (a.amount ?? 0));
    print('  ${type.label.padRight(8)} ${items.length.toString().padLeft(4)} 笔   ¥${total.toStringAsFixed(2)}');
  }
  print('');

  print('按月聚合');
  final byMonth = <String, List<SmsAlert>>{};
  for (final a in alerts) {
    final key = '${a.receivedAt.year}-${a.receivedAt.month.toString().padLeft(2, "0")}';
    byMonth.putIfAbsent(key, () => []).add(a);
  }
  final months = byMonth.keys.toList()..sort();
  for (final m in months) {
    final items = byMonth[m]!;
    final income = items
        .where((a) => !a.type.isExpense)
        .fold<double>(0, (sum, a) => sum + (a.amount ?? 0));
    final expense = items
        .where((a) => a.type.isExpense)
        .fold<double>(0, (sum, a) => sum + (a.amount ?? 0));
    print('  $m  ${items.length.toString().padLeft(4)} 笔   收入 ¥${income.toStringAsFixed(2).padLeft(10)}   支出 ¥${expense.toStringAsFixed(2).padLeft(10)}');
  }
}