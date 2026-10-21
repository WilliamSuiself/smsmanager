/// 短信持久化库：所有分类过的短信都在这里留底。
///
/// 系统短信库会滚动淘汰，且单次查询数量受限，所以每条处理过的短信
/// 连同分类结果一起持久化到本地 JSON，不受系统短信库清理影响。
///
/// 存储格式（messages_store.json）：
///   {"lastSyncMs": 169..., "messages": [{"id":1,"sender":"...","body":"...",
///     "at":169...,"category":"finance","read":false}]}
library;

import 'dart:convert';
import 'dart:io';

import '../models/sms_message.dart';

class MessageStore {
  final Map<int, SmsMessage> _byId = {};

  /// 上次同步到的最新短信时间（epoch 毫秒），增量查询的游标
  int lastSyncMs = 0;

  int get size => _byId.length;

  /// 全部短信，时间倒序
  List<SmsMessage> get all {
    final list = _byId.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return list;
  }

  SmsMessage? byId(int id) => _byId[id];

  /// 合并一批短信（按短信 id 去重），返回新增条数。
  int merge(List<SmsMessage> messages) {
    var added = 0;
    for (final m in messages) {
      if (!_byId.containsKey(m.id)) {
        _byId[m.id] = m;
        added++;
      }
      final ms = m.receivedAt.millisecondsSinceEpoch;
      if (ms > lastSyncMs) lastSyncMs = ms;
    }
    return added;
  }

  /// 标记已读
  void markRead(int id) {
    final m = _byId[id];
    if (m != null) _byId[id] = m.copyWith(read: true);
  }

  /// 用新对象整体替换已存在的短信（用于拉黑后重新打标签等场景）
  void replace(SmsMessage message) {
    if (!_byId.containsKey(message.id)) return;
    _byId[message.id] = message;
  }

  // ──────────────────────────────────────────────
  // 持久化
  // ──────────────────────────────────────────────

  Future<void> loadFrom(File file) async {
    _byId.clear();
    lastSyncMs = 0;
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      lastSyncMs = (data['lastSyncMs'] as num?)?.toInt() ?? 0;
      for (final item in (data['messages'] as List? ?? [])) {
        final m = item as Map<String, dynamic>;
        final id = (m['id'] as num?)?.toInt();
        if (id == null) continue;
        _byId[id] = SmsMessage(
          id: id,
          sender: m['sender'] as String? ?? '',
          body: m['body'] as String? ?? '',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['at'] as num?)?.toInt() ?? 0,
          ),
          category: SmsCategory.values.firstWhere(
            (c) => c.name == m['category'],
            orElse: () => SmsCategory.other,
          ),
          confidence: (m['confidence'] as num?)?.toDouble() ?? 1.0,
          read: m['read'] as bool? ?? false,
        );
      }
    } catch (_) {
      _byId.clear();
      lastSyncMs = 0;
    }
  }

  Future<void> saveTo(File file) async {
    final messages = all;
    await file.writeAsString(
      jsonEncode({
        'lastSyncMs': lastSyncMs,
        'count': messages.length,
        'messages': [
          for (final m in messages)
            {
              'id': m.id,
              'sender': m.sender,
              'body': m.body,
              'at': m.receivedAt.millisecondsSinceEpoch,
              'category': m.category.name,
              'confidence': m.confidence,
              'read': m.read,
            },
        ],
      }),
    );
  }
}
