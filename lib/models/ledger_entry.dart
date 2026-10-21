/// 自动记账条目
///
/// 由 [FinanceParser] 从账务类短信（[SmsCategory.finance]）解析生成。
/// 金额 / 对方户名识别不到时对应字段为 null，仍保留原始短信供用户手动核对。
library;

/// 资金方向
enum TxDirection {
  /// 收入（工资 / 退款 / 转入 / 入账）
  income,

  /// 支出（消费 / 转出 / 还款 / 缴费）
  expense,

  /// 无法判断方向
  unknown,
}

class LedgerEntry {
  /// 关联的短信 id
  final int messageId;

  final DateTime at;

  /// 金额（元），解析失败为 null
  final double? amount;

  final TxDirection direction;

  /// 对方户名 / 商户（解析失败为 null）
  final String? counterparty;

  /// 卡号后四位（解析不到为 null）
  final String? cardLast4;

  /// 原始短信全文（供核对）
  final String rawBody;

  const LedgerEntry({
    required this.messageId,
    required this.at,
    required this.direction,
    required this.rawBody,
    this.amount,
    this.counterparty,
    this.cardLast4,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'at': at.millisecondsSinceEpoch,
        'amount': amount,
        'direction': direction.name,
        'counterparty': counterparty,
        'cardLast4': cardLast4,
        'rawBody': rawBody,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      messageId: (json['messageId'] as num).toInt(),
      at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
      amount: (json['amount'] as num?)?.toDouble(),
      direction: TxDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => TxDirection.unknown,
      ),
      counterparty: json['counterparty'] as String?,
      cardLast4: json['cardLast4'] as String?,
      rawBody: json['rawBody'] as String? ?? '',
    );
  }
}
