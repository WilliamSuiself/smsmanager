/// 应用统一状态 Provider
///
/// 两条数据管道共享同一次短信拉取：
///   - 全量管道：[SmsMessage] 分类入库 → 消息列表 / 账本 / 待办 / 黑名单
///   - 汇聚管道：[SmsAlert]（关注号码 ∪ 告警关键词）→ 折叠 / 静音 / AI 标注 / 向量关联
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert.dart';
import '../models/ledger_entry.dart';
import '../models/sms_message.dart';
import '../models/todo_item.dart';
import '../services/alert_store.dart';
import '../services/blacklist_store.dart';
import '../services/ccb_parser.dart';
import '../services/correlation_service.dart';
import '../services/embedding_service.dart';
import '../services/finance_parser.dart';
import '../services/ledger_store.dart';
import '../services/message_store.dart';
import '../services/object_key.dart';
import '../services/permission_service.dart';
import '../services/sms_service.dart';
import '../services/todo_store.dart';
import '../services/vector_store.dart';
import '../services/watchlist_service.dart';

/// 三态权限：未检查 / 已授权 / 已拒绝（含永久拒绝）
enum PermissionGate { unknown, granted, denied }

class AppProvider extends ChangeNotifier {
  List<SmsAlert> _alerts = [];
  bool _loading = false;
  String? _error;
  PermissionGate _gate = PermissionGate.unknown;

  /// 按对象折叠后的分组（仅当 AlertGroupingMode.folded 时使用）
  List<AlertGroup> _groups = [];
  AlertGroupingMode _groupingMode = AlertGroupingMode.folded;

  /// 静音的对象（key → 静音至 timestamp ms）
  final Map<String, int> _muted = {};

  /// AI 分析结果（来自 agent 写的 analysis.json）：alert id → AI 标签
  Map<int, AiTag> _aiTags = {};

  /// 本地向量库（所有告警短信自动进入，供语义相似关联）
  final VectorStore _vectorStore = VectorStore();
  bool _vectorStoreLoaded = false;

  /// 持久化告警库（全量历史，跨年度，不受短信库滚动淘汰影响）
  final AlertStore _store = AlertStore();
  File? _storeFile;
  File? _vectorFile;

  /// 全量短信库 + 衍生数据（账本 / 待办 / 黑名单）
  final MessageStore _messageStore = MessageStore();
  final LedgerStore _ledgerStore = LedgerStore();
  final TodoStore _todoStore = TodoStore();
  final BlacklistStore _blacklistStore = BlacklistStore();
  File? _messageFile;
  File? _ledgerFile;
  File? _todoFile;

  /// 消息列表当前按分类筛选（null = 全部）
  SmsCategory? _filter;

  /// 增量查询的重叠窗口：防止同步间隙内到达的短信漏抓
  static const int _syncOverlapMs = 10 * 60 * 1000;

  /// 上次打开时间（启动弹窗用）+ 本次启动新增的告警
  static const String _lastOpenKey = 'last_open_ms';
  DateTime? _lastOpenAt;
  List<SmsAlert> _newSinceLastOpen = [];

  DateTime? get lastOpenAt => _lastOpenAt;

  /// 上次打开到本次打开之间的新增告警（bootstrap 时计算，展示过弹窗后可清除）
  List<SmsAlert> get newSinceLastOpen => _newSinceLastOpen;

  void dismissNewAlerts() => _newSinceLastOpen = [];

