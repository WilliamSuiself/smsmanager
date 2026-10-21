/// 短信服务：通过原生 MethodChannel 增量拉取收件箱短信，
/// 交给 [SmsClassifier] 分类为 [SmsMessage]。
///
/// 数据流：
///   Telephony provider (native) → raw maps → SmsClassifier → SmsMessage (list)
///
/// 注意：不使用 flutter_sms_inbox——该库单次查询硬上限 1000 条且分页有 bug，
/// 无法覆盖跨年度历史。本地 [MessageStore] 负责持久化全量，
/// 这里只负责「拉 sinceMs 之后的新短信」。
library;

import 'package:flutter/services.dart';

import '../models/sms_message.dart';
import 'sms_classifier.dart';

class SmsService {
  SmsService._();

  static const MethodChannel _channel = MethodChannel('smsmanager/sms');

  /// 点通知冷启动时携带的短信数据：{sender, body, at}；消费一次后清空。
  static Future<Map<String, dynamic>?> consumeLaunchAlert() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'consumeLaunchAlert',
      );
      return res?.cast<String, dynamic>();
    } on MissingPluginException {
      return null;
    }
  }

  /// App 存活时点通知 → 原生侧主动推 'onLaunchAlert'（onNewIntent）。
  /// 在启动早期调用一次完成绑定。
  static void setLaunchAlertHandler(
    void Function(Map<String, dynamic> data) onLaunchAlert,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchAlert' && call.arguments is Map) {
        onLaunchAlert((call.arguments as Map).cast<String, dynamic>());
      }
    });
  }

  /// 拉取收件箱中 [sinceMs]（epoch 毫秒）之后收到的全部短信并分类。
  ///
  /// - [sinceMs] 为 null 或 0 → 全量拉取（首次建库用）
  /// - 增量调用方应自己按短信 id 去重（建议 sinceMs 往前带一点重叠窗口）
  /// - iOS / 无 channel 实现 → 返回空列表
  static Future<List<SmsMessage>> fetchMessagesSince({
    int? sinceMs,
    Set<String> blacklist = const {},
  }) async {
    final List<dynamic>? raw;
    try {
      raw = await _channel.invokeMethod<List<dynamic>>(
        'queryInbox',
        {'sinceMs': sinceMs ?? 0},
      );
    } on MissingPluginException {
      return const [];
    }
    if (raw == null) return const [];

    final results = <SmsMessage>[];
    for (final m in raw) {
      final map = m as Map;
      final sender = (map['address'] as String?) ?? '';
      final body = (map['body'] as String?) ?? '';
      final id = (map['id'] as num?)?.toInt();
      if (id == null || body.isEmpty) continue;
      final dateMs = (map['date'] as num?)?.toInt();
      final receivedAt = dateMs != null
          ? DateTime.fromMillisecondsSinceEpoch(dateMs)
          : DateTime.now();
      final category = SmsClassifier.classify(
        body,
        sender: sender,
        blacklist: blacklist,
      );
      results.add(
        SmsMessage(
          id: id,
          sender: sender,
          body: body,
          receivedAt: receivedAt,
          category: category,
          confidence: SmsClassifier.confidenceOf(body, category),
        ),
      );
    }
    results.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return results;
  }
}
