/// 单条告警卡片（v0.7）
///
/// 显示：严重度标签 + body 摘要 + 发送方 + 时间 + AI 标签
/// 点击 → 跳转 AlertDetailPage 看完整内容
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../services/correlation_service.dart';
import '../state/alert_list_provider.dart';

class AlertCard extends StatelessWidget {
  final SmsAlert alert;
  final VoidCallback? onTap;
  final AiTag? aiTag;
  final CorrelationReport? correlation;

  const AlertCard({
    super.key,
    required this.alert,
    this.onTap,
    this.aiTag,
    this.correlation,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late Color dotColor;
    switch (alert.severity) {
      case AlertSeverity.critical:
        dotColor = scheme.error;
        break;
      case AlertSeverity.info:
        dotColor = scheme.tertiary;
        break;
      case AlertSeverity.ticket:
        dotColor = scheme.secondary;
        break;
      case AlertSeverity.unknown:
        dotColor = scheme.outline;
        break;
    }

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
        child: Icon(_iconFor(alert.type)),
      ),
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${alert.type.label} · ${alert.severity.label}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            alert.sender,
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
              alert.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (aiTag != null) ...[
              const SizedBox(height: 6),
              _AiTagChip(tag: aiTag!),
            ],
            if (correlation != null) ...[
              const SizedBox(height: 6),
              _CorrelationChip(report: correlation!),
            ],
          ],
        ),
      ),
      trailing: Text(
        DateFormat('MM-dd HH:mm').format(alert.receivedAt),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }

  IconData _iconFor(AlertType type) {
    switch (type) {
      case AlertType.systemAlert:
        return Icons.error_outline;
      case AlertType.businessAlert:
        return Icons.warning_amber_outlined;
      case AlertType.monitor:
        return Icons.monitor_heart_outlined;
      case AlertType.exception:
        return Icons.report_problem_outlined;
      case AlertType.opsTask:
        return Icons.assignment_late_outlined;
      case AlertType.unknown:
        return Icons.notifications_active_outlined;
    }
  }
}

/// 关联标记小芯片：复发次数 / 首次 / 风暴
class _CorrelationChip extends StatelessWidget {
  final CorrelationReport report;
  const _CorrelationChip({required this.report});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late Color bg;
    late Color fg;
    late String label;
    switch (report.verdict) {
      case CorrelationVerdict.storm:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        label = '风暴 · 同期${report.burst.length}条';
        break;
      case CorrelationVerdict.frequent:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade900;
        label = '高频 · 7天${report.sameObject7d}次';
        break;
      case CorrelationVerdict.recurring:
        bg = scheme.secondaryContainer.withValues(alpha: 0.6);
        fg = scheme.onSecondaryContainer;
        label = '复发 · 第${report.sameObjectTotal}次';
        break;
      case CorrelationVerdict.firstSeen:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        label = '首次出现';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// AI 标签小芯片（绿 = 重复 / 红 = 新异常 / 灰 = 未知）
class _AiTagChip extends StatelessWidget {
  final AiTag tag;
  const _AiTagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late Color bg;
    late Color fg;
    late IconData icon;
    late String label;

    switch (tag.action) {
      case 'OK':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        icon = Icons.check_circle_outline;
        label = 'AI: 重复告警';
        break;
      case 'URGENT':
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        icon = Icons.warning_amber;
        label = 'AI: 新异常';
        break;
      case 'WATCH':
      default:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        icon = Icons.visibility_outlined;
        label = 'AI: 关注';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}