/// 建行告警 - 系统问题诊断脚本
///
/// 输入 alerts.json（app export），输出：
/// 1. 严重度分布（主要五级 / 次要六级 / 工单）
/// 2. 告警对象聚类（TiKV / 作业未开始 / 作业执行超时 等）
/// 3. 调度域聚类（BDH / NH / DDH / D2）
/// 4. 高频重复告警（同一对象 1 周内触发 ≥5 次）
/// 5. 时间分布（按小时段 / 按工作日 vs 周末）
///
/// 用法：
///   flutter pub run tool/system_analysis.dart /path/to/alerts.json
library;

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('用法：flutter pub run tool/system_analysis.dart <alerts.json>');
    exit(1);
  }

  final input = await File(args[0]).readAsString();
  final data = jsonDecode(input) as Map<String, dynamic>;
  final alerts = (data['alerts'] as List).cast<Map<String, dynamic>>();

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('  建行告警 - 系统问题诊断');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');

  _printSeverityDistribution(alerts);
  print('');
  _printAlertObjectClustering(alerts);
  print('');
  _printScheduleDomainClustering(alerts);
  print('');
  _printHighFrequencyRepeats(alerts);
  print('');
  _printTimeDistribution(alerts);
  print('');
  _printWeeklyTrend(alerts);
}

void _printSeverityDistribution(List<Map<String, dynamic>> alerts) {
  print('1. 严重度分布');
  final bySev = <String, int>{};
  for (final a in alerts) {
    final body = a['body'] as String;
    String sev;
    if (body.contains('主要') || body.contains('五级')) {
      sev = '主要五级';
    } else if (body.contains('次要') || body.contains('六级')) {
      sev = '次要六级';
    } else if (body.contains('工单') || body.contains('委托')) {
      sev = '工单';
    } else {
      sev = '其他';
    }
    bySev[sev] = (bySev[sev] ?? 0) + 1;
  }
  final total = alerts.length;
  for (final entry in bySev.entries) {
    final pct = (entry.value / total * 100).toStringAsFixed(1);
    print('  ${entry.key.padRight(10)} ${entry.value.toString().padLeft(4)} 笔   ${pct.padLeft(5)}%');
  }
}

void _printAlertObjectClustering(List<Map<String, dynamic>> alerts) {
  print('2. 告警对象聚类（从告警正文识别异常对象）');
  // 提取告警对象关键词
  final patterns = <RegExp, String>{
    RegExp(r'作业未开始执行'): '作业未开始执行',
    RegExp(r'作业未执行结束'): '作业未执行结束',
    RegExp(r'作业执行超时'): '作业执行超时',
    RegExp(r'作业实例执行失败'): '作业实例执行失败',
    RegExp(r'TiKV.{0,8}存储可用空间'): 'TiKV 存储可用空间',
    RegExp(r'TiKV.{0,8}空间使用率'): 'TiKV 空间使用率',
    RegExp(r'磁盘使用率'): '磁盘使用率',
    RegExp(r'Drainer.{0,8}同步延时'): 'Drainer 同步延时',
    RegExp(r'ping状态'): 'ping 状态',
  };

  final counts = <String, int>{};
  for (final a in alerts) {
    final body = a['body'] as String;
    for (final entry in patterns.entries) {
      if (entry.key.hasMatch(body)) {
        counts[entry.value] = (counts[entry.value] ?? 0) + 1;
        break;
      }
    }
  }

  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted.take(10)) {
    final pct = (entry.value / alerts.length * 100).toStringAsFixed(1);
    print('  ${entry.key.padRight(28)} ${entry.value.toString().padLeft(4)} 笔   ${pct.padLeft(5)}%');
  }
}

void _printScheduleDomainClustering(List<Map<String, dynamic>> alerts) {
  print('3. 调度域聚类（BDH/NH/DDH/D2/...）');
  final counts = <String, int>{};
  final domainRe = RegExp(r"调度域[：:][^,，'\n]+[,，']");
  for (final a in alerts) {
    final body = a['body'] as String;
    final m = domainRe.firstMatch(body);
    if (m != null) {
      // 提取调度域代号
      final match = RegExp(r'[A-Z]+\d?').firstMatch(m.group(0)!);
      if (match != null) {
        final code = match.group(0)!;
        counts[code] = (counts[code] ?? 0) + 1;
      }
    }
  }
  if (counts.isEmpty) {
    print('  (无调度域关键字)');
    return;
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted.take(8)) {
    final pct = (entry.value / alerts.length * 100).toStringAsFixed(1);
    print('  ${entry.key.padRight(8)} ${entry.value.toString().padLeft(4)} 笔   ${pct.padLeft(5)}%');
  }
}

