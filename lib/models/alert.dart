/// 建行告警数据模型
///
/// 每条 [SmsAlert] 对应一条来自建行（或疑似建行）的短信，
/// 经过解析后拆解为：类型 / 金额 / 卡号后四位 / 余额 / 原始时间戳。
library;

/// 告警严重度（用户工作场景：建行系统运维告警）
enum AlertSeverity {
  /// 主要五级告警（红色，最高级）
  critical,

  /// 次要六级告警（黄色，次级）
  info,

  /// 工单 / 任务类
  ticket,

  /// 其他（含告警关键字但未识别严重度）
  unknown,
}

extension AlertSeverityX on AlertSeverity {
  String get label {
    switch (this) {
      case AlertSeverity.critical:
        return '主要五级';
      case AlertSeverity.info:
        return '次要六级';
      case AlertSeverity.ticket:
        return '工单';
      case AlertSeverity.unknown:
        return '其他';
    }
  }
}

/// 告警类型 — 用于 app UI 分组 + 报表统计
///
/// 重新设计：建行 = 用户工作单位，app 只显示系统运维 / 业务告警，
/// 不再处理任何个人支付类（消费 / 转账 / 还款 等已在 parser 过滤）。
enum AlertType {
  /// 系统告警 / 故障 / 宕机 / 中断
  systemAlert,

  /// 业务告警 / 风险预警 / 风险提示
  businessAlert,

  /// 监控告警 / 阈值超标 / 资源监控
  monitor,

  /// 异常 / 超时 / 失败率 / 可用率
  exception,

  /// 工单 / 任务 / 已派发 / 已分派
  opsTask,

  /// 兜底：含强告警关键字但分类不明确
  unknown,
}

extension AlertTypeX on AlertType {
  /// 中文显示名（UI 直接用）
  String get label {
    switch (this) {
      case AlertType.systemAlert:
        return '系统告警';
      case AlertType.businessAlert:
        return '业务告警';
      case AlertType.monitor:
        return '监控告警';
      case AlertType.exception:
        return '异常';
      case AlertType.opsTask:
        return '工单';
      case AlertType.unknown:
        return '告警';
    }
  }

  /// 是否支出类（用于决定金额颜色 / 列表分组）
  ///
  /// 在告警场景下不再有 "expense" 概念（告警无金额或金额只代表指标值）。
  /// 保留这个方法是为了不破坏 [AlertCard] 的渲染逻辑——所有告警统一用主色调显示。
  bool get isExpense => false;
}

/// 单条告警
class SmsAlert {
  /// Android SMS DB id（用于去重 / 标记已读）
  final int id;

  /// 发送方号码（如 "95533"）
  final String sender;

  /// 短信全文
  final String body;

  /// 接收时间（毫秒）
  final DateTime receivedAt;

  /// 解析后的告警类型
  final AlertType type;

  /// 严重度（主要五级 / 次要六级 / 工单 / 其他）
  final AlertSeverity severity;

  /// 涉及金额（人民币元）
  final double? amount;

  /// 卡号后四位（解析不到为 null）
  final String? cardLast4;

  /// 账户余额（解析不到为 null）
  final double? balance;

  const SmsAlert({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.type,
    required this.severity,
    this.amount,
    this.cardLast4,
    this.balance,
  });
}