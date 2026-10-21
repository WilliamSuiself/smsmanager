/// 告警对象提取（纯函数，无 Flutter 依赖——tool 脚本也可复用）
///
/// 建行告警正文结构：`数据应用'<系统代号>'_<指标类型>:<对象>`，
/// 'B1'/'N-P9EIL' 这类是系统代号不是对象。按优先级提取：
///   1. 调度作业：`调度域：BDH ,'ODAP_...'` → 作业名（单条/聚合同构）
///   2. 作业流：`作业流名称:xxx`
///   3. 主机设备：冒号后紧跟 `[a-z]{1,2}\d+\w*` 主机名
///      （wn1apa2kvdb0002 / n110paae0hd3008.ksc.com / dj19eilmndb0001），
///      聚合告警概要 `...发生时间':wnXXX~` 同样命中
///   4. 工单号：`工单_SR26090200775` / `工单 #123`
///   5. 委托：`XX申请将待办工单委托` → 人名
///   6. 兜底：第一个单引号大写代号（'N-P9EIL' 系统级）→ body 前 30 字符
///
/// Kotlin 侧 SmsReceiver.extractObjectKey 与本函数规则保持一致，改动需同步。
library;

final _jobRe = RegExp(r"调度域[：:][^,，'\n]{0,20}[,，]\s*'([^'\n]{4,80})'");
final _jobFlowRe = RegExp(r"作业流名称[：:]\s*([A-Za-z0-9_\-]+)");
final _hostRe = RegExp(r"[：:]\s*([a-z]{1,2}\d+\w*(?:\.\w+)*)");
// 另一种作业格式：'D2''N-P9EIL:企业级信息应用计算子系统' 'ADWNG_...'作业运行时长超时
// —— 无调度域前缀，作业名独立成引号 token
final _jobCodeRe = RegExp(r"'((?:ODAP|ADWNG|NAIS|NEDP|job_)[A-Za-z0-9_\-]+)'");
final _ticketRe = RegExp(r"工单[_#：: ]?\s*([A-Z]{1,3}\d{5,})");
final _delegateRe = RegExp(r"([一-龥]{2,4})申请将待办工单委托");
final _quotedRe = RegExp(r"'([A-Z0-9][\w\.\-]+)'");

/// 从告警正文提取"对象" key
String extractAlertObjectKey(String body) {
  // 调度作业：调度域：XX ,'<作业名>'
  final jm = _jobRe.firstMatch(body);
  if (jm != null) return jm.group(1)!;

  // 作业流名称：xxx（NEDP / 流计算类告警）
  final sm = _jobFlowRe.firstMatch(body);
  if (sm != null) return sm.group(1)!;

  // 主机名：冒号后紧跟小写主机代号（时间里的冒号后是数字，不会误命中）
  final hm = _hostRe.firstMatch(body);
  if (hm != null) return hm.group(1)!;

  // 独立引号作业代号（无调度域上下文的变体格式）
  final jcm = _jobCodeRe.firstMatch(body);
  if (jcm != null) return jcm.group(1)!;

  // 工单号
  final tm = _ticketRe.firstMatch(body);
  if (tm != null) return tm.group(1)!;

  // 工单委托 → 申请人
  final dm = _delegateRe.firstMatch(body);
  if (dm != null) return '${dm.group(1)}的委托';

  // 通用兜底：第一个单引号大写代号（系统代号级分组）
  final qm = _quotedRe.firstMatch(body);
  if (qm != null) return qm.group(1)!;

  return body.substring(0, body.length < 30 ? body.length : 30);
}
