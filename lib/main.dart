// 入口 - 通用短信管理 App
// 数据完全本地化，不联网；短信读取走自建 MethodChannel (Android only)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/sms_message.dart';
import 'pages/ledger_page.dart';
import 'pages/settings_page.dart';
import 'pages/todo_page.dart';
import 'services/sms_service.dart';
import 'state/message_list_provider.dart';
import 'widgets/message_card.dart';
import 'widgets/message_detail_page.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final provider = MessageListProvider();
        provider.bootstrap().then((_) async {
          // 冷启动：点系统通知直达该短信详情
          final launch = await SmsService.consumeLaunchAlert();
          if (launch != null) _openLaunchMessage(launch, provider);
        });
        // 热态（App 活着时）点通知：原生 onNewIntent 主动推过来
        SmsService.setLaunchAlertHandler(
          (data) => _openLaunchMessage(data, provider),
        );
        return provider;
      },
      child: const SmsManagerApp(),
    ),
  );
}

/// 点通知直达详情：优先在已入库短信里按正文匹配；同步还没追上来时兜底不跳转。
void _openLaunchMessage(Map<String, dynamic> data, MessageListProvider provider) {
  final body = data['body'] as String? ?? '';
  if (body.isEmpty) return;

  provider.reload();

  SmsMessage? match;
  for (final m in provider.messages) {
    if (m.body == body) {
      match = m;
      break;
    }
  }
  if (match == null) return;

  _navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => MessageDetailPage(message: match!)),
  );
}

class SmsManagerApp extends StatelessWidget {
  const SmsManagerApp({super.key});

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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const MessageListPage(),
      const LedgerPage(),
      const TodoPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sms_outlined), selectedIcon: Icon(Icons.sms), label: '消息'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: '账本'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: '待办'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

class MessageListPage extends StatelessWidget {
  const MessageListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessageListProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('短信管理'),
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          if (provider.gate == PermissionGate.granted)
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
      ),
      body: Column(
        children: [
          if (provider.gate == PermissionGate.granted) _CategoryFilterBar(provider: provider),
          Expanded(
            child: _Body(gate: provider.gate, loading: provider.loading, error: provider.error),
          ),
        ],
      ),
    );
  }
}

/// 分类筛选 chip 栏：全部 / 账务 / 重要紧急 / 待办 / 垃圾 / 其他
class _CategoryFilterBar extends StatelessWidget {
  final MessageListProvider provider;
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
  const _FilterChip({required this.label, required this.selected, required this.onTap});

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
    final provider = context.read<MessageListProvider>();

    if (gate == PermissionGate.denied) return _PermissionPrompt(provider: provider, scheme: scheme);
    if (gate == PermissionGate.unknown) return const Center(child: CircularProgressIndicator());
    if (loading && provider.messages.isEmpty) return const Center(child: CircularProgressIndicator());
    if (error != null) return _ErrorView(error: error!, provider: provider);

    final visible = context.watch<MessageListProvider>().visibleMessages;
    if (visible.isEmpty) {
      return _EmptyView(scheme: scheme, provider: provider);
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
                MaterialPageRoute(builder: (_) => MessageDetailPage(message: m)),
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

class _PermissionPrompt extends StatelessWidget {
  final MessageListProvider provider;
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
              '用于读取并本地分类短信，\n数据 100% 在本地，不联网。',
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
  final MessageListProvider provider;
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
  final MessageListProvider provider;
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
            Text('还没有短信', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '没有找到符合当前筛选条件的短信。',
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
