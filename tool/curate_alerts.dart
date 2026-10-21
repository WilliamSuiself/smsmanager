/// 建行告警 - AI 智能去重分析脚本
///
/// 输入：
///   baseline.json — 已存在的告警基线（app 首次启动时快照）
///   newest.json — 当前最新告警
///
/// 输出：
///   analysis.json — AI 对每条"新增"告警的判定
///
/// 判定规则（让 MiniMax-M3 做）：
///   - verdict: duplicate / new-anomaly / ticket / unknown
///   - action: OK / WATCH / URGENT
///   - summary: 一句话说明
///
/// 用法：
///   flutter pub run tool/curate_alerts.dart \
///     --baseline /path/to/baseline.json \
///     --newest /path/to/newest.json \
///     --output /path/to/analysis.json

library;

// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:smsmanager/services/object_key.dart';
import 'package:http/http.dart' as http;

const String _apiBase = 'https://api.minimaxi.com/v1';
const String _model = 'MiniMax-M3';

// ──────────────────────────────────────────────────────────────
// API key（用户硬编码授权；生产环境请放环境变量 / Secret）
// ──────────────────────────────────────────────────────────────
const String _apiKey =
    'sk-cp-vBDN9UUZB36_QDaBjHeVLL4Tccadwzw_onXFHRRXh9CPb_Ypm1IquzO9xoaBfcEWXX7tk-o0-HXIPcX_zsovV5VuH7vgVjxwre4tRu6f7teNyWZDHLLi4Zk';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);

  print('━━━ AI 告警去重分析 ━━━');
  print('  baseline: ${opts.baseline}');
  print('  newest:   ${opts.newest}');
  print('  output:   ${opts.output}');

  final baselineAlerts = await _loadIds(opts.baseline);
  final newestAlerts = await _loadAlerts(opts.newest);

  final newAlerts = newestAlerts
      .where((a) => !baselineAlerts.contains(a['id']))
      .toList();

  print('  基线告警: ${baselineAlerts.length} 条');
  print('  最新告警: ${newestAlerts.length} 条');
  print('  新增告警: ${newAlerts.length} 条');
  print('');

  if (newAlerts.isEmpty) {
    print('（无新增告警，跳过 AI 分析）');
    final empty = {
      'analyzedAt': DateTime.now().toIso8601String(),
      'newCount': 0,
      'tags': <String, dynamic>{},
    };
    await File(opts.output).writeAsString(jsonEncode(empty));
    return;
  }

  // 加载 baseline 详细告警，用于 prompt 中的"对照样本"
  final baselineFull = await _loadFull(opts.baseline);

  final tags = <String, dynamic>{};
  int urgent = 0;
  int watch = 0;
  int ok = 0;

  for (final alert in newAlerts) {
    print('━━━ 分析 #${alert['id']} ━━━');
    print('  body: ${(alert['body'] as String).substring(0, (alert['body'] as String).length < 80 ? (alert['body'] as String).length : 80)}');

    final verdict = await _askAi(alert, baselineFull);
    tags['${alert['id']}'] = verdict;
    print('  判定: verdict=${verdict['verdict']} action=${verdict['action']}');
    print('  摘要: ${verdict['summary']}');
    print('');

    switch (verdict['action']) {
      case 'URGENT':
        urgent++;
        break;
      case 'WATCH':
        watch++;
        break;
      default:
        ok++;
        break;
    }
  }

  // 写出 analysis.json
  final out = {
    'analyzedAt': DateTime.now().toIso8601String(),
    'baselineCount': baselineAlerts.length,
    'newestCount': newestAlerts.length,
    'newCount': newAlerts.length,
    'urgentCount': urgent,
    'watchCount': watch,
    'okCount': ok,
    'tags': tags,
  };
  await File(opts.output).writeAsString(jsonEncode(out));
  print('━━━ 汇总 ━━━');
  print('  URGENT: $urgent 条  /  WATCH: $watch 条  /  OK: $ok 条');
  print('  写入: ${opts.output}');
}

