/// 建行短信解析器（v0.5 — 工作单位告警导向）
///
/// 用户场景：建行 = 工作单位，不是个人银行。
/// app 只显示**运维 / 业务告警**类短信，
/// 任何与个人支付 / 账户 / 营销 / 外汇相关的短信一律丢弃。
library;

import '../models/alert.dart';

class CcbParser {
  CcbParser._();

  // ──────────────────────────────────────────────────────────────
  // 关键词集合
  // ──────────────────────────────────────────────────────────────

  /// 非告警关键字（任一命中 → 过滤）
  ///
  /// 涵盖：
  /// - 个人支付（消费 / 支出 / 转账 / 转入 / 转出 / 还款 / 入账 / 退款 / 退货 /
  ///             工资 / 充值 / 提现 / 取现 / 支付 / 存入 / 汇入 / 到账 / 缴费 / 党费 /
  ///             POS / 扫码 / 被扫 / 网联 / 银联）
  /// - 卡种（储蓄卡 / 信用卡 / 龙卡 / 理财卡 / 尾号 / 末四位）
  /// - 账户安全（登录提醒 / 密码 / 地址变更 / 开户 / 销户 / 激活 / 绑定 / 解绑 /
  ///             签约 / 客户等级 / 星级 / 回访 / 生日）
  /// - 风控（临时额度 / 额度调整 / 境外使用 / 境外网站）
  /// - 营销（积分 / 抽奖 / 商城 / 兑换 / 优惠 / 促销 / 礼品 / 推荐 / 邀您 / 尊享）
  /// - 投资（理财 / 基金 / 投资 / 收益 / 赎回 / 申购 / 到期）
  /// - 外汇（外汇 / 外币 / 买入价 / 卖出价 / 汇率 / 钞汇 / 现钞 / 现汇 /
  ///        外汇买卖 / 汇兑 / 结售汇 / 汇率牌价）
  static const Set<String> _nonAlertKeywords = {
    // 支付 / 资金流水
    '消费', '支出', '转账', '转入', '转出', '还款', '已还',
    '入账', '退款', '退货', '工资', '充值', '提现', '取现',
    '支付', '存入', '汇入', '到账', '缴费', '党费',
    'POS', '扫码', '被扫', '网联', '银联',
    // 个人账户 / 卡种
    '储蓄卡', '信用卡', '龙卡', '理财卡',
    '尾号', '账号末四位', '卡号末四位', '末四位',
    // 账户安全 / 信息变更
    '登录提醒', '登录通知', '密码', '地址变更', '开户', '销户', '激活',
    '绑定', '解绑', '签约', '客户等级', '星级', '回访', '生日',
    // 风控
    '临时额度', '额度调整', '额度最高', '境外使用', '境外网站',
    // 营销
    '积分', '抽奖', '商城', '兑换', '优惠', '促销', '礼品',
    '优惠券', '活动券', '推荐', '邀您', '尊享',
    // 投资
    '理财', '基金', '投资', '收益', '赎回', '申购', '到期',
    // 外汇（含利率档期、SOFR/ESTR/SONIA 基准利率等非交易类数据通知）
    '外汇', '外币', '买入价', '卖出价', '汇率', '钞汇', '现钞', '现汇',
    '外汇买卖', '汇兑', '结售汇', '结汇', '售汇', '汇率牌价',
    // 外汇基准利率档期数据通知（误发 → 视为非告警）
    'SOFR', 'ESTR', 'SONIA', 'TONAR', 'EONIA',
    '全量档期', '档期利率', '利率数据重复', '自动发布',
    '生效的', '档期',
    // 国际通用外币代号（避免外汇类短信混入）
    '美元', '欧元', '英镑', '日元', '港币', '澳元', '加元', '瑞郎', '新加坡元',
  };

  /// 强告警关键字（命中其一 → 才保留）
  ///
  /// 特征：建行系统运维 / 业务告警通知里常见的强关键词。
  static const Set<String> _alertKeywords = {
    '告警', '警告', '报警', '异常', '监控', '阈值', '超标',
    '系统告警', '业务告警', '运维告警', '风险预警', '风险提示',
    '故障', '宕机', '中断', '超时', '失败率', '可用率',
    '不可用', '降级', '熔断', '连接异常',
    'CPU', '内存', '磁盘', 'IO', '带宽', '流量',
    '接口', '主机', '服务', '数据库', '服务器', '网络',
    '部署', '上线', '回滚', '发版', '升级',
    '工单', '任务', '处理中', '已派发', '已分派',
    '延迟', '积压', '堆积',
  };

