// 入口 - 短信汇聚分析器
// 数据完全本地化，不联网；短信读取走自建 MethodChannel (Android only)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'models/alert.dart';
import 'models/sms_message.dart';
import 'services/ccb_parser.dart';
import 'services/sms_service.dart';
import 'state/app_provider.dart';
import 'widgets/alert_card.dart';
import 'widgets/alert_detail_page.dart';
import 'widgets/alert_group_card.dart';
import 'widgets/category_page.dart';
import 'widgets/ledger_page.dart';
import 'widgets/message_card.dart';
import 'widgets/message_detail_page.dart';
import 'widgets/search_page.dart';
import 'widgets/settings_page.dart';
import 'widgets/todo_page.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final provider = AppProvider();
        provider.bootstrap().then((_) async {
          provider.exportAlertsJson().then((path) {
            if (path != null) debugPrint('[CCB-Alert] exported alerts to $path');
          });
          // 启动弹窗：上次打开 → 本次打开之间的新增告警
          _showNewAlertsDialog(provider);
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

/// 点通知直达详情：优先在全量消息 / 已入库告警里按正文匹配；
/// 同步还没追上来时用携带参数兜底构造告警详情。
/// 同时触发一次增量同步，让这条新短信立刻进库 / 进列表 / 进向量库。
void _openLaunchAlert(Map<String, dynamic> data, AppProvider provider) {
  final body = data['body'] as String? ?? '';
  final sender = data['sender'] as String? ?? '';
  final at = (data['at'] as num?)?.toInt() ?? 0;
  if (body.isEmpty) return;

  provider.reload();

  // 优先匹配全量消息（账务 / 待办 / 重要紧急等分类详情）
  for (final m in provider.messages) {
    if (m.body == body) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => MessageDetailPage(message: m)),
      );
      return;
    }
  }

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

/// 启动弹窗：展示上次打开到本次打开之间的新增告警（点条目进详情）
void _showNewAlertsDialog(AppProvider provider) {
  if (provider.newSinceLastOpen.isEmpty) return;
  // 等 MaterialApp 首帧渲染完再弹，避免 navigator 不可用
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final nav = _navigatorKey.currentState;
    if (nav == null || !nav.context.mounted) return;
    final alerts = List.of(provider.newSinceLastOpen);
    showDialog(
      context: nav.context,
      barrierDismissible: true,
      builder: (ctx) => _NewAlertsDialog(alerts: alerts, provider: provider),
    );
  });
}

class _NewAlertsDialog extends StatelessWidget {
  final List<SmsAlert> alerts;
  final AppProvider provider;
  const _NewAlertsDialog({required this.alerts, required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final from = provider.lastOpenAt;
    final range = from == null
        ? '上次打开以来'
        : '自 ${DateFormat('MM-dd HH:mm').format(from)} 以来';
    return AlertDialog(
      title: Text('新增告警 ${alerts.length} 条',
          style: TextStyle(color: scheme.error)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(range,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: alerts.length,
                itemBuilder: (_, i) {
                  final a = alerts[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.severity == AlertSeverity.critical
                          ? Icons.error
                          : Icons.warning_amber_outlined,
                      color: a.severity == AlertSeverity.critical
                          ? scheme.error
                          : Colors.orange,
                    ),
                    title: Text(
                      a.body.length > 40
                          ? '${a.body.substring(0, 40)}…'
                          : a.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${a.type.label} · ${DateFormat('MM-dd HH:mm').format(a.receivedAt)}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      provider.dismissNewAlerts();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AlertDetailPage(
                            alert: a, aiTag: provider.aiTags[a.id]),
                      ));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            provider.dismissNewAlerts();
            Navigator.of(context).pop();
          },
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class CcbAlertApp extends StatelessWidget {
  const CcbAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '短信汇聚分析',
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          MessageListPage(),
          AlertListPage(),
          LedgerPage(),
          TodoPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sms_outlined), selectedIcon: Icon(Icons.sms), label: '消息'),
          NavigationDestination(icon: Icon(Icons.star_outline), selectedIcon: Icon(Icons.star), label: '关注'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: '账本'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: '待办'),
        ],
      ),
    );
  }
}

/// 消息页：全量短信 + 分类筛选（账务 / 重要紧急 / 待办 / 垃圾 / 其他）
class MessageListPage extends StatelessWidget {
  const MessageListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          if (provider.gate == PermissionGate.granted) ...[
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
          IconButton(
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPage(provider: provider),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (provider.gate == PermissionGate.granted)
            _CategoryFilterBar(provider: provider),
          Expanded(
            child: _MessagesBody(
                gate: provider.gate,
                loading: provider.loading,
                error: provider.error),
          ),
        ],
      ),
    );
  }
}