// ──────────────────────────────────────────────────────────────
// 工具方法
// ──────────────────────────────────────────────────────────────

class _Opts {
  final String baseline;
  final String newest;
  final String output;
  _Opts(this.baseline, this.newest, this.output);
}

_Opts _parseArgs(List<String> args) {
  String baseline = '/tmp/smsmanager.json';
  String newest = '/tmp/smsmanager.json';
  String output = '/tmp/ccb_analysis.json';
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--baseline' && i + 1 < args.length) baseline = args[++i];
    if (args[i] == '--newest' && i + 1 < args.length) newest = args[++i];
    if (args[i] == '--output' && i + 1 < args.length) output = args[++i];
  }
  return _Opts(baseline, newest, output);
}

Future<Set<int>> _loadIds(String path) async {
  if (!File(path).existsSync()) return {};
  final data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  return ((data['alerts'] as List?) ?? [])
      .map((a) => (a as Map<String, dynamic>)['id'] as int)
      .toSet();
}

Future<List<Map<String, dynamic>>> _loadAlerts(String path) async {
  if (!File(path).existsSync()) return [];
  final data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  return ((data['alerts'] as List?) ?? []).cast<Map<String, dynamic>>();
}

Future<List<Map<String, dynamic>>> _loadFull(String path) async {
  return _loadAlerts(path);
}

/// 调用 MiniMax chat completion 判断告警
Future<Map<String, dynamic>> _askAi(
  Map<String, dynamic> alert,
  List<Map<String, dynamic>> baseline,
) async {
  // 从 baseline 找同类对象的告警作为"对照样本"
  final objKey = alert['objectKey'] ?? extractAlertObjectKey(alert['body'] as String);
  final samples = baseline
      .where((b) => (b['objectKey'] ?? extractAlertObjectKey(b['body'] as String)) == objKey)
      .take(3)
      .toList();

  final prompt = '''
你是建行系统运维 / 业务告警智能判官。任务是判断**新告警**和**已有告警基线**的关系。

## 新告警（待判定）
类型: ${alert['type']}
严重度: ${alert['severity']}
对象: $objKey
正文: ${alert['body']}

## 同类对象的历史告警样本（最多 3 条）
${samples.isEmpty ? '（基线中无同类对象）' : samples.map((s) => '${s['receivedAt']} ${s['body']}').join('\n')}

## 判定规则
- duplicate: 与基线同类对象告警模式相同（同一对象 / 同一类型问题 / 重复出现）
- new-anomaly: 与基线同类对象告警模式不同 / 出现新对象 / 出现新异常模式
- ticket: 工单类通知（用户已被通知 / 委托 / 派发 等）
- unknown: 无法判断

## 输出 JSON（严格格式，不要其他说明）
{"verdict":"duplicate|new-anomaly|ticket|unknown","action":"OK|WATCH|URGENT","summary":"<一句话中文说明>"}
''';

  try {
    final httpResponse = await http.post(
      Uri.parse('$_apiBase/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.1,
      }),
    );

    if (httpResponse.statusCode != 200) {
      return {
        'verdict': 'unknown',
        'action': 'WATCH',
        'summary': 'AI 调用失败 (${httpResponse.statusCode})',
      };
    }

    final data = jsonDecode(httpResponse.body) as Map<String, dynamic>;
    final content = data['choices'][0]['message']['content'] as String;
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch == null) {
      return {
        'verdict': 'unknown',
        'action': 'WATCH',
        'summary': 'AI 返回非 JSON: ${content.substring(0, content.length < 60 ? content.length : 60)}',
      };
    }
    return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
  } catch (e) {
    return {
      'verdict': 'unknown',
      'action': 'WATCH',
      'summary': 'AI 调用异常: $e',
    };
  }
}

