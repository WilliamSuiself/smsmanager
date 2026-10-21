/// 账务短信解析器
///
/// 从常见银行 / 支付平台短信模板中尽力提取：金额、收支方向、对方户名、卡号后四位。
/// 国内银行/支付短信模板五花八门，这里覆盖最常见的几类写法，
/// 解析不到的字段留 null，原文始终保留供用户核对，不影响"已记账"这条消息本身的展示。
library;

import '../models/ledger_entry.dart';

class FinanceParser {
  FinanceParser._();

  /// 金额：¥123.45 / ￥123.45 / 123.45元 / RMB123.45
  static final RegExp _amountPattern = RegExp(
    r'[¥￥]\s?(\d+(?:,\d{3})*(?:\.\d{1,2})?)|(\d+(?:,\d{3})*(?:\.\d{1,2})?)\s?元',
  );

  /// 卡号后四位：尾号1234 / 末四位1234 / (1234)
  static final RegExp _cardLast4Pattern = RegExp(
    r'(?:尾号|末四位|后四位)\D{0,4}(\d{4})',
  );

  /// 支出类关键词
  static const Set<String> _expenseKeywords = {
    '消费', '支出', '转出', '还款', '已还', '支付', '扣款', '代扣', '缴费', '取现',
  };

  /// 收入类关键词
  static const Set<String> _incomeKeywords = {
    '工资', '入账', '退款', '转入', '存入', '汇入', '到账', '充值',
  };

  /// 对方户名/商户：'向XX转账' / '收款人:XX' / '商户:XX' / '于XX消费'
  static final List<RegExp> _counterpartyPatterns = [
    RegExp(r'(?:向|转给)([\u4e00-\u9fa5A-Za-z0-9]{2,20})(?:转账|转出|付款)'),
    RegExp(r'(?:商户|收款人|付款人)[：:]\s*([\u4e00-\u9fa5A-Za-z0-9]{2,20})'),
    RegExp(r'在([\u4e00-\u9fa5A-Za-z0-9]{2,20})(?:消费|支付)'),
  ];

  /// 从账务短信中解析出一条记账条目
  static LedgerEntry parse({
    required int messageId,
    required String body,
    required DateTime at,
  }) {
    final amount = _parseAmount(body);
    final direction = _parseDirection(body);
    final counterparty = _parseCounterparty(body);
    final cardLast4 = _cardLast4Pattern.firstMatch(body)?.group(1);

    return LedgerEntry(
      messageId: messageId,
      at: at,
      amount: amount,
      direction: direction,
      counterparty: counterparty,
      cardLast4: cardLast4,
      rawBody: body,
    );
  }

  static double? _parseAmount(String body) {
    final m = _amountPattern.firstMatch(body);
    if (m == null) return null;
    final raw = (m.group(1) ?? m.group(2))?.replaceAll(',', '');
    if (raw == null) return null;
    return double.tryParse(raw);
  }

  static TxDirection _parseDirection(String body) {
    final isExpense = _expenseKeywords.any(body.contains);
    final isIncome = _incomeKeywords.any(body.contains);
    if (isExpense && !isIncome) return TxDirection.expense;
    if (isIncome && !isExpense) return TxDirection.income;
    return TxDirection.unknown;
  }

  static String? _parseCounterparty(String body) {
    for (final p in _counterpartyPatterns) {
      final m = p.firstMatch(body);
      if (m != null) return m.group(1);
    }
    return null;
  }
}