  // ──────────────────────────────────────────────────────────────
  // 公开方法
  // ──────────────────────────────────────────────────────────────

  /// 是否为告警短信
  ///
  /// 判定规则（用户需求：只看建行 = 工作单位的系统告警通知）：
  /// 1. 必须命中 `_alertKeywords` 中至少一个（强告警门槛）
  /// 2. **不**能命中 `_nonAlertKeywords` 中任何一个（个人支付 / 账户 / 营销 / 外汇）
  ///
  /// 返回 false 的短信在内存中只活到本次循环结束，不落盘 / 不写日志 / 不进 UI。
  static bool isAlertCandidate(String body) {
    if (!_hasAlertKeyword(body)) return false;
    if (_hasNonAlertKeyword(body)) return false;
    return true;
  }

  /// 主解析入口
  static SmsAlert parse({
    required int id,
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    return SmsAlert(
      id: id,
      sender: sender,
      body: body,
      receivedAt: receivedAt,
      type: _detectType(body),
      severity: _detectSeverity(body),
    );
  }

  /// 严重度识别
  ///
  /// 建行告警体系：主要 X 级 / 次要 X 级（X 通常为 5/6）
  /// - 主要五级：critical（红色）
  /// - 次要六级：info（黄色）
  /// - 工单：ticket（蓝色）
  static AlertSeverity _detectSeverity(String body) {
    if (body.contains('工单') || body.contains('委托')) {
      return AlertSeverity.ticket;
    }
    if (body.contains('主要') || body.contains('五级')) {
      return AlertSeverity.critical;
    }
    if (body.contains('次要') || body.contains('六级')) {
      return AlertSeverity.info;
    }
    return AlertSeverity.unknown;
  }

  // ──────────────────────────────────────────────────────────────
  // 内部方法
  // ──────────────────────────────────────────────────────────────

  static bool _hasAlertKeyword(String body) {
    for (final kw in _alertKeywords) {
      if (body.contains(kw)) return true;
    }
    return false;
  }

  static bool _hasNonAlertKeyword(String body) {
    for (final kw in _nonAlertKeywords) {
      if (body.contains(kw)) return true;
    }
    return false;
  }

  static AlertType _detectType(String body) {
    // isAlertCandidate 已经过滤掉所有支付 / 个人账户 / 营销 / 外汇类短信。
    // 进入 _detectType 的全是真正的告警短信（建行系统运维 / 业务告警）。
    // 这里识别告警的细分类型，便于 UI 分组展示。

    // 系统告警：含强类型标签，或含资源关键字（CPU/内存/服务器/数据库/接口 等）
    if (body.contains('系统告警') ||
        body.contains('运维告警') ||
        body.contains('故障') ||
        body.contains('宕机') ||
        body.contains('中断')) {
      return AlertType.systemAlert;
    }
    if (body.contains('业务告警') || body.contains('风险预警') || body.contains('风险提示')) {
      return AlertType.businessAlert;
    }
    if (body.contains('监控') || body.contains('阈值') || body.contains('超标')) {
      return AlertType.monitor;
    }
    if (body.contains('异常') ||
        body.contains('超时') ||
        body.contains('失败率') ||
        body.contains('可用率')) {
      return AlertType.exception;
    }
    if (body.contains('工单') || body.contains('任务') || body.contains('已派发')) {
      return AlertType.opsTask;
    }
    // 资源类关键词 + 含告警上下文 → 默认归系统告警
    const resourceKeys = ['CPU', '内存', '磁盘', 'IO', '带宽', '流量',
                           '接口', '主机', '数据库', '服务器', '网络',
                           '服务', '连接异常'];
    for (final kw in resourceKeys) {
      if (body.contains(kw)) return AlertType.systemAlert;
    }
    return AlertType.unknown;
  }
}