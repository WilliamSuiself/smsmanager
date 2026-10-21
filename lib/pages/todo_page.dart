/// 待办页：展示由短信自动生成的待办事项
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/message_list_provider.dart';

class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessageListProvider>();
    final scheme = Theme.of(context).colorScheme;
    final todos = provider.todos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('待办'),
        backgroundColor: scheme.surface,
      ),
      body: todos.isEmpty
          ? Center(
              child: Text(
                '还没有待办事项\n收到快递/预约/续费等提醒短信后会自动显示在这里',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              itemCount: todos.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final todo = todos[i];
                return CheckboxListTile(
                  value: todo.done,
                  onChanged: (v) => provider.toggleTodo(todo.messageId, v ?? false),
                  title: Text(
                    todo.title,
                    style: TextStyle(
                      decoration: todo.done ? TextDecoration.lineThrough : null,
                      color: todo.done ? scheme.onSurfaceVariant : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    DateFormat('MM-dd HH:mm').format(todo.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
    );
  }
}
