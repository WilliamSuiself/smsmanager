/// 折叠后的告警组卡片（同一对象的多条告警合并）
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/alert.dart';
import '../state/alert_list_provider.dart';
import 'alert_card.dart';
import 'alert_detail_page.dart';

class AlertGroupCard extends StatefulWidget {
  final AlertGroup group;
  const AlertGroupCard({super.key, required this.group});

  @override
  State<AlertGroupCard> createState() => _AlertGroupCardState();
}

class _AlertGroupCardState extends State<AlertGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = widget.group;
    final count = group.alerts.length;
    final latest = group.alerts.first;
    final firstSev = group.alerts.first.severity;

    late Color sevDot;
    switch (firstSev) {
      case AlertSeverity.critical:
        sevDot = scheme.error;
        break;
      case AlertSeverity.info:
        sevDot = scheme.tertiary;
        break;
      case AlertSeverity.ticket:
        sevDot = scheme.secondary;
        break;
      case AlertSeverity.unknown:
        sevDot = scheme.outline;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            // 点卡片 → 直达该对象最新告警的详情页（最新告警是最受关注的）
            onTap: () {
              final provider = context.read<AlertListProvider>();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlertDetailPage(
                    alert: latest,
                    aiTag: provider.aiTags[latest.id],
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: sevDot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.objectKey,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '× $count',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          latest.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '最新: ${DateFormat('MM-dd HH:mm').format(latest.receivedAt)}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                            const Spacer(),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () =>
                                  setState(() => _expanded = !_expanded),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                child: Text(
                                  _expanded ? '收起 ▴' : '展开 ▾',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: scheme.primary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  const Divider(height: 1, indent: 12, endIndent: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final provider = context.read<AlertListProvider>();
                              provider.muteObject(group.objectKey, hours: 24);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('已静音 ${group.objectKey}（24小时）'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.volume_off_outlined, size: 16),
                            label: const Text('静音 24 小时'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final a in group.alerts.take(5))
                    ListTile(
                      dense: true,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AlertDetailPage(alert: a),
                          ),
                        );
                      },
                      leading: Icon(Icons.fiber_manual_record, size: 8, color: sevDot),
                      title: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(a.receivedAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      subtitle: Text(
                        a.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (group.alerts.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AlertGroupPage(group: group),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list_alt_outlined, size: 16),
                        label: Text('查看全部 ${group.alerts.length} 条'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 分组内全部告警列表页（组内 >5 条时从「查看全部」进入）
class AlertGroupPage extends StatelessWidget {
  final AlertGroup group;
  const AlertGroupPage({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AlertListProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text('${group.objectKey} · ${group.alerts.length} 条'),
      ),
      body: ListView.separated(
        itemCount: group.alerts.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final a = group.alerts[i];
          return AlertCard(
            alert: a,
            aiTag: provider.aiTags[a.id],
            correlation: provider.correlateAlert(a),
            onTap: () {
              Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => AlertDetailPage(
                    alert: a,
                    aiTag: provider.aiTags[a.id],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}