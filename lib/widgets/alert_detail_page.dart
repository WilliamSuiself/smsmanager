/// 告警详情页 — 完整 body + 元数据 + AI 标注 + 工单草稿
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../services/correlation_service.dart';
import '../state/alert_list_provider.dart';

class AlertDetailPage extends StatelessWidget {
  final SmsAlert alert;
  final AiTag? aiTag;

  const AlertDetailPage({super.key, required this.alert, this.aiTag});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(alert.receivedAt);
    final report = context.read<AlertListProvider>().correlateAlert(alert);

    return Scaffold(
      appBar: AppBar(
        title: Text(alert.type.label),
        backgroundColor: scheme.surface,
        actions: [
          IconButton(
            tooltip: '复制全文',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: alert.body));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: '复制为工单草稿',
            onPressed: () {
              final ticket = _buildTicketDraft(alert, fullTime);
              Clipboard.setData(ClipboardData(text: ticket));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('工单草稿已复制到剪贴板')),
              );
            },
            icon: const Icon(Icons.assignment_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SeverityChip(severity: alert.severity),
                if (aiTag != null) ...[
                  const SizedBox(width: 8),
                  _AiVerdictChip(tag: aiTag!),
                ],
              ],
            ),
            const SizedBox(height: 16),

            if (aiTag != null && aiTag!.summary.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 判断',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      aiTag!.summary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            _CorrelationCard(report: report, self: alert),
            const SizedBox(height: 16),

            _MetadataCard(
              rows: [
                ('发送方', alert.sender),
                ('时间', fullTime),
                ('类型', alert.type.label),
                ('严重度', alert.severity.label),
                ('对象', AlertListProvider.extractObjectKey(alert)),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              '告警内容',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
                alert.body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 生成工单草稿（Markdown 格式，可粘贴到工单系统）
  static String _buildTicketDraft(SmsAlert alert, String fullTime) {
    final sevLabel = alert.severity.label;
    final typeLabel = alert.type.label;
    final objKey = AlertListProvider.extractObjectKey(alert);
    return '''
# 工单草稿 — $typeLabel · $sevLabel

**对象**: `$objKey`
**时间**: $fullTime
**类型**: $typeLabel
**严重度**: $sevLabel

## 告警内容

> ${alert.body.replaceAll('\n', '\n> ')}

---
*抄送自 CCB Alert · ${DateTime.now().toIso8601String()}*
''';
  }
}

class _SeverityChip extends StatelessWidget {
  final AlertSeverity severity;
  const _SeverityChip({required this.severity});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late Color bg;
    late Color fg;
    late IconData icon;
    switch (severity) {
      case AlertSeverity.critical:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        icon = Icons.priority_high;
        break;
      case AlertSeverity.info:
        bg = scheme.tertiaryContainer;
        fg = scheme.onTertiaryContainer;
        icon = Icons.info_outline;
        break;
      case AlertSeverity.ticket:
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
        icon = Icons.assignment_outlined;
        break;
      case AlertSeverity.unknown:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        icon = Icons.help_outline;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(
            severity.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _AiVerdictChip extends StatelessWidget {
  final AiTag tag;
  const _AiVerdictChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late IconData icon;
    late String label;
    switch (tag.action) {
      case 'OK':
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        icon = Icons.check_circle_outline;
        label = '重复';
        break;
      case 'URGENT':
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        icon = Icons.warning_amber;
        label = '新异常';
        break;
      default:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        icon = Icons.visibility_outlined;
        label = '关注';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

/// 关联分析卡片：综合判定 + 统计 + 爆发 + 语义相似告警
class _CorrelationCard extends StatelessWidget {
  final CorrelationReport report;
  final SmsAlert self;

  const _CorrelationCard({required this.report, required this.self});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '关联分析',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              _VerdictChip(verdict: report.verdict),
            ],
          ),
          const SizedBox(height: 12),

          // 同对象统计
          Text(
            '对象 ${report.objectKey}：累计 ${report.sameObjectTotal} 次'
            ' · 近 24h ${report.sameObject24h} 次'
            ' · 近 7 天 ${report.sameObject7d} 次',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (report.lastSeenBefore != null) ...[
            const SizedBox(height: 4),
            Text(
              '距上次告警 ${_fmtGap(self.receivedAt.difference(report.lastSeenBefore!))}'
              '（${DateFormat('MM-dd HH:mm').format(report.lastSeenBefore!)}）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],

          // 历史发生时间（同对象，不含本次，最多 5 条）— "分别是什么时间"
          if (report.sameObject.where((a) => a.id != self.id).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '历史发生: ${report.sameObject.where((a) => a.id != self.id).take(5).map((a) => DateFormat('MM-dd HH:mm').format(a.receivedAt)).join(' / ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],

          // 与上一次相比有什么差别 — "和本次有什么差别"
          if (report.diffFromPrevious != null) ...[
            const SizedBox(height: 4),
            Text(
              '与上次相比: ${report.diffFromPrevious}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],

          // 同对象的季度 / 年度分布（周期性告警：季末批量、年末结息等）
          if (report.sameObjectTotal > 1) ...[
            const SizedBox(height: 4),
            Text(
              '历史分布：${report.sameObjectByQuarter.entries.take(6).map((e) => '${e.key}×${e.value}').join(' · ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (report.sameObjectYears.length > 1)
              Text(
                '覆盖年份：${report.sameObjectYears.join(' / ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
          ],

          // 同期爆发
          if (report.burst.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '同期 ±30 分钟内另有 ${report.burst.length} 条告警'
              '${report.burst.length >= CorrelationService.stormCount ? '（疑似告警风暴）' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: report.burst.length >= CorrelationService.stormCount
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontWeight: report.burst.length >= CorrelationService.stormCount
                        ? FontWeight.w600
                        : null,
                  ),
            ),
          ],

          // 语义相似告警
          if (report.similar.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              '相似告警（向量库 Top ${report.similar.length}）',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            for (final s in report.similar.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  final provider = context.read<AlertListProvider>();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlertDetailPage(
                        alert: s.alert,
                        aiTag: provider.aiTags[s.alert.id],
                      ),
                    ),
                  );
                },
                leading: Text(
                  '${(s.score * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                title: Text(
                  s.alert.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                subtitle: Text(
                  '${AlertListProvider.extractObjectKey(s.alert)} · '
                  '${DateFormat('MM-dd HH:mm').format(s.alert.receivedAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _fmtGap(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} 天';
    if (d.inHours >= 1) return '${d.inHours} 小时';
    return '${d.inMinutes} 分钟';
  }
}

/// 关联判定结论 chip
class _VerdictChip extends StatelessWidget {
  final CorrelationVerdict verdict;
  const _VerdictChip({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late Color bg;
    late Color fg;
    late IconData icon;
    switch (verdict) {
      case CorrelationVerdict.storm:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        icon = Icons.thunderstorm_outlined;
        break;
      case CorrelationVerdict.frequent:
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade900;
        icon = Icons.repeat_one_outlined;
        break;
      case CorrelationVerdict.recurring:
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
        icon = Icons.history_outlined;
        break;
      case CorrelationVerdict.firstSeen:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        icon = Icons.fiber_new_outlined;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            verdict.label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
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