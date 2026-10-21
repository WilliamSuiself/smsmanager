/// 短信列表 Provider
///
/// 持有分类后的 [SmsMessage] 列表 + 加载状态，并联动账本 / 待办 / 黑名单。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ledger_entry.dart';
import '../models/sms_message.dart';
import '../models/todo_item.dart';
import '../services/blacklist_store.dart';
import '../services/finance_parser.dart';
import '../services/ledger_store.dart';
import '../services/message_store.dart';
import '../services/permission_service.dart';
import '../services/sms_classifier.dart';
import '../services/sms_service.dart';
import '../services/todo_store.dart';

/// 三态权限：未检查 / 已授权 / 已拒绝（含永久拒绝）
enum PermissionGate { unknown, granted, denied }

class MessageListProvider extends ChangeNotifier {
  bool _loading = false;
  String? _error;
  PermissionGate _gate = PermissionGate.unknown;

  /// 当前按分类筛选（null = 全部）
  SmsCategory? _filter;

  final MessageStore _messageStore = MessageStore();
  final LedgerStore _ledgerStore = LedgerStore();
  final TodoStore _todoStore = TodoStore();
  final BlacklistStore _blacklistStore = BlacklistStore();

  File? _messageFile;
  File? _ledgerFile;
  File? _todoFile;

  /// 增量查询的重叠窗口：防止同步间隙内到达的短信漏抓
  static const int _syncOverlapMs = 10 * 60 * 1000;

  bool get loading => _loading;
  String? get error => _error;
  PermissionGate get gate => _gate;
  SmsCategory? get filter => _filter;

  List<SmsMessage> get messages => _messageStore.all;

  /// 当前筛选下可见的短信
  List<SmsMessage> get visibleMessages {
    if (_filter == null) return messages;
    return messages.where((m) => m.category == _filter).toList();
  }

  List<LedgerEntry> get ledgerEntries => _ledgerStore.all;
  List<TodoItem> get todos => _todoStore.all;
  Set<String> get blacklist => _blacklistStore.senders;

  /// 每个分类下的短信数量（供 UI 筛选 chip 展示角标）
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

  Future<void> _loadLocalData() async {
    final dir = await getApplicationSupportDirectory();
    _messageFile = File('${dir.path}/messages_store.json');
    _ledgerFile = File('${dir.path}/ledger_store.json');
    _todoFile = File('${dir.path}/todo_store.json');

    await _messageStore.loadFrom(_messageFile!);
    await _ledgerStore.loadFrom(_ledgerFile!);
    await _todoStore.loadFrom(_todoFile!);
    await _blacklistStore.load();

    if (_messageStore.size > 0) notifyListeners();
  }

  /// 检查权限 → 加载本地历史 → 申请（如未授权） → 增量同步短信
  Future<void> bootstrap() async {
    await _loadLocalData();
    final status = await PermissionService.currentStatus();
    _gate = status.isGranted ? PermissionGate.granted : PermissionGate.denied;
    notifyListeners();
    if (_gate == PermissionGate.granted) {
      await reload();
    }
  }

  Future<void> requestPermission() async {
    final status = await PermissionService.requestSms();
    _gate = status.isGranted ? PermissionGate.granted : PermissionGate.denied;
    notifyListeners();
    if (_gate == PermissionGate.granted) {
      await reload();
    }
  }

  /// 增量同步：拉取上次同步点之后的新短信，合并进本地库，
  /// 并为账务 / 待办类短信自动生成账本条目 / 待办事项。
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
      notifyListeners();
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

  /// 对单条短信重新跑一次分类（用于手动纠错入口预留）
  SmsCategory reclassify(SmsMessage m) {
    return SmsClassifier.classify(
      m.body,
      sender: m.sender,
      blacklist: _blacklistStore.senders,
    );
  }
}
