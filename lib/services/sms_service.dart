/// 短信服务：通过原生 MethodChannel 增量拉取收件箱短信，
/// 过滤建行发件人 + 告警关键词后解析为 [SmsAlert]。
///
/// 数据流：
///   Telephony provider (native) → raw maps → CcbParser → SmsAlert (list)
///
/// 注意：不使用 flutter_sms_inbox——该库单次查询硬上限 1000 条且分页有 bug，
/// 无法覆盖跨年度的告警历史。本地 [AlertStore] 负责持久化全量，
/// 这里只负责「拉 sinceMs 之后的新短信」。
library;

import 'package:flutter/services.dart';

import '../models/alert.dart';
import 'ccb_parser.dart';

class SmsService {
  SmsService._();

  static const MethodChannel _channel = MethodChannel('smsmanager/sms');

  /// 点通知冷启动时的告警数据：{sender, body, at}；消费一次后清空。
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

  /// 建行短信识别号码段
  /// - 95533 建设银行全国客服
  /// - 1069 开头 + 95533 是建行官方商业号段
  /// - 12368 央行金融消费权益保护投诉电话（部分建行投诉通知）
  static const Set<String> _senderAllowlist = {
    '95533',
    '10695533',
    '12368',
  };

  /// 号码段匹配：号码里包含 95533 或以 1069 开头都算
  static bool _isCcbSender(String sender) {
    final cleaned = sender.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (_senderAllowlist.contains(cleaned)) return true;
    if (cleaned.contains('95533')) return true;
    if (cleaned.startsWith('1069') && cleaned.contains('95533')) return true;
    return false;
  }

  /// 拉取收件箱中 [sinceMs]（epoch 毫秒）之后收到的建行告警短信。
  ///
  /// - [sinceMs] 为 null 或 0 → 全量拉取（首次建库用，手机里有几年的就拉几年）
  /// - 增量调用方应自己按短信 id 去重（建议 sinceMs 往前带一点重叠窗口）
  /// - iOS / 无 channel 实现 → 返回空列表
  static Future<List<SmsAlert>> fetchCcbAlertsSince({int? sinceMs}) async {
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

    final results = <SmsAlert>[];
    for (final m in raw) {
      final map = m as Map;
      final sender = (map['address'] as String?) ?? '';
      if (!_isCcbSender(sender)) continue;
      final body = (map['body'] as String?) ?? '';
      // 只保留真正的告警；被过滤的短信不进入任何持久化 / 日志 / UI
      if (!CcbParser.isAlertCandidate(body)) continue;
      final id = (map['id'] as num?)?.toInt();
      if (id == null) continue;
      final dateMs = (map['date'] as num?)?.toInt();
      results.add(
        CcbParser.parse(
          id: id,
          sender: sender,
          body: body,
          receivedAt: dateMs != null
              ? DateTime.fromMillisecondsSinceEpoch(dateMs)
              : DateTime.now(),
        ),
      );
    }
    results.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return results;
  }
}