/// 分类筛选 chip 栏：全部 / 账务 / 重要紧急 / 待办 / 垃圾 / 其他
class _CategoryFilterBar extends StatelessWidget {
  final AppProvider provider;
  const _CategoryFilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final counts = provider.categoryCounts;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: '全部',
            selected: provider.filter == null,
            onTap: () => provider.setFilter(null),
          ),
          for (final c in SmsCategory.values)
            _FilterChip(
              label: '${c.label}(${counts[c] ?? 0})',
              selected: provider.filter == c,
              onTap: () => provider.setFilter(c),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _MessagesBody extends StatelessWidget {
  final PermissionGate gate;
  final bool loading;
  final String? error;

  const _MessagesBody({
    required this.gate,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.read<AppProvider>();

    if (gate == PermissionGate.denied) {
      return _PermissionPrompt(provider: provider, scheme: scheme);
    }
    if (gate == PermissionGate.unknown) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loading && provider.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) return _ErrorView(error: error!, provider: provider);

    final visible = context.watch<AppProvider>().visibleMessages;
    if (visible.isEmpty) {
      return _EmptyView(scheme: scheme, provider: provider, message: '没有找到符合当前筛选条件的短信。');
    }

    return RefreshIndicator(
      onRefresh: provider.reload,
      child: ListView.separated(
        itemCount: visible.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final m = visible[i];
          return MessageCard(
            message: m,
            onTap: () {
              provider.markRead(m.id);
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => MessageDetailPage(message: m)),
              );
            },
            onMarkRead: () => provider.markRead(m.id),
            onBlockSender: () => provider.blockSender(m.sender),
          );
        },
      ),
    );
  }
}

/// 关注页：关注号码的短信 + 告警类短信的汇聚分析视图
///
/// 页面顶部可直接注册关注号码；注册的号码发来的短信会全量收录进这里。
class AlertListPage extends StatelessWidget {
  const AlertListPage({super.key});

  void _addSender(BuildContext context, AppProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加关注号码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '如 95533 / 106980095533 / 13800138000',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final s = controller.text.trim();
              if (s.isNotEmpty) provider.addWatchSender(s);
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关注'),
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
              tooltip: '分类',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CategoryPage(provider: provider),
                ),
              ),
              icon: const Icon(Icons.category_outlined),
            ),
            IconButton(
              tooltip: '搜索',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchPage(provider: provider),
                ),
              ),
              icon: const Icon(Icons.search_outlined),
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
      body: Column(
        children: [
          _WatchlistBar(provider: provider, onAdd: () => _addSender(context, provider)),
          Expanded(
            child: _Body(
                gate: provider.gate,
                loading: provider.loading,
                error: provider.error),
          ),
        ],
      ),
    );
  }
}

/// 关注号码栏：已注册号码以 chip 展示（点 × 移除），末尾「添加」注册新号码
class _WatchlistBar extends StatelessWidget {
  final AppProvider provider;
  final VoidCallback onAdd;
  const _WatchlistBar({required this.provider, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Center(
            child: Text(
              '关注号码',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          for (final s in provider.watchlist)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                label: Text(s),
                onDeleted: () => provider.removeWatchSender(s),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(provider.watchlist.isEmpty ? '添加关注号码' : '添加'),
            onPressed: onAdd,
          ),
        ],
      ),
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
    final provider = context.read<AppProvider>();

    if (gate == PermissionGate.denied) return _PermissionPrompt(provider: provider, scheme: scheme);
    if (gate == PermissionGate.unknown) return const Center(child: CircularProgressIndicator());
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorView(error: error!, provider: provider);

    final visibleAlerts = provider.visibleAlerts;
    if (visibleAlerts.isEmpty) {
      return _EmptyView(
          scheme: scheme, provider: provider, message: '添加关注号码，或等待告警类短信到达。');
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
  final AppProvider provider;
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
              '用于在本地分类与汇聚分析短信，\n数据 100% 在本地，不联网。',
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
  final AppProvider provider;
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
  final AppProvider provider;
  final String message;
  const _EmptyView(
      {required this.scheme, required this.provider, required this.message});

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
            Text('暂无收录短信', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
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
        final provider = ctx.read<AppProvider>();
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