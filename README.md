# 短信汇聚分析器

一个**隐私优先**的 Android 短信管理与汇聚分析工具。收件箱全量短信在本地自动分类（账务 / 重要紧急 / 待办 / 垃圾 / 其他），账务类自动记账、待办类自动生成待办；用户把自己关心的号码（银行、运维平台、物流、家人……）注册为关注号码后，其短信全量汇聚进「关注」页，并对告警类短信自动做关联分析。

> 数据 100% 本地化，App 完全不联网，不上传任何短信内容。

## 平台支持

| 平台 | 读取短信 | 监听新短信 | 状态 |
| --- | --- | --- | --- |
| Android | 支持 | 支持 | 主要开发目标 |
| iOS | 不支持 | 不支持 | 仅占位（系统限制，第三方 App 无法读取 SMS） |

## 功能

- **全量短信分类**：每条短信本地分类为账务 / 重要紧急 / 待办 / 垃圾 / 其他（关键词规则为主 + 本地向量相似度兜底），支持左滑已读 / 拉黑
- **自动记账**：账务类短信解析金额 / 收支方向 / 对方户名 / 卡号后四位 → 账本页流水 + 本月收支汇总
- **自动待办**：快递 / 预约 / 续费等待办类短信自动生成待办，可勾选完成
- **号码黑名单**：详情页一键拉黑；命中黑名单的号码直接判垃圾，历史短信同步重打标签
- **关注号码**：「关注」页直接注册号码；关注号码的短信全量收录并实时弹高优先级通知
- **通用告警汇聚**：非关注号码的短信按告警关键词（双词表：强告警命中 + 排除词过滤）自动筛选进「关注」库
- **折叠/平铺双模式**：按告警对象（作业名 / 主机名 / 工单号 / 委托人，纯函数规则提取）智能分组，支持对象静音 24h
- **关联分析**：同对象复发（近 24h / 7d 频次 + 上次时间）、同期爆发（±30min 窗口）、同类型模式、**语义相似**（本地离线向量：字符 n-gram + FNV-1a hashing trick，512 维，无云端依赖）
- **分类 / 搜索**：关注页右上角进入——按告警类型分类视图 + 全文实时搜索（严重度 / 时间范围筛选）
- **启动弹窗**：展示上次打开到本次打开之间的新增告警，点条目直达详情
- **实时通知**：原生 `BroadcastReceiver` 监听 SMS_RECEIVED，进程被杀仍生效；**关注号码**与**重要紧急**类短信弹高优先级通知（关注号码通知带关联结论：复发 / 首次出现），其余静默入库
- **持久化**：消息库 / 告警库 / 账本 / 待办全部 JSON 留底（跨年度），不受系统短信库滚动淘汰影响

## 技术架构

```
UI（Flutter, Material 3）
  ├─ 消息 / 关注 / 账本 / 待办 4 Tab（IndexedStack 状态保持）
  ├─ 消息卡片（分类标签 + 处理建议 + 左滑已读/拉黑）+ 详情页
  └─ 关注页：关注号码注册栏 + 告警分组列表 + 详情页关联分析卡片
状态层  AppProvider（ChangeNotifier，两条管道一次拉取）
服务层
  ├─ SmsService        MethodChannel 增量拉取短信（自建，无条数上限）
  ├─ SmsClassifier     全量分类（关键词规则 + 向量兜底；黑名单短路）
  ├─ FinanceParser     账务解析（金额 / 收支 / 商户 / 卡号后四位）
  ├─ CcbParser         告警识别 + 类型/严重度解析（双词表）
  ├─ MessageStore      全量消息库（messages_store.json）
  ├─ AlertStore        告警持久化库（alerts_store.json，lastSyncMs 增量游标）
  ├─ LedgerStore       账本（ledger_store.json）/ TodoStore 待办（todo_store.json）
  ├─ BlacklistStore    号码黑名单（SharedPreferences）
  ├─ VectorStore       本地向量库（vectors.json）
  ├─ EmbeddingService  离线嵌入（1~3-gram + FNV-1a → 512 维 L2 归一化）
  ├─ CorrelationService 关联分析（规则 + 向量）
  └─ WatchlistService  用户关注号码（SharedPreferences + 原生同步）
原生层（Kotlin）
  ├─ MainActivity      queryInbox(sinceMs) 直查 SMS provider；通知直达详情
  └─ SmsReceiver       SMS_RECEIVED 广播 → 关注号码/重要紧急 → 高优先级通知（含关联结论）
```

## 构建与运行

```bash
flutter pub get
flutter run              # 连真机调试（需 Android 设备，iOS 不支持读取短信）
flutter build apk        # 构建发布包
flutter test             # 运行单元测试
```

### 首次启动

1. 授予「短信」与「通知」权限（Android 13+ 为独立运行时权限）
2. 「关注」页顶部 → 添加你想重点关注的号码
3. 建议在系统设置中允许自启动 + 后台不受限（国产 ROM 会冻结后台 receiver）

## tool/ 辅助脚本

- `analyze.dart`：读 alerts.json 输出历史分析报告
- `system_analysis.dart`：严重度分布 / 对象聚类 / 高频重复 / 时间分布诊断
- `curate_alerts.dart`：AI 智能去重（调用 LLM API）
- `group_preview.dart`：对象提取规则验证

## 隐私

- 全部数据存储在应用私有目录，App 无任何网络权限请求
- 短信内容不上传、不记录日志；被过滤的短信不落盘
