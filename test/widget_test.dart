// 短信汇聚分析器 App 基础冒烟测试
//
// 不调 bootstrap() — 跳过 permission_handler 的 platform channel，
// gate 保持 PermissionGate.unknown，UI 显示 spinner。
// 真实流程需要在 Android 真机 + 已授权环境下跑通。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smsanalyzer/main.dart';
import 'package:smsanalyzer/state/app_provider.dart';

void main() {
  testWidgets('app boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>(
        create: (_) => AppProvider(),
        child: const CcbAlertApp(),
      ),
    );
    await tester.pump();

    // 消息页顶栏标题
    expect(find.text('消息'), findsWidgets);

    // PermissionGate.unknown 分支显示 spinner
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 底部导航 4 个 tab
    expect(find.text('关注'), findsOneWidget);
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
  });
}
