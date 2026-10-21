/// 号码黑名单（app 内部维护，不依赖系统级拦截）
///
/// 用 [SharedPreferences] 持久化一个号码集合。命中黑名单的发件人，
/// 后续短信会被 [SmsClassifier] 直接判定为垃圾短信，不再跑内容规则。
library;

import 'package:shared_preferences/shared_preferences.dart';

class BlacklistStore {
  static const String _prefsKey = 'blacklist_senders';

  Set<String> _senders = {};

  Set<String> get senders => Set.unmodifiable(_senders);

  bool contains(String sender) => _senders.contains(sender);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _senders = (prefs.getStringList(_prefsKey) ?? []).toSet();
  }

  Future<void> add(String sender) async {
    if (sender.isEmpty || !_senders.add(sender)) return;
    await _persist();
  }

  Future<void> remove(String sender) async {
    if (!_senders.remove(sender)) return;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _senders.toList());
  }
}
