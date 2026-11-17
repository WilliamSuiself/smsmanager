/// 设置页：折叠模式 / 黑名单 / 静音管理 / 数据导出 / 关于
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../state/app_provider.dart';

class SettingsPage extends StatelessWidget {
  final AppProvider provider;
  const SettingsPage({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = provider.mutedObjects;
    final blacklist = provider.blacklist.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            const _SectionHeader('浏览'),
            // 折叠 / 平铺
            ListTile(
              leading: const Icon(Icons.view_agenda_outlined),
              title: const Text('列表模式'),
              subtitle: Text(provider.mode == AlertGroupingMode.folded
                  ? '折叠（按告警对象分组）'
                  : '平铺（每条告警一行）'),
              trailing: SegmentedButton<AlertGroupingMode>(
                segments: const [
                  ButtonSegment(value: AlertGroupingMode.folded, label: Text('折叠')),
                  ButtonSegment(value: AlertGroupingMode.flat, label: Text('平铺')),
                ],
                selected: {provider.mode},
                onSelectionChanged: (_) => provider.toggleGroupingMode(),
                showSelectedIcon: false,
              ),
            ),

            const _SectionHeader('黑名单'),
            if (blacklist.isEmpty)
              const ListTile(
                leading: Icon(Icons.block_outlined),
                title: Text('没有拉黑的号码'),
                subtitle: Text('在短信详情页或消息卡片左滑可拉黑发件人'),
              )
            else
              for (final s in blacklist)
                ListTile(
                  leading: const Icon(Icons.block, size: 20),
                  title: Text(s),
                  trailing: TextButton(
                    onPressed: () => provider.unblockSender(s),
                    child: const Text('移除'),
                  ),
                ),

            const _SectionHeader('静音管理'),
            if (muted.isEmpty)
              const ListTile(
                leading: Icon(Icons.notifications_off_outlined),
                title: Text('没有静音的对象'),
                subtitle: Text('在告警卡片上左滑可静音 24 小时'),
              )
            else
              for (final e in muted)
                ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '静音至 ${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e.value))}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () => provider.unmuteObject(e.key),
                    child: const Text('解除'),
                  ),
                ),

            const _SectionHeader('数据'),
            ListTile(
              leading: const Icon(Icons.sync_outlined),
              title: const Text('重新同步短信'),
              subtitle: const Text('拉取最近短信，合并进本地库'),
              trailing: provider.loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: provider.loading ? null : provider.reload,
            ),
            ListTile(
              leading: const Icon(Icons.data_object_outlined),
              title: const Text('导出告警数据'),
              subtitle: Text(provider.alerts.isEmpty
                  ? '暂无数据'
                  : '共 ${provider.alerts.length} 条，导出 alerts.json'),
              onTap: () async {
                final path = await provider.exportAlertsJson();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(path != null ? '已导出到 $path' : '没有可导出的数据'),
                  ));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('向量库规模'),
              subtitle: Text('${provider.vectorStoreSize} 条告警已建立语义索引'),
            ),

            const _SectionHeader('关于'),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('隐私说明'),
              subtitle: Text('数据 100% 本地存储，App 完全不联网，不上传任何短信内容'),
            ),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('短信汇聚分析 v0.1'),
              subtitle: Text('Flutter + Material 3 · 通用短信汇聚分析'),
            ),
          ]),
        ),
      ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
