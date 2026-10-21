import 'package:flutter_test/flutter_test.dart';
import 'package:smsmanager/models/ledger_entry.dart';
import 'package:smsmanager/services/finance_parser.dart';

void main() {
  group('FinanceParser', () {
    test('解析储蓄卡消费短信：金额 / 支出方向 / 卡号后四位', () {
      final entry = FinanceParser.parse(
        messageId: 1,
        body: '您尾号1234的储蓄卡于今日15:20发生支出￥128.50，余额￥3560.80',
        at: DateTime(2026, 1, 1),
      );
      expect(entry.amount, 128.50);
      expect(entry.direction, TxDirection.expense);
      expect(entry.cardLast4, '1234');
    });

    test('解析工资入账短信：金额 / 收入方向', () {
      final entry = FinanceParser.parse(
        messageId: 2,
        body: '代发工资￥8000.00已存入您的账户',
        at: DateTime(2026, 1, 1),
      );
      expect(entry.amount, 8000.00);
      expect(entry.direction, TxDirection.income);
    });

    test('解析商户消费短信：对方商户名', () {
      final entry = FinanceParser.parse(
        messageId: 3,
        body: '您在星巴克消费38.00元，感谢惠顾',
        at: DateTime(2026, 1, 1),
      );
      expect(entry.amount, 38.00);
      expect(entry.counterparty, '星巴克');
    });

    test('金额/对方信息都解析不到时，字段为 null 但保留原文', () {
      final entry = FinanceParser.parse(
        messageId: 4,
        body: '您的账户本月有一笔待确认的扣款记录',
        at: DateTime(2026, 1, 1),
      );
      expect(entry.amount, isNull);
      expect(entry.rawBody, contains('待确认的扣款记录'));
    });
  });
}
