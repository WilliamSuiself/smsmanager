/// 设置页：黑名单管理 + 关于
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/message_list_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessageListProvider>();
    final scheme = Theme.of(context).colorScheme;
    final blacklist = provider.blacklist.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: scheme.surface,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '号码黑名单',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (blacklist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '还没有拉黑任何号码。在短信详情页可以把骚扰/垃圾短信的发件号码加入黑名单。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (final sender in blacklist)
              ListTile(
                leading: const Icon(Icons.block),
                title: Text(sender),
                trailing: TextButton(
                  onPressed: () => provider.unblockSender(sender),
                  child: const Text('移除'),
                ),
              ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '关于',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('隐私承诺'),
            subtitle: Text('所有短信分类、记账、待办均在本地设备上计算，不联网，不上传任何短信内容。'),
          ),
        ],
      ),
    );
  }
}
