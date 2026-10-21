# 短信管理 (SmsManager)

手机里建设银行的告警短信越来越多，需要一个本地 App 帮自己统一管理。

> 数据完全本地化，不联网，不上传任何短信内容。

## 平台支持（先看清）

| 平台 | 读取短信 | 监听新短信 | 状态 |
| --- | --- | --- | --- |
| Android | 支持 | 支持 | 主要开发目标 |
| iOS | **不支持** | **不支持** | 仅作占位 UI |

**iOS 限制原因**：苹果系统不允许第三方 App 读取用户 SMS（隐私策略），整个 App Store 都没有真正能用的方案。能做的只有：让用户从短信 App 手动分享 / 用 Shortcuts 半自动——这条路体验非常差，本项目**只在 Android 上做真实功能**。iOS 上先跑壳子让你确认 UI。

## 已实现 (v0.1)

- [x] Flutter 脚手架 + Material 3 主题（建行蓝 `#005BAC`）
- [x] 主页骨架：告警 / 分类 / 搜索 / 设置 4 Tab
- [x] 告警列表空状态 + 授权按钮占位
- [x] 依赖：`permission_handler` / `provider` / `shared_preferences` / `intl` / `flutter_slidable`（短信读取走自建 MethodChannel，flutter_sms_inbox 有 1000 条上限已弃用）
- [x] 读短信 + 告警过滤（关键词双词表，只看运维/业务告警）
- [x] 折叠分组（按告警对象）+ 平铺列表 + 对象静音 24h
- [x] SmsReceiver 实时监听 → 高优先级通知（含关联结论）
- [x] 本地向量库（vectors.json）+ 关联分析：同对象复发 / 同期爆发 / 同类型 / 语义相似
- [x] 详情页关联分析卡片 + 工单草稿一键复制

## 路线图（按推荐顺序）

### v0.2 - 真的能读短信
- [ ] `permission_handler` 申请 `Permission.sms`（Android 13+ 运行时权限）
- [ ] 拉取历史短信，过滤 `95533` / `1069...95533` / `12368` 等建行号码段
- [ ] 解析常见模板：消费 / 转账 / 充值 / 贷款 / 信用卡还款 / 工资入账
- [ ] 列表展示：金额、类型、卡号后四位、时间

### v0.3 - 分类 + 搜索
- [ ] 按金额类型自动归类（消费、转账、还款、工资、理财...）
- [ ] 月度汇总（本月花了多少 / 收入多少）
- [ ] 全文搜索 + 金额区间筛选

### v0.4 - 管理动作
- [ ] 滑动操作：标记已读 / 归档 / 删除
- [ ] 忽略规则（按关键字、按金额阈值）
- [ ] 重要告警置顶（工资到账 / 大额转出）

### v0.5 - 通知 + 桌面小部件
- [ ] 实时监听新短信 → 应用内通知
- [ ] Android Widget 显示今日汇总

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

## 接下来要做哪一步？

推荐下一步：**v0.2 - 接 telephony 权限 + 拉取历史短信**。

告诉我"继续"或者你想先调 UI 风格，我直接推进。