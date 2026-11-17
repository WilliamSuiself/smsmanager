/// 告警短信解析器（v0.6 — 通用短信汇聚）
///
/// 收录三类：
/// 1. 运维 / 业务告警（告警关键词命中）
/// 2. **账户变动**（消费 / 转账 / 到账 等——单独分类，不再丢弃）
/// 3. 营销 / 骚扰类仍然过滤（积分 / 优惠 / 理财推荐等）
library;

import '../models/alert.dart';

class CcbParser {
  CcbParser._();

  // ──────────────────────────────────────────────────────────────
  // 关键词集合
  // ──────────────────────────────────────────────────────────────

  /// 营销 / 骚扰关键字（任一命中 → 过滤，即使命中账户变动关键词）
  static const Set<String> _marketingKeywords = {
    // 营销
    '积分', '抽奖', '商城', '兑换', '优惠', '促销', '礼品',
    '优惠券', '活动券', '推荐', '邀您', '尊享',
    // 投资 / 理财推荐
    '理财', '基金', '投资', '收益', '赎回', '申购', '到期',
    // 外汇 / 利率数据通知（非交易类）
    '外汇', '外币', '买入价', '卖出价', '汇率', '钞汇', '现钞', '现汇',
    '外汇买卖', '汇兑', '结售汇', '结汇', '售汇', '汇率牌价',
    'SOFR', 'ESTR', 'SONIA', 'TONAR', 'EONIA',
    '全量档期', '档期利率', '利率数据重复', '自动发布', '档期',
    '美元', '欧元', '英镑', '日元', '港币', '澳元', '加元', '瑞郎', '新加坡元',
  };

  /// 账户变动关键字（命中其一 → 归入「账户变动」类，不再丢弃）
  ///
  /// 涵盖：支付流水（消费 / 支出 / 转账 / 转入 / 转出 / 还款 / 入账 / 退款 /
  ///       工资 / 充值 / 提现 / 取现 / 支付 / 存入 / 汇入 / 到账 / 缴费）
  ///       卡 / 账户操作（绑定 / 解绑 / 激活 / 开户 / 销户 / 挂失）
  static const Set<String> _accountKeywords = {
    '消费', '支出', '转账', '转入', '转出', '还款', '已还',
    '入账', '退款', '退货', '工资', '充值', '提现', '取现',
    '支付', '存入', '汇入', '到账', '缴费',
    'POS', '扫码', '被扫',
    '绑定', '解绑', '激活', '开户', '销户', '挂失',
    '余额', '可用余额',
  };

  /// 强告警关键字（命中其一 → 才保留）
  ///
  /// 特征：系统运维 / 业务告警通知里常见的强关键词。
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

  /// 是否收录（通用短信汇聚）：
  /// 1. 告警类：命中告警关键词，且不含营销词
  /// 2. 账户变动类：命中账户关键词，且不含营销词（**不再丢弃**）
  /// 3. 其余（纯营销 / 骚扰）→ 丢弃
  static bool isAlertCandidate(String body) {
    if (_hasMarketingKeyword(body)) return false;
    return _hasAlertKeyword(body) || _hasAccountKeyword(body);
  }

  /// 是否为账户变动类短信（消费 / 转账 / 到账 等）
  static bool isAccountActivity(String body) =>
      !_hasMarketingKeyword(body) && _hasAccountKeyword(body);

  static bool _hasMarketingKeyword(String body) {
    for (final kw in _marketingKeywords) {
      if (!body.contains(kw)) continue;
      // 豁免：营销词与账户交易动词同时出现时，视为交易而非营销
      // （如「理财卡支出人民币323元」是真实交易，不是理财推荐）
      const tradeVerbs = {'消费', '支出', '转账', '入账', '还款', '退款', '工资',
        '充值', '提现', '取现', '支付', '存入', '汇入', '到账', '缴费'};
      final hasTradeVerb = tradeVerbs.any(body.contains);
      if (hasTradeVerb) continue;
      return true;
    }
    return false;
  }

  static bool _hasAccountKeyword(String body) {
    for (final kw in _accountKeywords) {
      if (body.contains(kw)) return true;
    }
    return false;
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
  /// 告警分级体系：主要 X 级 / 次要 X 级（X 通常为 5/6）
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

  // （旧 _hasNonAlertKeyword 已移除：账户变动不再过滤，营销过滤并入 _hasMarketingKeyword）

  static AlertType _detectType(String body) {
    // 账户变动优先（避免「支付异常」既是账户又含告警词的歧义——
    // 用户明确要求账户变动单独成类）
    if (isAccountActivity(body)) return AlertType.accountActivity;

    // 工单类
    if (body.contains('工单') || body.contains('任务') || body.contains('已派发')) {
      return AlertType.opsTask;
    }

    // 其余全部归「告警」（系统/业务/监控/异常同义合并——v0.7 分类精简）
    return AlertType.alert;
  }
}