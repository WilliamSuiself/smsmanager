/// 重点关注号码列表（用户配置）
///
/// 通用短信汇聚分析：用户把自己关心的号码（银行、运维平台、物流、家人等）
/// 加入关注列表。关注号码的短信**全量**收录进分析库；
/// 非关注号码只收录命中告警关键词的（通用汇聚分析）。
///
/// 持久化：Flutter 侧 SharedPreferences + 同步推送给原生（通知过滤用）。
library;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchlistService {
  WatchlistService._();

  static const String _key = 'watch_senders';
  static const MethodChannel _channel = MethodChannel('smsanalyzer/sms');

  /// 规范化号码：去空格/横线/加号，@开头视为规范化结果
  static String normalize(String sender) =>
      sender.replaceAll(RegExp(r'[\s\-\+]'), '');

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 保存并同步到原生侧（SmsReceiver 通知过滤用）
  static Future<void> save(List<String> senders) async {
    final normalized = senders.map(normalize).toSet().toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, normalized);
    } catch (_) {}
    try {
      await _channel.invokeMethod('setWatchlist', {'senders': normalized});
    } on MissingPluginException {
      // 原生不可用时仅存 Flutter 侧（列表过滤仍生效）
    } catch (_) {}
  }

  static Future<List<String>> add(String sender) async {
    final list = (await load()).toList();
    final n = normalize(sender);
    if (n.isNotEmpty && !list.contains(n)) list.add(n);
    await save(list);
    return list;
  }

  static Future<List<String>> remove(String sender) async {
    final list = (await load()).toList()..remove(normalize(sender));
    await save(list);
    return list;
  }

  static Future<bool> contains(String sender) async =>
      (await load()).contains(normalize(sender));
}
