# 短信管理 (SmsManager)

手机短信越来越多、越来越杂，需要一个本地 App 帮自己自动分类 + 处理。

> 数据完全本地化，不联网，不上传任何短信内容。所有分类 / 记账 / 待办都是纯本地规则 + 向量相似度计算，不调用任何云端 AI 接口。

## 平台支持（先看清）

| 平台 | 读取短信 | 监听新短信 | 状态 |
| --- | --- | --- | --- |
| Android | 支持 | 支持 | 主要开发目标 |
| iOS | **不支持** | **不支持** | 仅作占位 UI |

**iOS 限制原因**：苹果系统不允许第三方 App 读取用户 SMS（隐私策略），整个 App Store 都没有真正能用的方案。本项目**只在 Android 上做真实功能**。iOS 上先跑壳子让你确认 UI。

## 核心能力

收到一条短信，App 自动判断属于哪一类，并给出处理建议：

| 分类 | 建议文案 | 自动动作 |
| --- | --- | --- |
| 账务类 | 已帮您完成记账 | 解析金额 / 收支方向 / 对方户名，写入账本 |
| 重要紧急 | 重要，请紧急处理 | 高优先级通知 + 震动提醒 |
| 待办类 | 已帮您加入待办事项 | 自动生成一条待办，可在"待办"页勾选完成 |
| 垃圾/营销 | 垃圾短信，建议忽略 | 不弹通知；详情页可一键将号码加入黑名单 |

分类引擎（[`lib/services/sms_classifier.dart`](lib/services/sms_classifier.dart)）：
1. 发件人命中黑名单 → 直接判定垃圾
2. 关键词规则匹配（urgent > finance > spam > todo 优先级）
3. 规则没命中 → 退化为本地向量相似度兜底（[`EmbeddingService`](lib/services/embedding_service.dart)，字符 n-gram 哈希，不联网）

账务类短信额外交给 [`FinanceParser`](lib/services/finance_parser.dart) 解析金额 / 收支方向 / 商户 / 卡号后四位，自动写入「账本」页的流水和月度收支汇总。

## 已实现 (v0.2)

- [x] Flutter 脚手架 + Material 3 主题
- [x] 4 Tab：消息 / 账本 / 待办 / 设置
- [x] 短信读取走自建 MethodChannel（`android/.../MainActivity.kt` queryInbox，支持 sinceMs 增量、无条数上限）
- [x] 本地规则 + 向量兜底的通用短信分类（账务 / 重要紧急 / 待办 / 垃圾 / 其他）
- [x] 账务短信自动记账（金额 / 收支方向 / 商户 / 卡号后四位解析）+ 月度收支汇总
- [x] 待办类短信自动生成待办事项，可勾选完成
- [x] 黑名单：详情页一键拉黑号码，命中黑名单直接归类垃圾
- [x] SmsReceiver 实时监听 → 按分类决定通知优先级（重要紧急高优先级+震动，垃圾静默不弹）

## 路线图

### v0.3 - 记账增强
- [ ] 按月 / 按分类统计图表
- [ ] 手动编辑/修正识别不准的金额、对方信息

### v0.4 - 待办增强
- [ ] 从短信正文解析截止日期，到期提醒
- [ ] 待办事项手动添加/编辑

### v0.5 - 分类准确率
- [ ] 支持用户手动纠正分类结果，反馈进向量示例库
- [ ] 更多银行 / 支付平台短信模板适配

## Android 配置要点

第一次跑需要：
1. 在 `android/app/src/main/AndroidManifest.xml` 加权限：
   ```xml
   <uses-permission android:name="android.permission.READ_SMS"/>
   <uses-permission android:name="android.permission.RECEIVE_SMS"/>
   ```
2. Android 13+ 还要动态请求 `READ_SMS` 运行时权限
3. 第一次启动会跳系统弹窗，问"是否允许 短信管理 读取短信"

## 运行

```bash
cd /Users/suiyunhai/coding/smsmanager
flutter pub get
flutter run              # 连真机调试
flutter run -d <设备id>   # 指定设备
```

## 测试

```bash
flutter analyze
flutter test
```
