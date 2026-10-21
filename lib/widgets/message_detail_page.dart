/// 短信详情页 — 完整正文 + 分类建议 + 快捷操作
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sms_message.dart';
import '../state/message_list_provider.dart';

class MessageDetailPage extends StatelessWidget {
  final SmsMessage message;

  const MessageDetailPage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(message.receivedAt);
    final provider = context.read<MessageListProvider>();
    final isBlacklisted = provider.blacklist.contains(message.sender);

    return Scaffold(
      appBar: AppBar(
        title: Text(message.category.label),
        backgroundColor: scheme.surface,
        actions: [
          IconButton(
            tooltip: '复制全文',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message.body));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SuggestionCard(category: message.category),
            const SizedBox(height: 16),

            _MetadataCard(
              rows: [
                ('发送方', message.sender),
                ('时间', fullTime),
                ('分类', message.category.label),
                ('置信度', '${(message.confidence * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              '短信内容',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SelectableText(
                message.body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),

            if (message.category == SmsCategory.spam || !isBlacklisted)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isBlacklisted
                      ? null
                      : () async {
                          await provider.blockSender(message.sender);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已将 ${message.sender} 加入黑名单')),
                            );
                          }
                        },
                  icon: const Icon(Icons.block),
                  label: Text(isBlacklisted ? '该号码已在黑名单中' : '将该号码加入黑名单'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 处理建议卡片（对应用户看到这条短信后得到的结论）
class _SuggestionCard extends StatelessWidget {
  final SmsCategory category;
  const _SuggestionCard({required this.category});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (category) {
      SmsCategory.urgent => (scheme.errorContainer, scheme.onErrorContainer, Icons.priority_high),
      SmsCategory.finance => (Colors.green.shade50, Colors.green.shade800, Icons.check_circle_outline),
      SmsCategory.todo => (Colors.amber.shade50, Colors.amber.shade900, Icons.event_note_outlined),
      SmsCategory.spam => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.report_gmailerrorred_outlined),
      SmsCategory.other => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.suggestion,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final List<(String, String)> rows;
  const _MetadataCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      rows[i].$1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      rows[i].$2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}
