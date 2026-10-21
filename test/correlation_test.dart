// 关联分析 / 向量库单元测试（v0.8）
//
// 验证：
//   1. EmbeddingService：确定性、相似文本相似度高于不相似文本
//   2. VectorStore：topK 排序、excludeId、持久化 roundtrip
//   3. CorrelationService：首次 / 复发 / 高频 / 风暴 判定

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smsmanager/models/alert.dart';
import 'package:smsmanager/services/correlation_service.dart';
import 'package:smsmanager/services/embedding_service.dart';
import 'package:smsmanager/services/object_key.dart';
import 'package:smsmanager/services/vector_store.dart';
import 'package:smsmanager/state/alert_list_provider.dart';

SmsAlert _alert(
  int id,
  String body, {
  DateTime? at,
  AlertType type = AlertType.systemAlert,
  AlertSeverity severity = AlertSeverity.critical,
}) {
  return SmsAlert(
    id: id,
    sender: '95533',
    body: body,
    receivedAt: at ?? DateTime(2026, 10, 15, 12, 0),
    type: type,
    severity: severity,
  );
}

void main() {
  group('extractAlertObjectKey（真实告警正文格式）', () {
    test('调度作业：调度域前缀 → 取引号作业名', () {
      expect(
        extractAlertObjectKey(
          "【建设银行】主要'五级'告警：云化数仓-数据应用'B1'_作业未执行结束:调度域：BDH ,"
          "'ODAP_MPP_NGHWDATA_F_OS_CL_SIGIR_CP_ETL_DAY_DC0140000'超时未结束,调度日期:20250226",
        ),
        'ODAP_MPP_NGHWDATA_F_OS_CL_SIGIR_CP_ETL_DAY_DC0140000',
      );
    });

    test('聚合作业告警：概要信息里同样有 调度域+作业名', () {
      expect(
        extractAlertObjectKey(
          "【建设银行】主要'五级'告警：聚合告警，云化数仓-数据应用'B1'_作业未开始执行:"
          "一分钟内发生24条告警,告警概要信息'事件内容~发生时间':调度域：BDH ,"
          "'ODAP_MPP_NGHWADWETLDATA_R209_NG_STD_SMBSN_ACC_INFO_ETL_DAY_DB0080000'超时未调起",
        ),
        'ODAP_MPP_NGHWADWETLDATA_R209_NG_STD_SMBSN_ACC_INFO_ETL_DAY_DB0080000',
      );
    });

    test('无调度域的变体：引号里的作业代号', () {
      expect(
        extractAlertObjectKey(
          "【建设银行】次要'六级'告警： 云化数仓-数据应用'B1'_作业执行超时:'D2'"
          "'N-P9EIL:企业级信息应用计算子系统' 'ADWNG_DIM_NG_SRC_CST_NUM_REF_H_ADW_NGADWDATA_GPMPP_ETL_000000000'作业运行时长超时",
        ),
        'ADWNG_DIM_NG_SRC_CST_NUM_REF_H_ADW_NGADWDATA_GPMPP_ETL_000000000',
      );
    });

    test('主机告警：冒号后主机名', () {
      expect(
        extractAlertObjectKey(
          "【建设银行】主要'五级'告警：云化数仓-数据应用'B1'_ping状态:"
          "wn4mpaadbcsg568,Linux_ping状态已达到1 , 连续4次等于阈值1.0",
        ),
        'wn4mpaadbcsg568',
      );
      expect(
        extractAlertObjectKey(
          "【建设银行】主要'五级'告警：云化数仓-数据应用'B1'_ping状态:"
          "n110paae0hd3008.ksc.com,Linux_ping状态已达到1",
        ),
        'n110paae0hd3008.ksc.com',
      );
    });

    test('聚合设备告警：概要信息冒号后的主机名', () {
      expect(
        extractAlertObjectKey(
          "【建设银行】主要'五级'告警：聚合告警：云化数仓-数据应用'B1'_磁盘使用率:"
          "1分钟内发生6条告警,告警概要信息'设备名称~事件内容~发生时间':wn19odaetap3001~Linux_磁盘使用率",
        ),
        'wn19odaetap3001',
      );
    });

    test('作业流名称（NEDP/流计算类）', () {
      expect(
        extractAlertObjectKey(
          "【建设银行】次要'六级'告警：云化数仓-数据应用，告警信息:'技术栈:x86，所属区域:武汉'"
          "自用''组件：流计算，'作业实例执行失败' 项目名称:PAPP 作业流名称:job_tp01_prvt_cst_intdy_txn_tag_r01_a_r_hudi2ck",
        ),
        'job_tp01_prvt_cst_intdy_txn_tag_r01_a_r_hudi2ck',
      );
    });

    test('工单提醒 → 工单号', () {
      expect(
        extractAlertObjectKey(
          '【建设银行】数据湖管理系统 DL 应用可研工单_SR26090200775_处理即将逾期提醒',
        ),
        'SR26090200775',
      );
    });

    test('工单委托 → 申请人', () {
      expect(
        extractAlertObjectKey(
          '【建设银行】唐鑫申请将待办工单委托给您，该委托已生效',
        ),
        '唐鑫的委托',
      );
    });

    test('无对象结构 → 系统代号兜底', () {
      expect(
        extractAlertObjectKey("【建设银行】主要'五级'告警：数据应用'B1'_TiKV 空间超标"),
        'B1',
      );
    });
  });

  group('EmbeddingService', () {
    test('同一文本生成相同向量（确定性，可持久化）', () {
      final a = EmbeddingService.embed("告警：'B1'_TiKV 空间使用率超标");
      final b = EmbeddingService.embed("告警：'B1'_TiKV 空间使用率超标");
      for (var i = 0; i < EmbeddingService.dim; i++) {
        expect(a[i], b[i]);
      }
    });

    test('相似文本相似度显著高于不相似文本', () {
      final q = EmbeddingService.embed("告警：'B1'_TiKV 空间使用率 95% 超标");
      final similar = EmbeddingService.embed("告警：'B1'_TiKV 空间使用率 87% 超标");
      final different = EmbeddingService.embed("工单 #12345 已派发给您，请尽快处理");
      final sSimilar = EmbeddingService.cosine(q, similar);
      final sDifferent = EmbeddingService.cosine(q, different);
      expect(sSimilar, greaterThan(0.8));
      expect(sSimilar, greaterThan(sDifferent));
    });

    test('数字归一化：不同百分比不失真', () {
      final a = EmbeddingService.embed('CPU 使用率 95% 超标');
      final b = EmbeddingService.embed('CPU 使用率 12% 超标');
      expect(EmbeddingService.cosine(a, b), greaterThan(0.9));
    });
  });

  group('VectorStore', () {
    test('topK 按相似度降序且排除自身', () {
      final store = VectorStore();
      final v1 = EmbeddingService.embed("告警：'B1'_TiKV 空间使用率超标");
      final v2 = EmbeddingService.embed("告警：'B2'_TiKV 空间使用率超标");
      final v3 = EmbeddingService.embed('工单已派发');
      store.upsert(1, v1);
      store.upsert(2, v2);
      store.upsert(3, v3);

      final hits = store.topK(v1, k: 5, excludeId: 1);
      expect(hits.first.id, 2);
      expect(hits.any((h) => h.id == 1), false);
      expect(hits.first.score, greaterThan(hits.last.score));
    });

    test('持久化 roundtrip', () async {
      final file = File(
        '${Directory.systemTemp.path}/ccb_vec_test_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      final store = VectorStore();
      store.upsert(1, EmbeddingService.embed('测试告警 A'));
      store.upsert(2, EmbeddingService.embed('测试告警 B'));
      await store.saveTo(file);

      final loaded = VectorStore();
      await loaded.loadFrom(file);
      expect(loaded.size, 2);
      expect(
        EmbeddingService.cosine(loaded.vectorOf(1)!, store.vectorOf(1)!),
        closeTo(1.0, 1e-6),
      );
      await file.delete();
    });
  });

  group('CorrelationService 判定', () {
    final keyOf = AlertListProvider.extractObjectKey;

    VectorStore storeOf(List<SmsAlert> alerts) {
      final s = VectorStore();
      for (final a in alerts) {
        s.upsert(a.id, EmbeddingService.embed(a.body));
      }
      return s;
    }

    test('无历史 → 首次出现', () {
      final target = _alert(1, "主要'五级'告警：数据应用'B1'_TiKV 空间超标");
      final r = CorrelationService.analyze(
        target: target,
        all: [target],
        store: storeOf([target]),
        objectKeyOf: keyOf,
      );
      expect(r.verdict, CorrelationVerdict.firstSeen);
      expect(r.objectKey, 'B1');
      expect(r.sameObjectTotal, 1);
    });

    test('同对象历史 → 复发 + 距上次间隔', () {
      final t = DateTime(2026, 10, 15, 12, 0);
      final prev = _alert(1, "主要'五级'告警：数据应用'B1'_TiKV 空间超标",
          at: t.subtract(const Duration(hours: 6)));
      final target = _alert(2, "主要'五级'告警：数据应用'B1'_TiKV 空间超标", at: t);
      final all = [target, prev];
      final r = CorrelationService.analyze(
        target: target,
        all: all,
        store: storeOf(all),
        objectKeyOf: keyOf,
      );
      expect(r.verdict, CorrelationVerdict.recurring);
      expect(r.sameObjectTotal, 2);
      expect(r.lastSeenBefore, prev.receivedAt);
    });

    test('7 天内高频 → 高频复发', () {
      final t = DateTime(2026, 10, 15, 12, 0);
      final all = <SmsAlert>[
        _alert(99, "主要'五级'告警：数据应用'B1'_TiKV 空间超标", at: t),
        for (var i = 0; i < 10; i++)
          _alert(i, "主要'五级'告警：数据应用'B1'_TiKV 空间超标",
              at: t.subtract(Duration(hours: i + 1))),
      ];
      final r = CorrelationService.analyze(
        target: all.first,
        all: all,
        store: storeOf(all),
        objectKeyOf: keyOf,
      );
      expect(r.verdict, CorrelationVerdict.frequent);
      expect(r.sameObject7d, 11);
    });

    test('±30 分钟内 ≥3 条其他告警 → 告警风暴', () {
      final t = DateTime(2026, 10, 15, 12, 0);
      final target = _alert(1, "主要'五级'告警：数据应用'B1'_TiKV 空间超标", at: t);
      final all = <SmsAlert>[
        target,
        _alert(2, "次要'六级'告警：'B2'_作业执行超时", at: t.subtract(const Duration(minutes: 5))),
        _alert(3, "告警：主机 wn1001 连接异常", at: t.add(const Duration(minutes: 10))),
        _alert(4, "业务告警：'ODAP_JOB1' 失败率超标", at: t.subtract(const Duration(minutes: 20))),
      ];
      final r = CorrelationService.analyze(
        target: target,
        all: all,
        store: storeOf(all),
        objectKeyOf: keyOf,
      );
      expect(r.verdict, CorrelationVerdict.storm);
      expect(r.burst.length, 3);
    });

    test('季度分布：跨年度周期性告警可识别', () {
      final t = DateTime(2026, 9, 30, 2, 0); // Q3 季末
      final target = _alert(1, "主要'五级'告警：数据应用'B1'_TiKV 空间超标", at: t);
      final all = <SmsAlert>[
        target,
        _alert(2, "主要'五级'告警：数据应用'B1'_TiKV 空间超标",
            at: DateTime(2026, 6, 30, 3, 0)), // 今年 Q2 季末
        _alert(3, "主要'五级'告警：数据应用'B1'_TiKV 空间超标",
            at: DateTime(2025, 9, 30, 1, 0)), // 去年 Q3 季末
        _alert(4, "主要'五级'告警：数据应用'B1'_TiKV 空间超标",
            at: DateTime(2024, 12, 31, 22, 0)), // 前年 Q4 年末
      ];
      final r = CorrelationService.analyze(
        target: target,
        all: all,
        store: storeOf(all),
        objectKeyOf: keyOf,
      );
      expect(r.sameObjectByQuarter['2026Q3'], 1);
      expect(r.sameObjectByQuarter['2026Q2'], 1);
      expect(r.sameObjectByQuarter['2025Q3'], 1);
      expect(r.sameObjectByQuarter['2024Q4'], 1);
      expect(r.sameObjectYears, [2026, 2025, 2024]);
      // 跨年度复发 → 判定为 recurring（总量 >1 且未达高频阈值）
      expect(r.verdict, CorrelationVerdict.recurring);
    });

    test('向量相似能召回不同对象的同类告警', () {
      final t = DateTime(2026, 10, 15, 12, 0);
      final target = _alert(1, "主要'五级'告警：数据应用'B1'_TiKV 空间使用率超标", at: t);
      final similarObj = _alert(2, "主要'五级'告警：数据应用'B2'_TiKV 空间使用率超标",
          at: t.subtract(const Duration(days: 1)));
      final unrelated = _alert(3, '工单 #12345 已派发，请尽快处理',
          at: t.subtract(const Duration(days: 1)), type: AlertType.opsTask);
      final all = [target, similarObj, unrelated];
      final r = CorrelationService.analyze(
        target: target,
        all: all,
        store: storeOf(all),
        objectKeyOf: keyOf,
      );
      // B1/B2 是不同对象但同一类问题 → 向量相似应把 B2 排第一
      expect(r.similar.first.alert.id, 2);
      expect(r.similar.first.score, greaterThan(0.8));
    });
  });
}
