/// 短信权限申请服务
///
/// 封装 [permission_handler]：检测 / 申请 / 跳设置。
library;

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  PermissionService._();

  /// 检查当前 SMS 权限状态
  static Future<PermissionStatus> currentStatus() {
    return Permission.sms.status;
  }

  /// 申请 SMS 权限
  ///
  /// 返回最终状态：
  /// - [PermissionStatus.granted] 用户同意
  /// - [PermissionStatus.permanentlyDenied] 永久拒绝 → 应该引导用户去设置
  /// - [PermissionStatus.denied] / [PermissionStatus.restricted] 用户拒绝 / 系统限制
  static Future<PermissionStatus> requestSms() async {
    final status = await Permission.sms.request();
    // Android 13+ 需要同时申请 notifications 才能正常监听新短信；
    // 否则 SmsReceiver 发出的通知会被系统静默吞掉，用户完全看不到。
    await Permission.notification.request();
    if (status.isPermanentlyDenied) {
      // 引导用户去系统设置
      await openAppSettings();
    }
    return status;
  }
}