/// 待办事项
///
/// 由待办类短信（[SmsCategory.todo]）自动生成，用户可手动勾选完成。
library;

class TodoItem {
  /// 关联的短信 id（用于去重：同一条短信不会重复生成待办）
  final int messageId;

  /// 待办标题（短信摘要）
  final String title;

  final DateTime createdAt;

  final bool done;

  const TodoItem({
    required this.messageId,
    required this.title,
    required this.createdAt,
    this.done = false,
  });

  TodoItem copyWith({bool? done}) => TodoItem(
        messageId: messageId,
        title: title,
        createdAt: createdAt,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'title': title,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'done': done,
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      messageId: (json['messageId'] as num).toInt(),
      title: json['title'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? 0,
      ),
      done: json['done'] as bool? ?? false,
    );
  }
}
