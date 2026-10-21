import 'package:flutter_test/flutter_test.dart';
import 'package:smsmanager/models/sms_message.dart';
import 'package:smsmanager/services/sms_classifier.dart';

void main() {
  group('SmsClassifier 规则分类', () {
    test('账务短信 → finance', () {
      const body = '您尾号1234的储蓄卡于今日15:20发生支出￥128.50，余额￥3,560.80';
      expect(SmsClassifier.classify(body), SmsCategory.finance);
    });

    test('安全风险短信 → urgent', () {
      const body = '您的账户检测到异常登录风险，请立即核实并修改密码';
      expect(SmsClassifier.classify(body), SmsCategory.urgent);
    });

    test('逾期催收短信 → urgent', () {
      const body = '您的信用卡账单已逾期，请尽快还款以免影响个人征信';
      expect(SmsClassifier.classify(body), SmsCategory.urgent);
    });

    test('快递取件短信 → todo', () {
      const body = '您的快递已到达小区驿站，请尽快凭取件码领取';
      expect(SmsClassifier.classify(body), SmsCategory.todo);
    });

    test('营销广告短信 → spam', () {
      const body = '双十一限时秒杀，全场五折，点击链接立即抢购';
      expect(SmsClassifier.classify(body), SmsCategory.spam);
    });

    test('命中黑名单号码 → 直接判为垃圾，不看内容', () {
      const body = '您的快递已到达驿站，请尽快取件';
      final category = SmsClassifier.classify(
        body,
        sender: '10086888',
        blacklist: {'10086888'},
      );
      expect(category, SmsCategory.spam);
    });

    test('验证码短信不会被误判为待办', () {
      const body = '您的验证码是123456，5分钟内有效，请勿泄露给他人';
      expect(SmsClassifier.classify(body), isNot(SmsCategory.todo));
    });

    test('无关键词命中的普通闲聊短信 → other', () {
      const body = '喂，晚上有空一起吃饭吗';
      expect(SmsClassifier.classify(body), SmsCategory.other);
    });

    test('urgent 与 finance 同时命中时 urgent 优先级更高', () {
      const body = '您的还款已逾期，请立即处理，涉嫌影响征信，账单金额128元';
      expect(SmsClassifier.classify(body), SmsCategory.urgent);
    });
  });
}
