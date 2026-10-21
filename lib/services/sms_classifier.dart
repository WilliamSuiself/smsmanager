/// 通用短信分类器（纯本地，不联网）
///
/// 策略：
///   1. 发件人命中黑名单 → 直接判定垃圾（最高优先级，跳过内容分析）
///   2. 关键词规则匹配 → 按 [urgent > finance > spam > todo] 优先级取分数最高的分类
///   3. 规则没有任何命中 → 退化为向量相似度兜底：
///      用 [EmbeddingService] 把短信文本与内置的分类示例文本做余弦相似度，
///      取相似度最高且超过阈值的分类；否则归入 [SmsCategory.other]
///
/// 这套"规则为主 + 向量兜底"的方案完全在设备本地计算，不调用任何云端 AI 接口，
/// 符合"数据不出本地"的隐私承诺。
library;

import 'dart:typed_data';

import '../models/sms_message.dart';
import 'embedding_service.dart';

class SmsClassifier {
  SmsClassifier._();

  /// 向量兜底时的最低相似度阈值，低于此值一律归为 other
  static const double _similarityThreshold = 0.22;

  /// 金额信号：¥ / ￥ / 数字+元。真实场景里发现运维日志类长文本
  /// （大量数字、英文缩写、路径字符串）会在字符 n-gram 向量上和账务示例
  /// 产生虚假相似度，因此向量兜底命中"账务"时，必须有金额信号佐证，
  /// 否则一律退回 other，避免把非账务内容误记一笔账。
  static final RegExp _amountSignal = RegExp(r'[¥￥]|\d+(?:\.\d{1,2})?\s?元');

  /// 重要紧急：安全风险 / 催收逾期 / 停机断供 / 法律事务等需要立刻处理的内容
  static const Set<String> _urgentKeywords = {
    '异常登录', '安全提醒', '风险提示', '盗刷', '涉嫌', '违法', '冻结', '紧急',
    '立即处理', '逾期', '欠费', '停机', '断网', '限电', '停水', '催收',
    '法院', '诉讼', '传票', '开庭', '失信', '仲裁', '强制执行',
  };

  /// 账务类：资金流水通知，命中后交给 [FinanceParser] 进一步解析金额等字段
  static const Set<String> _financeKeywords = {
    '消费', '支出', '转账', '转入', '转出', '还款', '已还', '入账', '退款',
    '工资', '充值', '提现', '取现', '支付', '存入', '汇入', '到账', '扣款',
    '代扣', '余额', '账单', '还款日', '待还',
  };

  /// 待办类：有时效性但不紧急，适合加入待办列表
  static const Set<String> _todoKeywords = {
    '取件', '快递', '包裹', '预约', '会议', '面试', '体检', '续费', '签收',
    '挂号', '请于', '截止', '领取', '核酸', '提醒您', '到期', '确认',
  };

  /// 垃圾/营销：广告推广 / 诈骗嫌疑
  static const Set<String> _spamKeywords = {
    '优惠', '特价', '秒杀', '中奖', '抽奖', '点击链接', '回复td退订', '退订回t',
    '免费领取', '限时', '抢购', '助力', '砍价', '贷款额度', '白条', '借呗',
    '网贷', '私彩', '博彩', '股票内幕', '加微信', '扫码领取', '尊享特权',
    '最高可借', '无抵押', '低息',
  };

  /// 验证码一般无需加入待办（时效极短），单独识别避免被误判为待办
  static const Set<String> _verificationKeywords = {'验证码', '校验码'};

  /// 内置的分类示例文本（用于向量兜底，规则没有命中强关键词时使用）
  static final Map<SmsCategory, List<String>> _examples = {
    SmsCategory.finance: [
      '您尾号1234的储蓄卡于今日发生支出￥88.00，余额￥2300.00',
      '您的信用卡于今日消费￥120.00，可用额度￥5000.00',
      '代发工资￥8000.00已存入您的账户',
    ],
    SmsCategory.urgent: [
      '您的账户存在异常登录风险，请立即核实并修改密码',
      '您的贷款已逾期，请尽快还款以免影响征信',
      '您涉及一起诉讼案件，请于三日内到法院应诉',
    ],
    SmsCategory.todo: [
      '您的快递已到达驿站，请尽快取件',
      '您预约的会议将于明天上午10点举行，请准时参加',
      '您的话费套餐即将到期，请及时续费',
    ],
    SmsCategory.spam: [
      '双十一限时秒杀，全场五折，点击链接立即抢购',
      '恭喜您中奖，点击链接领取现金红包',
      '最高可借20万，无抵押低息，加微信咨询',
    ],
  };

