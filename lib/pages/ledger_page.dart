/// 账本页：展示自动记账生成的收支流水 + 本月汇总
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ledger_entry.dart';
import '../state/message_list_provider.dart';

class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessageListProvider>();
    final scheme = Theme.of(context).colorScheme;
    final totals = provider.monthlyTotals;
    final entries = provider.ledgerEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('账本'),
        backgroundColor: scheme.surface,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _TotalCard(
                    label: '本月收入',
                    amount: totals.income,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TotalCard(
                    label: '本月支出',
                    amount: totals.expense,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      '还没有自动记账的流水\n收到账务类短信后会自动显示在这里',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _LedgerTile(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  const _TotalCard({required this.label, required this.amount, required this.color});

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
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '¥${amount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  final LedgerEntry entry;
  const _LedgerTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = entry.direction == TxDirection.expense;
    final sign = entry.direction == TxDirection.income
        ? '+'
        : entry.direction == TxDirection.expense
            ? '-'
            : '';
    final color = entry.direction == TxDirection.income
        ? Colors.green.shade700
        : entry.direction == TxDirection.expense
            ? Colors.red.shade700
            : scheme.onSurfaceVariant;

    return ListTile(
      leading: Icon(
        isExpense ? Icons.arrow_upward : Icons.arrow_downward,
        color: color,
      ),
      title: Text(entry.counterparty ?? '未识别对方信息'),
      subtitle: Text(
        DateFormat('MM-dd HH:mm').format(entry.at) +
            (entry.cardLast4 != null ? ' · 尾号${entry.cardLast4}' : ''),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        entry.amount != null ? '$sign¥${entry.amount!.toStringAsFixed(2)}' : '金额未识别',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