void _printHighFrequencyRepeats(List<Map<String, dynamic>> alerts) {
  print('4. 高频重复告警对象（同一对象触发 ≥10 次）');
  // 提取主机名 / 作业代号
  final objectRe = RegExp(r'(wn\w+|NAIS_\w+|ADWNG_\w+|ODAP_\w+)');
  final counts = <String, int>{};
  for (final a in alerts) {
    final body = a['body'] as String;
    for (final m in objectRe.allMatches(body)) {
      counts[m.group(0)!] = (counts[m.group(0)!] ?? 0) + 1;
    }
  }

  final frequent = counts.entries.where((e) => e.value >= 10).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (frequent.isEmpty) {
    print('  (无)');
    return;
  }
  for (final entry in frequent.take(8)) {
    print('  ${entry.key.padRight(40)} ${entry.value.toString().padLeft(4)} 次');
  }
}

void _printTimeDistribution(List<Map<String, dynamic>> alerts) {
  print('5. 时间分布（按小时段）');
  final hourCounts = List<int>.filled(24, 0);
  int weekday = 0;
  int weekend = 0;
  for (final a in alerts) {
    final dt = DateTime.parse(a['receivedAt'] as String).toLocal();
    hourCounts[dt.hour]++;
    if (dt.weekday >= 1 && dt.weekday <= 5) {
      weekday++;
    } else {
      weekend++;
    }
  }
  final peak = hourCounts.indexOf(hourCounts.reduce((a, b) => a > b ? a : b));
  print('  峰值时段: ${peak.toString().padLeft(2)}:00 - ${(peak + 1).toString().padLeft(2)}:00   '
                '${hourCounts[peak]} 笔');
  print('  工作日 / 周末: $weekday / $weekend');

  // 按 6 小时桶
  print('  时段分布（每 6 小时桶）：');
  for (int i = 0; i < 4; i++) {
    final start = i * 6;
    final end = start + 6;
    final sum = hourCounts.sublist(start, end).fold<int>(0, (s, e) => s + e);
    final bar = '█' * (sum ~/ 10).clamp(0, 40);
    print('    ${start.toString().padLeft(2)}:00-${end.toString().padLeft(2)}:00  ${sum.toString().padLeft(4)} 笔   $bar');
  }
}

void _printWeeklyTrend(List<Map<String, dynamic>> alerts) {
  print('6. 周对比（本周 vs 上周）');
  if (alerts.isEmpty) {
    print('  (无数据)');
    return;
  }
  final now = DateTime.now();
  // 本周从 7 天前开始；上周从 14 天前到 7 天前
  final thisWeekStart = now.subtract(const Duration(days: 7));
  final lastWeekStart = now.subtract(const Duration(days: 14));

  int thisWeek = 0, lastWeek = 0;
  int thisWeekCritical = 0, lastWeekCritical = 0;
  for (final a in alerts) {
    final dt = DateTime.parse(a['receivedAt'] as String).toLocal();
    if (dt.isAfter(thisWeekStart)) {
      thisWeek++;
      if (a['severity'] == 'critical') thisWeekCritical++;
    } else if (dt.isAfter(lastWeekStart)) {
      lastWeek++;
      if (a['severity'] == 'critical') lastWeekCritical++;
    }
  }

  final trend = lastWeek == 0
      ? 'N/A (上周 0)'
      : (thisWeek > lastWeek ? '恶化' : thisWeek < lastWeek ? '好转' : '持平');
  final pct = lastWeek == 0 ? 'N/A' : '${((thisWeek - lastWeek) / lastWeek * 100).toStringAsFixed(1)}%';

  print('  本周（过去 7 天）：$thisWeek 笔  其中主要五级 $thisWeekCritical 笔');
  print('  上周（前 7-14 天）：$lastWeek 笔  其中主要五级 $lastWeekCritical 笔');
  print('  趋势：$trend ($pct)');
  print('');
  print('  → 详情看每周复盘文件。');
}