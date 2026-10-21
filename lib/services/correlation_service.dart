/// 告警关联分析服务
///
/// 对一条目标告警，结合规则维度 + 向量维度给出关联报告：
///   1. 同对象复发：同一 objectKey 的历史告警次数 / 近 24h、近 7d 次数 / 距上次间隔
///   2. 同期爆发：前后 ±30 分钟窗口内的其他告警（告警风暴 / 连锁故障信号）
///   3. 同类型模式：相同 类型+严重度 的历史告警数量
///   4. 语义相似：向量库余弦 topK（能发现「不同对象但同一类问题」，如 B1/B2 各自的 TiKV 空间告警）
library;

import '../models/alert.dart';
import 'embedding_service.dart';
import 'vector_store.dart';

/// 综合判定结论（优先级：风暴 > 高频 > 复发 > 首次）
enum CorrelationVerdict {
  /// 同期多条告警爆发
  storm,

  /// 同对象高频复发
  frequent,

  /// 同对象历史出现过
  recurring,

  /// 首次出现
  firstSeen,
}

extension CorrelationVerdictX on CorrelationVerdict {
  String get label {
    switch (this) {
      case CorrelationVerdict.storm:
        return '告警风暴';
      case CorrelationVerdict.frequent:
        return '高频复发';
      case CorrelationVerdict.recurring:
        return '复发';
      case CorrelationVerdict.firstSeen:
        return '首次出现';
    }
  }
}

/// 语义相似的告警
class SimilarAlert {
  final SmsAlert alert;
  final double score;
  const SimilarAlert(this.alert, this.score);
}

/// 一条告警的关联分析报告
class CorrelationReport {
  final String objectKey;
  final CorrelationVerdict verdict;

  /// 同对象告警（含目标本身，时间倒序）
  final List<SmsAlert> sameObject;
  final int sameObjectTotal;
  final int sameObject24h;
  final int sameObject7d;

  /// 上一次同对象告警时间（无则为 null → 首次）
  final DateTime? lastSeenBefore;

  /// ±30 分钟窗口内的其他告警
  final List<SmsAlert> burst;

  /// 同 类型+严重度 的历史告警总数（含自身）
  final int samePatternTotal;

  /// 同对象告警的季度分布（"2025Q4" → 次数），按季度倒序。
  /// 用于发现周期性规律：季末批量、年末结息、季度结算等。
  final Map<String, int> sameObjectByQuarter;

  /// 同对象告警跨年统计：出现过的年份列表（倒序）
  final List<int> sameObjectYears;

  /// 向量语义相似 topK（不含自身，已按分数降序）
  final List<SimilarAlert> similar;

  /// 与上一次同对象告警相比，正文发生了什么变化（无上一次则为 null）
  final String? diffFromPrevious;

  const CorrelationReport({
    required this.objectKey,
    required this.verdict,
    required this.sameObject,
    required this.sameObjectTotal,
    required this.sameObject24h,
    required this.sameObject7d,
    required this.lastSeenBefore,
    required this.burst,
    required this.samePatternTotal,
    required this.sameObjectByQuarter,
    required this.sameObjectYears,
    required this.similar,
    required this.diffFromPrevious,
  });
}

