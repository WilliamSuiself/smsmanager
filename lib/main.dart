// 入口 - 建行告警短信本地管理 App
// 数据完全本地化，不联网；所有短信读取走 flutter_sms_inbox (Android only)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/alert.dart';
import 'services/ccb_parser.dart';
import 'services/sms_service.dart';
import 'state/alert_list_provider.dart';
import 'widgets/alert_card.dart';
import 'widgets/alert_detail_page.dart';
import 'widgets/alert_group_card.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final provider = AlertListProvider();
        provider.bootstrap().then((_) async {
          provider.exportAlertsJson().then((path) {
            if (path != null) debugPrint('[CCB-Alert] exported alerts to $path');
          });
          // 冷启动：点系统通知直达该告警详情
          final launch = await SmsService.consumeLaunchAlert();
          if (launch != null) _openLaunchAlert(launch, provider);
        });
        // 热态（App 活着时）点通知：原生 onNewIntent 主动推过来
        SmsService.setLaunchAlertHandler(
          (data) => _openLaunchAlert(data, provider),
        );
        return provider;
      },
      child: const CcbAlertApp(),
    ),
  );
}

/// 点通知直达详情：优先在已入库告警里按正文匹配；同步还没追上来时用携带参数兜底构造。
/// 同时触发一次增量同步，让这条新告警立刻进库 / 进列表 / 进向量库。
void _openLaunchAlert(Map<String, dynamic> data, AlertListProvider provider) {
  final body = data['body'] as String? ?? '';
  final sender = data['sender'] as String? ?? '';
  final at = (data['at'] as num?)?.toInt() ?? 0;
  if (body.isEmpty) return;

  provider.reload();

  SmsAlert? match;
  for (final a in provider.alerts) {
    if (a.body == body) {
      match = a;
      break;
    }
  }
  final alert = match ??
      CcbParser.parse(
        id: -1,
        sender: sender.isEmpty ? '95533' : sender,
        body: body,
        receivedAt:
            at > 0 ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.now(),
      );

  _navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) =>
          AlertDetailPage(alert: alert, aiTag: provider.aiTags[alert.id]),
    ),
  );
}

class CcbAlertApp extends StatelessWidget {
  const CcbAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '短信管理',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005BAC),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005BAC),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const AlertListPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: '告警'),
          NavigationDestination(icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: '分类'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

class AlertListPage extends StatelessWidget {
  const AlertListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlertListProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('短信管理'),
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          if (provider.gate == PermissionGate.granted) ...[
            IconButton(
              tooltip: provider.mode == AlertGroupingMode.folded
                  ? '切换为平铺'
                  : '切换为折叠',
              onPressed: provider.toggleGroupingMode,
              icon: Icon(provider.mode == AlertGroupingMode.folded
                  ? Icons.view_agenda_outlined
                  : Icons.view_headline_outlined),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: provider.loading ? null : provider.reload,
              icon: provider.loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ],
      ),
      body: _Body(gate: provider.gate, loading: provider.loading, error: provider.error),
    );
  }
}

class _Body extends StatelessWidget {
  final PermissionGate gate;
  final bool loading;
  final String? error;

  const _Body({
    required this.gate,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.read<AlertListProvider>();

    if (gate == PermissionGate.denied) return _PermissionPrompt(provider: provider, scheme: scheme);
    if (gate == PermissionGate.unknown) return const Center(child: CircularProgressIndicator());
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorView(error: error!, provider: provider);

    final visibleAlerts = provider.visibleAlerts;
    if (visibleAlerts.isEmpty) {
      return _EmptyView(scheme: scheme, provider: provider);
    }

    return RefreshIndicator(
      onRefresh: provider.reload,
      child: provider.mode == AlertGroupingMode.folded
          ? _FoldedList(groups: provider.groups)
          : _FlatList(alerts: visibleAlerts, aiTags: provider.aiTags),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  final AlertListProvider provider;
  final ColorScheme scheme;
  const _PermissionPrompt({required this.provider, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 72, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('需要短信权限', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'CCB Alert 只读取建行 95533 等号码段，\n数据 100% 在本地，不联网。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: provider.requestPermission,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('授权短信权限'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final AlertListProvider provider;
  const _ErrorView({required this.error, required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('读取短信时出错', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(error, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: provider.reload,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final ColorScheme scheme;
  final AlertListProvider provider;
  const _EmptyView({required this.scheme, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 72, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('还没有建行告警', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '没有找到来自 95533 等号码段的告警短信。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: provider.reload,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 折叠列表（按告警对象分组）
class _FoldedList extends StatelessWidget {
  final List<AlertGroup> groups;
  const _FoldedList({required this.groups});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length,
      itemBuilder: (_, i) => AlertGroupCard(group: groups[i]),
    );
  }
}

/// 平铺列表（每条告警一行，含 AI 标签）
class _FlatList extends StatelessWidget {
  final List<SmsAlert> alerts;
  final Map<int, AiTag> aiTags;
  const _FlatList({required this.alerts, required this.aiTags});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: alerts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final a = alerts[i];
        final provider = ctx.read<AlertListProvider>();
        return AlertCard(
          alert: a,
          aiTag: aiTags[a.id],
          correlation: provider.correlateAlert(a),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AlertDetailPage(alert: a, aiTag: aiTags[a.id]),
              ),
            );
          },
        );
      },
    );
  }
}