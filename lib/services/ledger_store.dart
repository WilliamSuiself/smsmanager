/// 记账账本持久化（ledger_store.json）
library;

import 'dart:convert';
import 'dart:io';

import '../models/ledger_entry.dart';

class LedgerStore {
  final Map<int, LedgerEntry> _byMessageId = {};

  int get size => _byMessageId.length;

  /// 全部账本条目，时间倒序
  List<LedgerEntry> get all {
    final list = _byMessageId.values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  bool contains(int messageId) => _byMessageId.containsKey(messageId);

  /// 新增一条记账条目（按 messageId 去重），返回是否为新增。
  bool add(LedgerEntry entry) {
    if (_byMessageId.containsKey(entry.messageId)) return false;
    _byMessageId[entry.messageId] = entry;
    return true;
  }

  Future<void> loadFrom(File file) async {
    _byMessageId.clear();
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      for (final item in data) {
        final entry = LedgerEntry.fromJson(item as Map<String, dynamic>);
        _byMessageId[entry.messageId] = entry;
      }
    } catch (_) {
      _byMessageId.clear();
    }
  }

  Future<void> saveTo(File file) async {
    await file.writeAsString(jsonEncode(all.map((e) => e.toJson()).toList()));
  }
}
