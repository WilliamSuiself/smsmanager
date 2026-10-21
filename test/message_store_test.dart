import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smsmanager/models/sms_message.dart';
import 'package:smsmanager/services/message_store.dart';

void main() {
  group('MessageStore', () {
    test('merge 按 id 去重，并推进 lastSyncMs 到最新时间', () {
      final store = MessageStore();
      final added = store.merge([
        SmsMessage(
          id: 1,
          sender: '10086',
          body: '消费￥10',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(1000),
          category: SmsCategory.finance,
        ),
        SmsMessage(
          id: 2,
          sender: '10010',
          body: '快递已到',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          category: SmsCategory.todo,
        ),
      ]);
      expect(added, 2);
      expect(store.size, 2);
      expect(store.lastSyncMs, 2000);

      final addedAgain = store.merge([
        SmsMessage(
          id: 1,
          sender: '10086',
          body: '消费￥10',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(1000),
          category: SmsCategory.finance,
        ),
      ]);
      expect(addedAgain, 0);
      expect(store.size, 2);
    });

    test('markRead 标记已读', () {
      final store = MessageStore();
      store.merge([
        SmsMessage(
          id: 1,
          sender: '10086',
          body: 'hi',
          receivedAt: DateTime.now(),
          category: SmsCategory.other,
        ),
      ]);
      store.markRead(1);
      expect(store.byId(1)!.read, isTrue);
    });

    test('saveTo / loadFrom 往返一致', () async {
      final dir = await Directory.systemTemp.createTemp('message_store_test');
      final file = File('${dir.path}/messages_store.json');
      addTearDown(() => dir.deleteSync(recursive: true));

      final store = MessageStore();
      store.merge([
        SmsMessage(
          id: 1,
          sender: '95533',
          body: '消费￥100',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          category: SmsCategory.finance,
          confidence: 1.0,
        ),
      ]);
      await store.saveTo(file);

      final reloaded = MessageStore();
      await reloaded.loadFrom(file);
      expect(reloaded.size, 1);
      expect(reloaded.lastSyncMs, 5000);
      expect(reloaded.byId(1)!.category, SmsCategory.finance);
      expect(reloaded.byId(1)!.body, '消费￥100');
    });
  });
}
