// 短信管理 App 基础冒烟测试
//
// 不调 bootstrap() — 跳过 permission_handler 的 platform channel，
// gate 保持 PermissionGate.unknown，UI 显示 spinner。
// 真实流程需要在 Android 真机 + 已授权环境下跑通。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smsmanager/main.dart';
import 'package:smsmanager/state/message_list_provider.dart';

void main() {
  testWidgets('app boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<MessageListProvider>(
        create: (_) => MessageListProvider(),
        child: const SmsManagerApp(),
      ),
    );
    await tester.pump();

    // 顶栏标题
    expect(find.text('短信管理'), findsOneWidget);

    // PermissionGate.unknown 分支显示 spinner
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 底部导航 4 个 tab
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
