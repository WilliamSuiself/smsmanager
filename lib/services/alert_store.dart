/// 告警持久化库：手机里出现过的每一条建行告警都在这里留底。
///
/// 为什么需要它：
/// - 手机系统短信库本身会滚动淘汰，且查询上限受限——只靠"读短信"拿不到完整历史。
/// - 运维告警需要跨季度 / 跨年度关联（季末批量、年末结息等周期性故障），
///   所以每条见过的告警都持久化到本地 JSON，永不淘汰。
///
/// 存储格式（alerts_store.json）：
///   {"lastSyncMs": 1729..., "alerts": [{"id":1,"sender":"95533","body":"...","at":1729...}]}
///
/// 类型 / 严重度不落盘——读取时重新跑 [CcbParser.parse]，
/// 解析规则升级后历史数据自动按新规则重算。
library;

import 'dart:convert';
import 'dart:io';

import '../models/alert.dart';
import 'ccb_parser.dart';

class AlertStore {
  final Map<int, SmsAlert> _byId = {};

  /// 上次同步到的最新短信时间（epoch 毫秒），增量查询的游标
  int lastSyncMs = 0;

  int get size => _byId.length;

  /// 全部告警，时间倒序
  List<SmsAlert> get all {
    final list = _byId.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return list;
  }

  /// 合并一批告警（按短信 id 去重），返回新增条数。
  /// 同时推进 [lastSyncMs] 到这批里最新的 receivedAt。
  int merge(List<SmsAlert> alerts) {
    var added = 0;
    for (final a in alerts) {
      if (!_byId.containsKey(a.id)) {
        _byId[a.id] = a;
        added++;
      }
      final ms = a.receivedAt.millisecondsSinceEpoch;
      if (ms > lastSyncMs) lastSyncMs = ms;
    }
    return added;
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
      for (final item in (data['alerts'] as List? ?? [])) {
        final m = item as Map<String, dynamic>;
        final id = (m['id'] as num?)?.toInt();
        final sender = m['sender'] as String? ?? '';
        final body = m['body'] as String? ?? '';
        final at = (m['at'] as num?)?.toInt() ?? 0;
        if (id == null) continue;
        _byId[id] = CcbParser.parse(
          id: id,
          sender: sender,
          body: body,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(at),
        );
      }
    } catch (_) {
      _byId.clear();
      lastSyncMs = 0;
    }
  }

  Future<void> saveTo(File file) async {
    final alerts = all;
    await file.writeAsString(
      jsonEncode({
        'lastSyncMs': lastSyncMs,
        'count': alerts.length,
        'alerts': [
          for (final a in alerts)
            {
              'id': a.id,
              'sender': a.sender,
              'body': a.body,
              'at': a.receivedAt.millisecondsSinceEpoch,
            },
        ],
      }),
    );
  }
}
