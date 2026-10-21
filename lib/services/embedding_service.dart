/// 本地文本向量嵌入服务（离线，不联网）
///
/// 建行告警短信是高度模板化的中文文本，字符级 n-gram + 哈希映射（hashing trick）
/// 生成的稀疏向量对这类文本的相似度检索足够有效，且：
///   - 纯本地计算，无网络依赖，无隐私外泄
///   - 哈希函数自实现（FNV-1a），跨进程 / 跨版本稳定，向量可持久化
///   - 512 维 Float32，暴力余弦检索对数百条规模毫无压力
///
/// 归一化策略：数字归并（95% 与 87% 视为相似）、去空白与标点、小写化。
library;

import 'dart:math';
import 'dart:typed_data';

class EmbeddingService {
  EmbeddingService._();

  /// 向量维度（2 的幂，哈希取模分布更均匀）
  static const int dim = 512;

  /// n-gram 范围：1~3 个字符
  ///
  /// unigram 权重减半——单字区分度低但提供兜底召回；
  /// bigram/trigram 是中文告警模板的主要区分特征。
  static const int _maxGram = 3;
  static const double _unigramWeight = 0.5;

  /// 文本 → L2 归一化向量（余弦相似度 = 点积）
  static Float32List embed(String text) {
    final v = Float32List(dim);
    final t = _normalize(text);
    if (t.isEmpty) return v;

    for (var n = 1; n <= _maxGram; n++) {
      if (t.length < n) break;
      final w = n == 1 ? _unigramWeight : 1.0;
      for (var i = 0; i + n <= t.length; i++) {
        final idx = _fnv1a(t, i, i + n) % dim;
        v[idx] += w;
      }
    }

    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < dim; i++) {
        v[i] /= norm;
      }
    }
    return v;
  }

  /// 余弦相似度（向量已归一化 → 直接点积）
  static double cosine(Float32List a, Float32List b) {
    var s = 0.0;
    for (var i = 0; i < dim; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  /// 归一化：小写 + 数字串归并为 '#' + 去空白标点
  ///
  /// 数字归并很关键：「TiKV 空间使用率 95%」与「TiKV 空间使用率 87%」
  /// 是同一问题的两次告警，数字差异不应拉开相似度。
  static String _normalize(String text) {
    var t = text.toLowerCase();
    t = t.replaceAll(RegExp(r'\d+'), '#');
    t = t.replaceAll(RegExp(r'[\s,，。:：;；!！?？()（）\[\]【】「」"._\-/]'), '');
    t = t.replaceAll("'", '');
    return t;
  }

  /// FNV-1a 32-bit 哈希
  ///
  /// 必须用自实现的确定性哈希——Dart 的 String.hashCode 不保证跨进程稳定，
  /// 用它做持久化向量会导致重启后向量库整体失效。
  static int _fnv1a(String s, int start, int end) {
    var h = 0x811c9dc5;
    for (var i = start; i < end; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}