/// 简单文本 diff：取公共前缀 + 公共后缀，中间不同的部分即为两次告警的差异。
/// 适合建行告警这种"模板固定、中间变量（作业名/数值/时间戳）变化"的场景。
/// 与 Kotlin 侧 SmsReceiver.diffSummary 保持同一套规则。
String diffSummary(String previous, String current) {
  if (previous == current) return '内容与上次完全一致';
  final minLen = previous.length < current.length ? previous.length : current.length;
  var prefix = 0;
  while (prefix < minLen && previous[prefix] == current[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < minLen - prefix &&
      previous[previous.length - 1 - suffix] == current[current.length - 1 - suffix]) {
    suffix++;
  }
  final prevMid = previous.substring(prefix, previous.length - suffix).trim();
  final currMid = current.substring(prefix, current.length - suffix).trim();
  if (prevMid.isEmpty && currMid.isEmpty) return '内容与上次完全一致';
  String clip(String s) => s.length > 36 ? '${s.substring(0, 36)}…' : s;
  final prevShown = prevMid.isEmpty ? '(无)' : clip(prevMid);
  final currShown = currMid.isEmpty ? '(无)' : clip(currMid);
  return '上次「$prevShown」→ 本次「$currShown」';
}

class CorrelationService {
  CorrelationService._();

  /// 爆发窗口：±30 分钟
  static const Duration burstWindow = Duration(minutes: 30);

  /// 高频判定：近 7 天 ≥10 次 或 近 24 小时 ≥5 次
  static const int frequent7d = 10;
  static const int frequent24h = 5;

  /// 风暴判定：窗口内其他告警 ≥3 条
  static const int stormCount = 3;

  /// 向量相似度下限（低于此值认为是噪声，不展示）
  static const double minSimilarity = 0.3;

  /// 相似召回条数
  static const int similarTopK = 8;

  static CorrelationReport analyze({
    required SmsAlert target,
    required List<SmsAlert> all,
    required VectorStore store,
    required String Function(SmsAlert) objectKeyOf,
  }) {
    final key = objectKeyOf(target);
    final t = target.receivedAt;
    final cutoff24h = t.subtract(const Duration(hours: 24));
    final cutoff7d = t.subtract(const Duration(days: 7));

    // ── 维度 1：同对象 ──
    final sameObj = all.where((a) => objectKeyOf(a) == key).toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final total = sameObj.length;
    final c24 = sameObj.where((a) => a.receivedAt.isAfter(cutoff24h)).length;
    final c7 = sameObj.where((a) => a.receivedAt.isAfter(cutoff7d)).length;
    DateTime? lastBefore;
    for (final a in sameObj) {
      if (a.id != target.id && a.receivedAt.isBefore(t)) {
        lastBefore = a.receivedAt;
        break;
      }
    }

    // ── 维度 2：同期爆发 ──
    final burst = all
        .where((a) =>
            a.id != target.id &&
            a.receivedAt.difference(t).abs() <= burstWindow)
        .toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

    // ── 维度 3：同类型模式 ──
    final samePattern = all
        .where((a) => a.type == target.type && a.severity == target.severity)
        .length;

    // ── 维度 3.5：同对象的季度 / 年度分布（周期性规律） ──
    final byQuarter = <String, int>{};
    final years = <int>{};
    for (final a in sameObj) {
      final d = a.receivedAt;
      final q = '${d.year}Q${(d.month - 1) ~/ 3 + 1}';
      byQuarter[q] = (byQuarter[q] ?? 0) + 1;
      years.add(d.year);
    }
    final quarterSorted = Map.fromEntries(
      byQuarter.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
    final yearList = years.toList()..sort((a, b) => b.compareTo(a));

    // ── 维度 4：向量语义相似 ──
    final query = store.vectorOf(target.id) ?? EmbeddingService.embed(target.body);
    final byId = {for (final a in all) a.id: a};
    final similar = <SimilarAlert>[];
    for (final h in store.topK(
      query,
      k: similarTopK,
      excludeId: target.id,
      minScore: minSimilarity,
    )) {
      final hit = byId[h.id];
      if (hit != null) similar.add(SimilarAlert(hit, h.score));
    }

    // ── 综合判定 ──
    final CorrelationVerdict verdict;
    if (burst.length >= stormCount) {
      verdict = CorrelationVerdict.storm;
    } else if (c7 >= frequent7d || c24 >= frequent24h) {
      verdict = CorrelationVerdict.frequent;
    } else if (total > 1) {
      verdict = CorrelationVerdict.recurring;
    } else {
      verdict = CorrelationVerdict.firstSeen;
    }

    // 与上一次同对象告警（lastBefore 对应的那条）做正文 diff
    String? diff;
    final lastBeforeTime = lastBefore;
    if (lastBeforeTime != null) {
      final prev = sameObj.firstWhere(
        (a) => a.id != target.id && a.receivedAt.isAtSameMomentAs(lastBeforeTime),
        orElse: () => sameObj.firstWhere((a) => a.id != target.id),
      );
      diff = diffSummary(prev.body, target.body);
    }

    return CorrelationReport(
      objectKey: key,
      verdict: verdict,
      sameObject: sameObj,
      sameObjectTotal: total,
      sameObject24h: c24,
      sameObject7d: c7,
      lastSeenBefore: lastBefore,
      burst: burst,
      samePatternTotal: samePattern,
      sameObjectByQuarter: quarterSorted,
      sameObjectYears: yearList,
      similar: similar,
      diffFromPrevious: diff,
    );
  }
}
