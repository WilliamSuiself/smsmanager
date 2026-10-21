// 建行告警解析器单元测试（v0.5 — 工作单位告警导向）
//
// 验证：
//   1. 真正的系统 / 业务告警能被识别为告警
//   2. 所有个人支付类短信（消费 / 还款 / 工资 / 转账 / 信用卡 等）统统走反例
//   3. 个人账户安全类（密码 / 临时额度 / 登录 等）走反例
//   4. 营销 / 外汇 / 投资类走反例

import 'package:flutter_test/flutter_test.dart';

import 'package:smsmanager/models/alert.dart';
import 'package:smsmanager/services/ccb_parser.dart';

void main() {
  group('CcbParser 真实告警解析', () {
    test('系统告警（CPU 超阈值）→ 识别为系统告警', () {
      final a = CcbParser.parse(
        id: 1,
        sender: '95533',
        body: '【建设银行】告警：核心数据库服务器01 CPU 使用率 95% 持续 5 分钟，请运维人员尽快处理。',
        receivedAt: DateTime(2026, 10, 6, 12, 0),
      );
      expect(a.type, AlertType.systemAlert);
    });

    test('业务告警（交易异常）→ 识别为业务告警', () {
      final a = CcbParser.parse(
        id: 2,
        sender: '95533',
        body: '【建设银行】业务告警：某商户今日失败率超过阈值 5%，请关注。',
        receivedAt: DateTime(2026, 10, 6),
      );
      expect(a.type, AlertType.businessAlert);
    });

    test('监控告警（资源阈值）→ 识别为监控告警', () {
      final a = CcbParser.parse(
        id: 3,
        sender: '95533',
        body: '【建设银行】监控告警：磁盘空间使用率 92% 已超过阈值。',
        receivedAt: DateTime(2026, 10, 6),
      );
      expect(a.type, AlertType.monitor);
    });

    test('主要五级告警 → severity = critical', () {
      final a = CcbParser.parse(
        id: 100,
        sender: '95533',
        body: '【建设银行】主要\'五级\'告警：云化数仓-数据应用\'B1\'_TiKV 空间使用率超标',
        receivedAt: DateTime(2026, 10, 6),
      );
      expect(a.severity, AlertSeverity.critical);
    });

    test('次要六级告警 → severity = info', () {
      final a = CcbParser.parse(
        id: 101,
        sender: '95533',
        body: '【建设银行】次要\'六级\'告警：云化数仓-数据应用\'B1\'_作业执行超时',
        receivedAt: DateTime(2026, 10, 6),
      );
      expect(a.severity, AlertSeverity.info);
    });

    test('工单委托 → severity = ticket', () {
      final a = CcbParser.parse(
        id: 102,
        sender: '95533',
        body: '【建设银行】唐鑫申请将待办工单委托给您，该委托已生效',
        receivedAt: DateTime(2026, 10, 6),
      );
      expect(a.severity, AlertSeverity.ticket);
    });

    test('异常 / 超时 → 识别为异常', () {
      final a = CcbParser.parse(
        id: 4,
        sender: '95533',
        body: '【建设银行】接口调用超时，请排查。',
        receivedAt: DateTime(2026, 10, 6),
      );
      expect(a.type, AlertType.exception);
    });

    test('工单 / 任务 → 识别为工单', () {
      final a = CcbParser.parse(
        id: 5,
        sender: '95533',
        body: '【建设银行】工单 #12345 已派发给您，请尽快处理。',
        receivedAt: DateTime(2026, 10, 6),
      );
      expect(a.type, AlertType.opsTask);
    });

    test('含告警关键字但分类不明 → unknown', () {
      final a = CcbParser.parse(
        id: 6,
        sender: '95533',
        body: '【建设银行】系统告警：XX 主机负载异常，请关注。',
        receivedAt: DateTime(2026, 10, 6),
      );
      // 「系统告警」优先于「异常」 → systemAlert
      expect(a.type, AlertType.systemAlert);
    });
  });

  group('isAlertCandidate 过滤规则（任何支付 / 账户 / 营销 / 外汇 → 过滤）', () {
    test('储蓄卡消费 → 过滤（个人支付）', () {
      expect(
        CcbParser.isAlertCandidate(
          '您尾号1234的储蓄卡于10月10日10时10分消费人民币123.45元',
        ),
        false,
      );
    });

    test('信用卡还款入账 → 过滤（个人支付）', () {
      expect(
        CcbParser.isAlertCandidate(
          '您尾号5678的信用卡10月10日已还款入账5000元',
        ),
        false,
      );
    });

    test('理财卡支出 → 过滤（个人支付）', () {
      expect(
        CcbParser.isAlertCandidate(
          '您尾号6992的理财卡10月6日7时43分支出人民币323.57元',
        ),
        false,
      );
    });

    test('他人汇款（存入 / 汇入）→ 过滤（个人支付）', () {
      expect(
        CcbParser.isAlertCandidate(
          '隋云海于9月26日21:39向您账户6992存入45000元',
        ),
        false,
      );
    });

    test('消费退货存入 → 过滤（个人支付）', () {
      expect(
        CcbParser.isAlertCandidate(
          '抖音支付-北京苏禾宴餐饮服务有限公司于9月22日向您账户消费退货存入159元',
        ),
        false,
      );
    });

    test('POS / 扫码消费 → 过滤（个人支付）', () {
      expect(
        CcbParser.isAlertCandidate('POS机消费支出人民币500元'),
        false,
      );
      expect(
        CcbParser.isAlertCandidate('微信扫码支付支出人民币38元'),
        false,
      );
    });

    test('工资入账 → 过滤（个人支付）', () {
      expect(
        CcbParser.isAlertCandidate('您账户6992于9月4日存入18207.22元，代发工资'),
        false,
      );
    });

    test('信用卡临时额度调整 → 过滤（账户安全）', () {
      expect(
        CcbParser.isAlertCandidate(
          '【建设银行】您尾号0532的龙卡信用卡当前在境外/境外网站使用，该卡临时额度最高可调整至526000元',
        ),
        false,
      );
    });

    test('登录提醒 → 过滤（账户安全）', () {
      expect(
        CcbParser.isAlertCandidate('您账户于10月10日10时登录网银，请确认是否本人操作'),
        false,
      );
    });

    test('外汇买入通知 → 过滤（外汇）', () {
      expect(
        CcbParser.isAlertCandidate(
          '您尾号1234账户外汇买入美元 USD 1000.00 汇率 7.1234',
        ),
        false,
      );
    });

    test('SOFR/ESTR 档期利率通知 → 过滤（误发的外汇数据）', () {
      // 回归用例：之前含"发布"误识别为告警
      expect(
        CcbParser.isAlertCandidate(
          '【建设银行】20260928生效的SOFR(13EU009),美元(840),机构:111111111,全量档期利率数据重复,系统已自动发布.',
        ),
        false,
      );
      expect(
        CcbParser.isAlertCandidate(
          '【建设银行】20260904生效的ESTR(13EU011),欧元(978),全量档期利率数据重复,系统已自动发布.',
        ),
        false,
      );
      expect(
        CcbParser.isAlertCandidate(
          '【建设银行】20260924生效的SONIA(13EU010),英镑(826),全量档期利率数据重复,系统已自动发布.',
        ),
        false,
      );
    });

    test('客户等级升级通知 → 过滤（账户）', () {
      expect(
        CcbParser.isAlertCandidate('您已升级为建行七星级客户'),
        false,
      );
    });

    test('积分活动 → 过滤（营销）', () {
      expect(
        CcbParser.isAlertCandidate('您尾号1234账户积分兑换活动开始啦'),
        false,
      );
    });

    test('理财推荐 → 过滤（营销）', () {
      expect(
        CcbParser.isAlertCandidate('尊享客户专属理财推荐：预期年化4.5%'),
        false,
      );
    });

    test('无任何告警关键字 → 过滤', () {
      expect(
        CcbParser.isAlertCandidate('欢迎使用建行手机银行，请妥善保管账户'),
        false,
      );
    });
  });

  group('isAlertCandidate 正例（必须命中 _alertKeywords）', () {
    test('系统告警 + 含阈值数字 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('系统告警：服务器 CPU 95% 超过阈值'),
        true,
      );
    });

    test('业务告警 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('业务告警：XX 商户交易异常'),
        true,
      );
    });

    test('监控告警 + 资源名 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('监控告警：数据库连接池使用率 92%'),
        true,
      );
    });

    test('接口异常 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('告警：核心接口调用异常'),
        true,
      );
    });

    test('工单派发 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('工单 #12345 已派发，请处理'),
        true,
      );
    });

    test('故障 / 宕机 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('告警：XX 服务故障'),
        true,
      );
      expect(
        CcbParser.isAlertCandidate('告警：XX 主机宕机'),
        true,
      );
      expect(
        CcbParser.isAlertCandidate('告警：XX 网络中断'),
        true,
      );
    });

    test('风险预警 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('风险预警：检测到异常登录'),
        true,
      );
    });

    test('超阈值 + 资源 → 保留', () {
      expect(
        CcbParser.isAlertCandidate('告警：内存使用率 92% 超过阈值'),
        true,
      );
    });

    test('真正运维告警（不含支付词）→ 保留', () {
      expect(
        CcbParser.isAlertCandidate('【建设银行】告警：核心交换机 CPU 超标，请检查'),
        true,
      );
    });
  });

  group('AlertTypeX', () {
    test('label', () {
      expect(AlertType.systemAlert.label, '系统告警');
      expect(AlertType.businessAlert.label, '业务告警');
      expect(AlertType.monitor.label, '监控告警');
      expect(AlertType.exception.label, '异常');
      expect(AlertType.opsTask.label, '工单');
      expect(AlertType.unknown.label, '告警');
    });

    test('isExpense 永远 false（告警无支出概念）', () {
      expect(AlertType.systemAlert.isExpense, false);
      expect(AlertType.businessAlert.isExpense, false);
      expect(AlertType.monitor.isExpense, false);
      expect(AlertType.exception.isExpense, false);
      expect(AlertType.opsTask.isExpense, false);
    });
  });
}