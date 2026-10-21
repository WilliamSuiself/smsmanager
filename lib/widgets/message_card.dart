/// 单条短信卡片
///
/// 显示：分类标签 + 处理建议 + 摘要 + 发送方 + 时间
/// 支持左滑快捷操作：标记已读 / 拉黑发件人
library;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../models/sms_message.dart';

class MessageCard extends StatelessWidget {
  final SmsMessage message;
  final VoidCallback? onTap;
  final VoidCallback? onMarkRead;
  final VoidCallback? onBlockSender;

  const MessageCard({
    super.key,
    required this.message,
    this.onTap,
    this.onMarkRead,
    this.onBlockSender,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = _styleFor(message.category, scheme);

    return Slidable(
      key: ValueKey(message.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          if (!message.read)
            SlidableAction(
              onPressed: (_) => onMarkRead?.call(),
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              icon: Icons.done,
              label: '已读',
            ),
          SlidableAction(
            onPressed: (_) => onBlockSender?.call(),
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
            icon: Icons.block,
            label: '拉黑',
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: bg,
          foregroundColor: fg,
          child: Icon(icon),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                message.category.label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: message.read ? FontWeight.w400 : FontWeight.w700,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              message.sender,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              _SuggestionChip(category: message.category),
            ],
          ),
        ),
        trailing: Text(
          DateFormat('MM-dd HH:mm').format(message.receivedAt),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  (Color, Color, IconData) _styleFor(SmsCategory category, ColorScheme scheme) {
    switch (category) {
      case SmsCategory.urgent:
        return (scheme.errorContainer, scheme.onErrorContainer, Icons.priority_high);
      case SmsCategory.finance:
        return (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.account_balance_wallet_outlined);
      case SmsCategory.todo:
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.event_note_outlined);
      case SmsCategory.spam:
        return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.report_gmailerrorred_outlined);
      case SmsCategory.other:
        return (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.sms_outlined);
    }
  }
}

/// 处理建议小芯片
class _SuggestionChip extends StatelessWidget {
  final SmsCategory category;
  const _SuggestionChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (category) {
      SmsCategory.urgent => (scheme.errorContainer, scheme.onErrorContainer),
      SmsCategory.finance => (Colors.green.shade50, Colors.green.shade800),
      SmsCategory.todo => (Colors.amber.shade50, Colors.amber.shade900),
      SmsCategory.spam => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      SmsCategory.other => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        category.suggestion,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500),
      ),
    );
  }
}
