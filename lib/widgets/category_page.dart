/// 分类页：按告警类型 / 严重度统计并分类浏览
///
/// 结构：
///   - 顶部统计卡（总数 / 主要五级 / 次要六级 / 工单）
///   - 类型分组列表（系统告警 / 业务告警 / 监控 / 异常 / 工单）
///   - 点任意分组 → 进入该类型的告警列表（复用详情页跳转）
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../state/app_provider.dart';
import 'alert_detail_page.dart';

class CategoryPage extends StatelessWidget {
  final AppProvider provider;
  const CategoryPage({super.key, required this.provider});

  static const _typeIcon = {
    AlertType.alert: Icons.error_outline,
    AlertType.opsTask: Icons.assignment_outlined,
    AlertType.accountActivity: Icons.account_balance_wallet_outlined,
  };

  static const _typeColor = {
    AlertType.alert: Color(0xFFD32F2F),
    AlertType.opsTask: Color(0xFF7B1FA2),
    AlertType.accountActivity: Color(0xFF2E7D32),
  };

  @override
  Widget build(BuildContext context) {
    final alerts = provider.visibleAlerts;
    final scheme = Theme.of(context).colorScheme;

    // 按类型分组
    final byType = <AlertType, List<SmsAlert>>{};
    for (final a in alerts) {
      byType.putIfAbsent(a.type, () => []).add(a);
    }
    final types = byType.keys.toList()
      ..sort((a, b) => byType[b]!.length.compareTo(byType[a]!.length));

    final critical = alerts.where((a) => a.severity == AlertSeverity.critical).length;
    final info = alerts.where((a) => a.severity == AlertSeverity.info).length;
    final ticket = alerts.where((a) => a.severity == AlertSeverity.ticket).length;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('分类'),
          backgroundColor: scheme.surface,
          scrolledUnderElevation: 0,
          pinned: true,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _StatCard(label: '全部', count: alerts.length, color: scheme.primary),
                const SizedBox(width: 8),
                _StatCard(label: '主要五级', count: critical, color: scheme.error),
                const SizedBox(width: 8),
                _StatCard(label: '次要六级', count: info, color: Colors.orange),
                const SizedBox(width: 8),
                _StatCard(label: '工单', count: ticket, color: scheme.secondary),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final t = types[i];
              final list = byType[t]!;
              final latest = list.first.receivedAt;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: (_typeColor[t] ?? Colors.grey).withValues(alpha: 0.12),
                  child: Icon(_typeIcon[t] ?? Icons.help_outline,
                      color: _typeColor[t] ?? Colors.grey, size: 22),
                ),
                title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '最新 ${DateFormat('MM-dd HH:mm').format(latest)}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                trailing: Text('${list.length}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
                onTap: () => _openType(context, t, list),
              );
            },
            childCount: types.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  void _openType(BuildContext context, AlertType type, List<SmsAlert> list) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _TypeAlertListPage(type: type, alerts: list, provider: provider),
    ));
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatCard({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 某一类型的告警列表页
class _TypeAlertListPage extends StatelessWidget {
  final AlertType type;
  final List<SmsAlert> alerts;
  final AppProvider provider;
  const _TypeAlertListPage({required this.type, required this.alerts, required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('${type.label}（${alerts.length}）')),
      body: ListView.separated(
        itemCount: alerts.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final a = alerts[i];
          return ListTile(
            leading: Icon(
              a.severity == AlertSeverity.critical ? Icons.error : Icons.warning_amber_outlined,
              color: a.severity == AlertSeverity.critical ? scheme.error : Colors.orange,
            ),
            title: Text(
              a.body.length > 50 ? '${a.body.substring(0, 50)}…' : a.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(a.receivedAt),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AlertDetailPage(alert: a, aiTag: provider.aiTags[a.id]),
            )),
          );
        },
      ),
    );
  }
}
