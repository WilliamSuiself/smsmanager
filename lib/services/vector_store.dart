/// 告警向量库：alertId → 512 维向量的持久化存储 + 余弦检索
///
/// 存储格式（vectors.json）：
///   {"dim":512, "items":[{"id":123, "v":"<base64 little-endian float32>"}]}
///
/// 暴力 topK：数百条告警规模下毫秒级完成，无需引入 HNSW / sqlite-vec。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'embedding_service.dart';

/// 一条相似命中
class VectorHit {
  final int id;
  final double score;
  const VectorHit(this.id, this.score);
}

class VectorStore {
  final Map<int, Float32List> _vectors = {};

  int get size => _vectors.length;

  bool contains(int id) => _vectors.containsKey(id);

  Float32List? vectorOf(int id) => _vectors[id];

  void upsert(int id, Float32List v) {
    _vectors[id] = v;
  }

  /// 只保留 [keepIds] 中的向量（短信库滚动淘汰后同步清理）
  ///
  /// 返回被移除的条数。
  int retain(Set<int> keepIds) {
    final before = _vectors.length;
    _vectors.removeWhere((id, _) => !keepIds.contains(id));
    return before - _vectors.length;
  }

  /// 余弦相似度 topK（query 需已归一化）
  ///
  /// [excludeId] 排除自身；[minScore] 过滤低相似噪声命中。
  List<VectorHit> topK(
    Float32List query, {
    int k = 5,
    int? excludeId,
    double minScore = 0.0,
  }) {
    final hits = <VectorHit>[];
    for (final e in _vectors.entries) {
      if (e.key == excludeId) continue;
      final s = EmbeddingService.cosine(query, e.value);
      if (s >= minScore) hits.add(VectorHit(e.key, s));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(k).toList();
  }

  // ──────────────────────────────────────────────
  // 持久化
  // ──────────────────────────────────────────────

  Future<void> loadFrom(File file) async {
    _vectors.clear();
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if ((data['dim'] as int?) != EmbeddingService.dim) return;
      for (final item in (data['items'] as List? ?? [])) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as int?;
        final b64 = m['v'] as String?;
        if (id == null || b64 == null) continue;
        _vectors[id] = _decode(b64);
      }
    } catch (_) {
      _vectors.clear();
    }
  }

  Future<void> saveTo(File file) async {
    final items = [
      for (final e in _vectors.entries) {'id': e.key, 'v': _encode(e.value)},
    ];
    await file.writeAsString(
      jsonEncode({'dim': EmbeddingService.dim, 'items': items}),
    );
  }

  static Float32List _decode(String b64) {
    final bytes = base64Decode(b64);
    final data = ByteData.sublistView(bytes);
    final v = Float32List(EmbeddingService.dim);
    for (var i = 0; i < EmbeddingService.dim; i++) {
      v[i] = data.getFloat32(i * 4, Endian.little);
    }
    return v;
  }

  static String _encode(Float32List v) {
    final data = ByteData(v.length * 4);
    for (var i = 0; i < v.length; i++) {
      data.setFloat32(i * 4, v[i], Endian.little);
    }
    return base64Encode(data.buffer.asUint8List());
  }
}