  /// 读取上次打开时间；返回 null 表示首次启动（无可比基线）
  Future<DateTime?> _readLastOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_lastOpenKey);
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (e) {
      debugPrint('[CCB-Alert] readLastOpen error: $e');
      return null;
    }
  }

  Future<void> _writeLastOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _lastOpenKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[CCB-Alert] writeLastOpen error: $e');
    }
  }

  /// 关联分析缓存：alert id → report（reload 时清空）
  final Map<int, CorrelationReport> _corrCache = {};

  List<SmsAlert> get alerts => _alerts;
  bool get loading => _loading;
  String? get error => _error;
  PermissionGate get gate => _gate;
  List<AlertGroup> get groups => _groups;
  AlertGroupingMode get mode => _groupingMode;
  Map<int, AiTag> get aiTags => _aiTags;

  // ──────────────────────────────────────────────
  // 全量短信 / 账本 / 待办 / 黑名单
  // ──────────────────────────────────────────────

  List<SmsMessage> get messages => _messageStore.all;
  SmsMessage? messageById(int id) => _messageStore.byId(id);
  SmsCategory? get filter => _filter;

  /// 当前筛选下可见的短信
  List<SmsMessage> get visibleMessages {
    if (_filter == null) return messages;
    return messages.where((m) => m.category == _filter).toList();
  }

  List<LedgerEntry> get ledgerEntries => _ledgerStore.all;
  List<TodoItem> get todos => _todoStore.all;
  Set<String> get blacklist => _blacklistStore.senders;

  /// 每个分类下的短信数量（供消息页筛选 chip 展示角标）
  Map<SmsCategory, int> get categoryCounts {
    final counts = <SmsCategory, int>{for (final c in SmsCategory.values) c: 0};
    for (final m in messages) {
      counts[m.category] = (counts[m.category] ?? 0) + 1;
    }
    return counts;
  }

  /// 本月收入 / 支出合计（人民币元）
  ({double income, double expense}) get monthlyTotals {
    final now = DateTime.now();
    double income = 0;
    double expense = 0;
    for (final e in _ledgerStore.all) {
      if (e.at.year != now.year || e.at.month != now.month) continue;
      final amount = e.amount ?? 0;
      if (e.direction == TxDirection.income) {
        income += amount;
      } else if (e.direction == TxDirection.expense) {
        expense += amount;
      }
    }
    return (income: income, expense: expense);
  }

  /// 当前未静音的告警
  List<SmsAlert> get visibleAlerts {
    if (_muted.isEmpty) return _alerts;
    final now = DateTime.now().millisecondsSinceEpoch;
    return _alerts.where((a) {
      final key = extractObjectKey(a);
      final until = _muted[key];
      if (until == null) return true;
      return now > until;
    }).toList();
  }

  /// 加载本地持久化库（告警 / 消息 / 账本 / 待办 / 黑名单 / 向量库），启动时先展示全量历史
  Future<void> _loadLocalData() async {
    final dir = await getApplicationSupportDirectory();
    _storeFile = File('${dir.path}/alerts_store.json');
    _vectorFile = File('${dir.path}/vectors.json');
    _messageFile = File('${dir.path}/messages_store.json');
    _ledgerFile = File('${dir.path}/ledger_store.json');
    _todoFile = File('${dir.path}/todo_store.json');

    await _store.loadFrom(_storeFile!);
    _alerts = _store.all;

    await _vectorStore.loadFrom(_vectorFile!);
    _vectorStoreLoaded = true;

    await _messageStore.loadFrom(_messageFile!);
    await _ledgerStore.loadFrom(_ledgerFile!);
    await _todoStore.loadFrom(_todoFile!);
    await _blacklistStore.load();

    if (_alerts.isNotEmpty || _messageStore.size > 0) {
      _rebuildGroups();
      notifyListeners();
    }
  }

  /// 当前关注号码列表
  List<String> _watchlist = const [];

  List<String> get watchlist => _watchlist;

  /// 添加关注号码（含刷新同步）
  Future<void> addWatchSender(String sender) async {
    _watchlist = await WatchlistService.add(sender);
    notifyListeners();
    if (_gate == PermissionGate.granted) await reload();
  }

  /// 移除关注号码
  Future<void> removeWatchSender(String sender) async {
    _watchlist = await WatchlistService.remove(sender);
    notifyListeners();
    if (_gate == PermissionGate.granted) await reload();
  }

  /// 检查权限 → 加载本地历史 → 申请（如未授权） → 增量同步短信
  ///
  /// 同步完成后计算「上次打开 → 本次打开」之间的新增告警（启动弹窗用）。
  Future<void> bootstrap() async {
    await _loadLocalData();
    _watchlist = await WatchlistService.load();
    await SmsService.loadWatchlist();
    _lastOpenAt = await _readLastOpen();
    final status = await PermissionService.currentStatus();
    _gate = status.isGranted ? PermissionGate.granted : PermissionGate.denied;
    notifyListeners();
    if (_gate == PermissionGate.granted) {
      await reload();
    }
    // 记录本次打开时间（下次启动即为「上次打开」）
    await _writeLastOpen();
    // 有基线且同步后有新增 → 标记出来供启动弹窗展示
    if (_lastOpenAt != null) {
      final fresh = _alerts
          .where((a) => a.receivedAt.isAfter(_lastOpenAt!))
          .toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      _newSinceLastOpen = fresh;
      notifyListeners();
    }
  }

  /// 申请权限
  Future<void> requestPermission() async {
    final status = await PermissionService.requestSms();
    _gate = status.isGranted ? PermissionGate.granted : PermissionGate.denied;
    notifyListeners();
    if (_gate == PermissionGate.granted) {
      await reload();
    }
  }

  /// 增量同步：拉取上次同步点之后的新短信，一次拉取喂两条管道
  ///
  /// - 全量管道：所有短信分类进 [MessageStore]，账务 / 待办类自动衍生账本条目 / 待办事项
  /// - 汇聚管道：其中满足「关注号码 ∪ 告警关键词」的子集进 [AlertStore]
  ///
  /// 首次运行（lastSyncMs == 0）做全量拉取建库；之后只拉增量，
  /// 数据一旦入库永久保留，不受系统短信库滚动淘汰影响。
  Future<void> reload() async {
    if (_gate != PermissionGate.granted) {
      _error = '请先授权短信权限';
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // 告警是消息的子集：用全量消息游标做增量点即可覆盖两条管道
      final since = _messageStore.lastSyncMs > 0
          ? _messageStore.lastSyncMs - _syncOverlapMs
          : 0;
      final fresh = await SmsService.fetchMessagesSince(
        sinceMs: since,
        blacklist: _blacklistStore.senders,
      );
      final added = _messageStore.merge(fresh);
      _deriveLedgerAndTodo(fresh);
      if (added > 0 && _messageFile != null) {
        await _messageStore.saveTo(_messageFile!);
      }

      final freshAlerts = [
        for (final m in fresh)
          if (SmsService.isWatchOrAlert(m.sender, m.body))
            CcbParser.parse(
              id: m.id,
              sender: m.sender,
              body: m.body,
              receivedAt: m.receivedAt,
            ),
      ];
      final alertsAdded = _store.merge(freshAlerts);
      if (alertsAdded > 0 && _storeFile != null) {
        await _store.saveTo(_storeFile!);
      }
      _alerts = _store.all;
      _corrCache.clear();
      await _syncVectorStore();
      _rebuildGroups();
      await _loadAiAnalysis();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 为新到达的账务 / 待办类短信生成账本条目 / 待办事项（按 id 去重，可重复调用）
  void _deriveLedgerAndTodo(List<SmsMessage> fresh) {
    var ledgerAdded = false;
    var todoAdded = false;
    for (final m in fresh) {
      if (m.category == SmsCategory.finance && !_ledgerStore.contains(m.id)) {
        final entry = FinanceParser.parse(
          messageId: m.id,
          body: m.body,
          at: m.receivedAt,
        );
        if (_ledgerStore.add(entry)) ledgerAdded = true;
      } else if (m.category == SmsCategory.todo &&
          !_todoStore.contains(m.id)) {
        final title = m.body.length > 40 ? m.body.substring(0, 40) : m.body;
        if (_todoStore.add(
          TodoItem(messageId: m.id, title: title, createdAt: m.receivedAt),
        )) {
          todoAdded = true;
        }
      }
    }
    if (ledgerAdded && _ledgerFile != null) {
      _ledgerStore.saveTo(_ledgerFile!);
    }
    if (todoAdded && _todoFile != null) {
      _todoStore.saveTo(_todoFile!);
    }
  }

  void setFilter(SmsCategory? category) {
    _filter = category;
    notifyListeners();
  }

  void markRead(int id) {
    _messageStore.markRead(id);
    if (_messageFile != null) _messageStore.saveTo(_messageFile!);
    notifyListeners();
  }

  void toggleTodo(int messageId, bool done) {
    _todoStore.setDone(messageId, done);
    if (_todoFile != null) _todoStore.saveTo(_todoFile!);
    notifyListeners();
  }

  /// 把号码加入黑名单：以后该号码的短信直接判为垃圾，
  /// 并立即把历史上这个号码的短信重新打上垃圾标签。
  Future<void> blockSender(String sender) async {
    await _blacklistStore.add(sender);
    final affected = messages.where((m) => m.sender == sender).toList();
    if (affected.isNotEmpty) {
      for (final m in affected) {
        _messageStore.replace(
          SmsMessage(
            id: m.id,
            sender: m.sender,
            body: m.body,
            receivedAt: m.receivedAt,
            category: SmsCategory.spam,
            confidence: 1.0,
            read: m.read,
          ),
        );
      }
      if (_messageFile != null) await _messageStore.saveTo(_messageFile!);
    }
    notifyListeners();
  }

  Future<void> unblockSender(String sender) async {
    await _blacklistStore.remove(sender);
    notifyListeners();
  }

  /// 切换折叠 / 平铺模式
  void toggleGroupingMode() {
    _groupingMode = _groupingMode == AlertGroupingMode.folded
        ? AlertGroupingMode.flat
        : AlertGroupingMode.folded;
    _rebuildGroups();
    notifyListeners();
  }

  /// 静音某个告警对象 N 小时
  void muteObject(String objectKey, {int hours = 24}) {
    _muted[objectKey] =
        DateTime.now().millisecondsSinceEpoch + hours * 3600 * 1000;
    _rebuildGroups();
    notifyListeners();
  }

  /// 解除静音
  void unmuteObject(String objectKey) {
    _muted.remove(objectKey);
    _rebuildGroups();
    notifyListeners();
  }

  /// 当前静音的对象列表
  List<MapEntry<String, int>> get mutedObjects {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _muted.entries.where((e) => e.value > now).toList();
  }

  /// 向量库规模（供 UI / 调试展示）
  int get vectorStoreSize => _vectorStore.size;

  /// 对某条告警做关联分析（同对象 / 同期爆发 / 同类型 / 语义相似）
  ///
  /// 结果按 alert.id 缓存，reload 时清空。
  CorrelationReport correlateAlert(SmsAlert alert) {
    return _corrCache.putIfAbsent(
      alert.id,
      () => CorrelationService.analyze(
        target: alert,
        all: _alerts,
        store: _vectorStore,
        objectKeyOf: extractObjectKey,
      ),
    );
  }

  /// 同步向量库：新告警自动嵌入入库
  ///
  /// 向量只增不删——告警从系统短信库淘汰后仍需参与跨年度关联检索。
  Future<void> _syncVectorStore() async {
    if (_vectorFile == null) return;
    if (!_vectorStoreLoaded) {
      await _vectorStore.loadFrom(_vectorFile!);
      _vectorStoreLoaded = true;
    }
    var added = 0;
    for (final a in _alerts) {
      if (!_vectorStore.contains(a.id)) {
        _vectorStore.upsert(a.id, EmbeddingService.embed(a.body));
        added++;
      }
    }
    if (added > 0) {
      await _vectorStore.saveTo(_vectorFile!);
      debugPrint('[CCB-Alert] vector store: +$added, total ${_vectorStore.size}');
    }
  }

  /// 重建分组（折叠模式）
  void _rebuildGroups() {
    if (_groupingMode == AlertGroupingMode.flat) {
      _groups = [];
      return;
    }
    final filtered = visibleAlerts;
    final Map<String, List<SmsAlert>> bucket = {};
    for (final a in filtered) {
      final key = extractObjectKey(a);
      bucket.putIfAbsent(key, () => []).add(a);
    }
    // 倒序：最新告警的组在最前（同一组内 _alerts 已按时间倒序，first 即最新）
    final entries = bucket.entries.toList()
      ..sort((a, b) =>
          b.value.first.receivedAt.compareTo(a.value.first.receivedAt));
    _groups = entries.map((e) => AlertGroup(
          objectKey: e.key,
          alerts: e.value,
          isMuted: _muted.containsKey(e.key),
          muteUntil: _muted[e.key],
        )).toList();
  }

  /// 提取告警"对象" key（用于折叠 / 关联）
  ///
  /// 规则实现见 [extractAlertObjectKey]（纯函数，tool 脚本 / Kotlin 侧同步）。
  static String extractObjectKey(SmsAlert alert) =>
      extractAlertObjectKey(alert.body);

  /// 加载 AI 分析结果（来自 agent 写的 files/analysis.json）
  Future<void> _loadAiAnalysis() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/analysis.json');
      if (!file.existsSync()) {
        _aiTags = {};
        return;
      }
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final tags = <int, AiTag>{};
      for (final entry in (raw['tags'] as Map<String, dynamic>? ?? {}).entries) {
        final id = int.tryParse(entry.key);
        if (id == null) continue;
        final v = entry.value as Map<String, dynamic>;
        tags[id] = AiTag(
          id: id,
          verdict: v['verdict'] as String? ?? 'unknown',
          summary: v['summary'] as String? ?? '',
          action: v['action'] as String? ?? 'WATCH',
        );
      }
      _aiTags = tags;
    } catch (e) {
      debugPrint('[CCB-Alert] loadAiAnalysis error: $e');
      _aiTags = {};
    }
  }

  /// 把当前告警写到 files/alerts.json（agent 拉取）+ files/baseline.json（首次）
  ///
  /// 第一次启动：作为基线 baseline.json（之后用作 AI 比对的"已有告警"快照）
  /// 每次启动：覆盖 alerts.json（agent 拉取最新数据）
  Future<String?> exportAlertsJson() async {
    if (_gate != PermissionGate.granted || _alerts.isEmpty) return null;
    final dir = await getApplicationSupportDirectory();

    // 写 alerts.json（最新告警，agent 拉取用）
    final alertsFile = File('${dir.path}/alerts.json');
    final encoded = jsonEncode({
      'exportedAt': DateTime.now().toIso8601String(),
      'count': _alerts.length,
      'alerts': _alerts
          .map((a) => {
                'id': a.id,
                'sender': a.sender,
                'body': a.body,
                'receivedAt': a.receivedAt.toIso8601String(),
                'type': a.type.name,
                'severity': a.severity.name,
                'objectKey': extractObjectKey(a),
              })
          .toList(),
    });
    await alertsFile.writeAsString(encoded);

    // 写 baseline.json（首次——基线快照）
    final baselineFile = File('${dir.path}/baseline.json');
    if (!baselineFile.existsSync()) {
      await baselineFile.writeAsString(encoded);
      debugPrint('[CCB-Alert] baseline.json created with ${_alerts.length} alerts');
    }
    // 写 newest.json（每次 reload 都覆盖——agent 用它跟 baseline 比对找新增告警）
    final newestFile = File('${dir.path}/newest.json');
    await newestFile.writeAsString(encoded);

    return alertsFile.path;
  }
}

/// 折叠后的告警组（同一对象的告警合并）
class AlertGroup {
  final String objectKey;
  final List<SmsAlert> alerts;
  final bool isMuted;
  final int? muteUntil;

  const AlertGroup({
    required this.objectKey,
    required this.alerts,
    required this.isMuted,
    this.muteUntil,
  });
}

enum AlertGroupingMode { folded, flat }

/// AI 分析标签（agent 写 → app 读）
class AiTag {
  final int id;
  final String verdict; // duplicate / new-anomaly / unknown
  final String summary;
  final String action;  // OK / WATCH / URGENT

  const AiTag({
    required this.id,
    required this.verdict,
    required this.summary,
    required this.action,
  });
}