  static final Map<SmsCategory, List<Float32List>> _exampleVectors =
      _buildExampleVectors();

  static Map<SmsCategory, List<Float32List>> _buildExampleVectors() {
    final map = <SmsCategory, List<Float32List>>{};
    for (final entry in _examples.entries) {
      map[entry.key] = entry.value.map(EmbeddingService.embed).toList();
    }
    return map;
  }

  /// 分类入口
  ///
  /// [sender] 发件人号码；[blacklist] 当前黑名单集合（命中直接判垃圾）。
  static SmsCategory classify(
    String body, {
    String sender = '',
    Set<String> blacklist = const {},
  }) {
    if (blacklist.contains(sender)) return SmsCategory.spam;

    final scores = <SmsCategory, int>{
      SmsCategory.urgent: _countHits(body, _urgentKeywords),
      SmsCategory.finance: _countHits(body, _financeKeywords),
      SmsCategory.spam: _countHits(body, _spamKeywords),
      SmsCategory.todo: _hasVerificationCode(body)
          ? 0
          : _countHits(body, _todoKeywords),
    };

    // 优先级：urgent > finance > spam > todo —— 只要高优先级分类有命中就直接采用，
    // 不与低优先级分类比较关键词命中数量（否则"逾期"1 次会被"账单/还款"2 次盖过）。
    const priority = [
      SmsCategory.urgent,
      SmsCategory.finance,
      SmsCategory.spam,
      SmsCategory.todo,
    ];
    for (final c in priority) {
      if ((scores[c] ?? 0) > 0) return c;
    }

    // 规则无命中 → 向量相似度兜底
    return _classifyByEmbedding(body);
  }

  static bool _hasVerificationCode(String body) {
    for (final kw in _verificationKeywords) {
      if (body.contains(kw)) return true;
    }
    return false;
  }

  static int _countHits(String body, Set<String> keywords) {
    var hits = 0;
    for (final kw in keywords) {
      if (body.toLowerCase().contains(kw.toLowerCase())) hits++;
    }
    return hits;
  }

  static SmsCategory _classifyByEmbedding(String body) {
    final v = EmbeddingService.embed(body);
    var best = SmsCategory.other;
    var bestSim = 0.0;
    for (final entry in _exampleVectors.entries) {
      for (final ex in entry.value) {
        final sim = EmbeddingService.cosine(v, ex);
        if (sim > bestSim) {
          bestSim = sim;
          best = entry.key;
        }
      }
    }
    if (bestSim < _similarityThreshold) return SmsCategory.other;
    if (best == SmsCategory.finance && !_amountSignal.hasMatch(body)) {
      return SmsCategory.other;
    }
    return best;
  }

  /// 分类置信度（供 UI 展示 / 排序参考）：规则命中恒为 1.0，向量兜底返回相似度
  static double confidenceOf(String body, SmsCategory category) {
    if (category == SmsCategory.other) return 1.0;
    final ruleHit = _countHits(
      body,
      switch (category) {
        SmsCategory.urgent => _urgentKeywords,
        SmsCategory.finance => _financeKeywords,
        SmsCategory.spam => _spamKeywords,
        SmsCategory.todo => _todoKeywords,
        SmsCategory.other => <String>{},
      },
    );
    if (ruleHit > 0) return 1.0;
    final v = EmbeddingService.embed(body);
    var bestSim = 0.0;
    for (final ex in _exampleVectors[category] ?? const []) {
      final sim = EmbeddingService.cosine(v, ex);
      if (sim > bestSim) bestSim = sim;
    }
    return bestSim;
  }
}
