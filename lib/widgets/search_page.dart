/// 搜索页：全文搜索 + 类型/严重度/时间范围筛选
///
/// 纯本地、实时：输入即搜（body 包含关键词，不区分大小写），
/// 结果按时间倒序，点击进详情。
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../state/app_provider.dart';
import 'alert_detail_page.dart';

class SearchPage extends StatefulWidget {
  final AppProvider provider;
  const SearchPage({super.key, required this.provider});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';
  AlertSeverity? _severity;
  AlertType? _type;
  int _days = 0; // 0 = 不限

  static const _dayOptions = {0: '不限', 1: '24 小时', 7: '7 天', 30: '30 天'};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<SmsAlert> get _results {
    var list = widget.provider.visibleAlerts;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((a) => a.body.toLowerCase().contains(q)).toList();
    }
    if (_severity != null) {
      list = list.where((a) => a.severity == _severity).toList();
    }
    if (_type != null) {
      list = list.where((a) => a.type == _type).toList();
    }
    if (_days > 0) {
      final cutoff = DateTime.now().subtract(Duration(days: _days));
      list = list.where((a) => a.receivedAt.isAfter(cutoff)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _results;
    final hasFilter = _query.isNotEmpty || _severity != null || _type != null || _days > 0;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('搜索'),
          backgroundColor: scheme.surface,
          scrolledUnderElevation: 0,
          pinned: true,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: '搜索告警内容…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                // 筛选 chips
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // 严重度
                      for (final s in const [AlertSeverity.critical, AlertSeverity.info, AlertSeverity.ticket])
                        FilterChip(
                          label: Text(_severityLabel(s)),
                          selected: _severity == s,
                          onSelected: (on) => setState(() => _severity = on ? s : null),
                        ),
                      // 时间范围
                      for (final e in _dayOptions.entries)
                        FilterChip(
                          label: Text(e.value),
                          selected: _days == e.key,
                          onSelected: (on) => setState(() => _days = on ? e.key : 0),
                        ),
                    ],
                  ),
                ),
                if (hasFilter)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Text('找到 ${results.length} 条',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            _severity = null;
                            _type = null;
                            _days = 0;
                            _query = '';
                            _controller.clear();
                          }),
                          child: const Text('清除筛选'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!hasFilter)
          const SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('输入关键词搜索全部告警'),
                ],
              ),
            ),
          )
        else if (results.isEmpty)
          const SliverFillRemaining(
            child: Center(child: Text('没有匹配的告警')),
          )
        else
          SliverList.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final a = results[i];
              // 高亮命中段
              final body = a.body;
              return ListTile(
                leading: Icon(
                  a.severity == AlertSeverity.critical ? Icons.error : Icons.warning_amber_outlined,
                  color: a.severity == AlertSeverity.critical ? scheme.error : Colors.orange,
                ),
                title: Text(
                  body.length > 60 ? '${body.substring(0, 60)}…' : body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  '${a.type.label} · ${DateFormat('yyyy-MM-dd HH:mm').format(a.receivedAt)}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      AlertDetailPage(alert: a, aiTag: widget.provider.aiTags[a.id]),
                )),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  String _severityLabel(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.critical:
        return '主要五级';
      case AlertSeverity.info:
        return '次要六级';
      case AlertSeverity.ticket:
        return '工单';
      case AlertSeverity.unknown:
        return '其他';
    }
  }
}
