// 告警持久化库单元测试（v0.9 — 全量历史 + 增量同步）
//
// 验证：
//   1. merge 按短信 id 去重，重复合并不翻倍
//   2. lastSyncMs 推进到最新告警时间
//   3. 持久化 roundtrip：存盘后读回数据一致，且重新跑 parser

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smsmanager/models/alert.dart';
import 'package:smsmanager/services/alert_store.dart';

SmsAlert _a(int id, DateTime at, [String? body]) {
  return SmsAlert(
    id: id,
    sender: '95533',
    body: body ?? "主要'五级'告警：数据应用'B1'_TiKV 空间超标",
    receivedAt: at,
    type: AlertType.systemAlert,
    severity: AlertSeverity.critical,
  );
}

void main() {
  group('AlertStore', () {
    test('merge 去重：同一 id 重复合并不翻倍', () {
      final s = AlertStore();
      final a1 = _a(1, DateTime(2026, 10, 15, 12));
      final a2 = _a(2, DateTime(2026, 10, 15, 13));
      expect(s.merge([a1, a2]), 2);
      expect(s.merge([a1, a2]), 0); // 重复
      expect(s.size, 2);
    });

    test('lastSyncMs 推进到最新告警时间', () {
      final s = AlertStore();
      final t1 = DateTime(2026, 10, 15, 12);
      final t2 = DateTime(2026, 10, 15, 18);
      s.merge([_a(1, t1)]);
      expect(s.lastSyncMs, t1.millisecondsSinceEpoch);
      s.merge([_a(2, t2)]);
      expect(s.lastSyncMs, t2.millisecondsSinceEpoch);
      // 合入更早的告警不后退游标
      s.merge([_a(3, DateTime(2025, 1, 1))]);
      expect(s.lastSyncMs, t2.millisecondsSinceEpoch);
      expect(s.size, 3);
    });

    test('all 按时间倒序', () {
      final s = AlertStore();
      s.merge([
        _a(1, DateTime(2024, 3, 31)),
        _a(2, DateTime(2026, 10, 15)),
        _a(3, DateTime(2025, 6, 30)),
      ]);
      final list = s.all;
      expect(list.map((a) => a.id).toList(), [2, 3, 1]);
    });

    test('持久化 roundtrip：存盘读回一致且重新解析类型/严重度', () async {
      final file = File(
        '${Directory.systemTemp.path}/ccb_store_test_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      final s = AlertStore();
      s.merge([
        _a(1, DateTime(2025, 12, 31, 23, 0),
            "主要'五级'告警：数据应用'B1'_TiKV 空间超标"),
        _a(2, DateTime(2026, 10, 15, 8, 0), '工单 #12345 已派发给您'),
      ]);
      await s.saveTo(file);

      final loaded = AlertStore();
      await loaded.loadFrom(file);
      expect(loaded.size, 2);
      expect(loaded.lastSyncMs, s.lastSyncMs);
      final a1 = loaded.all.lastWhere((a) => a.id == 1);
      expect(a1.severity, AlertSeverity.critical);
      final a2 = loaded.all.firstWhere((a) => a.id == 2);
      expect(a2.severity, AlertSeverity.ticket); // 读回时重新 parse
      await file.delete();
    });

    test('文件不存在 → 空库，不报错', () async {
      final s = AlertStore();
      await s.loadFrom(File('${Directory.systemTemp.path}/ccb_store_nonexistent.json'));
      expect(s.size, 0);
      expect(s.lastSyncMs, 0);
    });
  });
}
