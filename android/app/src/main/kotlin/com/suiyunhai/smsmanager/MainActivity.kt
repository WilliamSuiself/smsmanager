package com.suiyunhai.smsmanager

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "smsmanager/sms"
    }

    private var methodChannel: MethodChannel? = null

    /** 冷启动时被通知带进来的告警（Dart 侧消费一次后清空） */
    private var launchAlert: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureLaunchAlert(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // App 活着时点通知 → 主动推给 Dart 侧导航到详情
        val data = extractAlert(intent)
        if (data != null) {
            methodChannel?.invokeMethod("onLaunchAlert", data)
        }
    }

    private fun captureLaunchAlert(intent: Intent?) {
        extractAlert(intent)?.let { launchAlert = it }
    }

    private fun extractAlert(intent: Intent?): Map<String, Any>? {
        val body = intent?.getStringExtra("alert_body") ?: return null
        return mapOf(
            "sender" to (intent.getStringExtra("alert_sender") ?: ""),
            "body" to body,
            "at" to intent.getLongExtra("alert_at", 0L),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                // 查收件箱：sinceMs 之后的短信（0/缺省 = 全量，无条数上限）
                "queryInbox" -> {
                    val sinceMs = call.argument<Number>("sinceMs")?.toLong() ?: 0L
                    queryInbox(sinceMs, result)
                }
                // 冷启动消费一次性的启动告警参数（点通知直达详情）
                "consumeLaunchAlert" -> {
                    result.success(launchAlert)
                    launchAlert = null
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 直接查 SMS provider，替代 flutter_sms_inbox（该库单次上限 1000 且分页有 bug，
     * 拿不到完整历史；运维告警需要做跨年度关联，必须全量 + 增量查询）。
     *
     * 返回：[{id, address, body, date}]，date 为 epoch 毫秒。
     */
    private fun queryInbox(sinceMs: Long, result: MethodChannel.Result) {
        Thread {
            try {
                val out = ArrayList<Map<String, Any>>()
                val selection = if (sinceMs > 0) "${Telephony.Sms.DATE} >= ?" else null
                val selArgs = if (sinceMs > 0) arrayOf(sinceMs.toString()) else null
                contentResolver.query(
                    Telephony.Sms.Inbox.CONTENT_URI,
                    arrayOf(
                        Telephony.Sms._ID,
                        Telephony.Sms.ADDRESS,
                        Telephony.Sms.BODY,
                        Telephony.Sms.DATE,
                    ),
                    selection,
                    selArgs,
                    "${Telephony.Sms.DATE} DESC"
                )?.use { c ->
                    val iId = c.getColumnIndexOrThrow(Telephony.Sms._ID)
                    val iAddr = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                    val iBody = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
                    val iDate = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
                    while (c.moveToNext()) {
                        out.add(
                            mapOf(
                                "id" to c.getLong(iId),
                                "address" to (c.getString(iAddr) ?: ""),
                                "body" to (c.getString(iBody) ?: ""),
                                "date" to c.getLong(iDate),
                            )
                        )
                    }
                }
                Handler(Looper.getMainLooper()).post { result.success(out) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.error("SMS_QUERY_FAILED", e.message, null)
                }
            }
        }.start()
    }
}
