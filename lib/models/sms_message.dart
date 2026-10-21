/// 通用短信分类模型
///
/// 每条 [SmsMessage] 对应手机收件箱里的一条短信，经过 [SmsClassifier]
/// 分类后打上 [SmsCategory] 标签，并附带针对该分类的处理建议。
library;

/// 短信分类
enum SmsCategory {
  /// 账务类：消费 / 转账 / 还款 / 工资等资金流水通知
  finance,

  /// 重要紧急：安全风险、逾期催收、紧急通知等需要立刻处理的内容
  urgent,

  /// 待办类：快递取件、预约、会议、账单到期等有时效性但不紧急的事项
  todo,

  /// 垃圾/营销：广告、推广、诈骗嫌疑短信
  spam,

  /// 其他：未命中任何规则的普通短信（验证码等）
  other,
}

extension SmsCategoryX on SmsCategory {
  /// 中文显示名
  String get label {
    switch (this) {
      case SmsCategory.finance:
        return '账务';
      case SmsCategory.urgent:
        return '重要紧急';
      case SmsCategory.todo:
        return '待办';
      case SmsCategory.spam:
        return '垃圾';
      case SmsCategory.other:
        return '其他';
    }
  }

  /// 处理建议文案（展示给用户）
  String get suggestion {
    switch (this) {
      case SmsCategory.finance:
        return '已帮您完成记账';
      case SmsCategory.urgent:
        return '重要，请紧急处理';
      case SmsCategory.todo:
        return '已帮您加入待办事项';
      case SmsCategory.spam:
        return '垃圾短信，建议忽略';
      case SmsCategory.other:
        return '普通通知，无需处理';
    }
  }
}

/// 单条短信（已分类）
class SmsMessage {
  /// Android SMS DB id（用于去重 / 标记已读）
  final int id;

  /// 发送方号码 / 名称
  final String sender;

  /// 短信全文
  final String body;

  /// 接收时间
  final DateTime receivedAt;

  /// 分类结果
  final SmsCategory category;

  /// 分类置信度（0~1，规则命中为 1.0，向量兜底为相似度分值）
  final double confidence;

  /// 是否已读
  final bool read;

  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.category,
    this.confidence = 1.0,
    this.read = false,
  });

  SmsMessage copyWith({bool? read}) {
    return SmsMessage(
      id: id,
      sender: sender,
      body: body,
      receivedAt: receivedAt,
      category: category,
      confidence: confidence,
      read: read ?? this.read,
    );
  }
}
