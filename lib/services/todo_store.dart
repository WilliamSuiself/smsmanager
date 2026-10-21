/// 待办事项持久化（todo_store.json）
library;

import 'dart:convert';
import 'dart:io';

import '../models/todo_item.dart';

class TodoStore {
  final Map<int, TodoItem> _byMessageId = {};

  int get size => _byMessageId.length;

  /// 全部待办，时间倒序（未完成在前）
  List<TodoItem> get all {
    final list = _byMessageId.values.toList()
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  bool contains(int messageId) => _byMessageId.containsKey(messageId);

  /// 新增一条待办（按 messageId 去重），返回是否为新增。
  bool add(TodoItem item) {
    if (_byMessageId.containsKey(item.messageId)) return false;
    _byMessageId[item.messageId] = item;
    return true;
  }

  void setDone(int messageId, bool done) {
    final item = _byMessageId[messageId];
    if (item != null) _byMessageId[messageId] = item.copyWith(done: done);
  }

  Future<void> loadFrom(File file) async {
    _byMessageId.clear();
    if (!file.existsSync()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      for (final item in data) {
        final todo = TodoItem.fromJson(item as Map<String, dynamic>);
        _byMessageId[todo.messageId] = todo;
      }
    } catch (_) {
      _byMessageId.clear();
    }
  }

  Future<void> saveTo(File file) async {
    await file.writeAsString(jsonEncode(all.map((e) => e.toJson()).toList()));
  }
}
