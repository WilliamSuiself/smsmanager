package com.suiyunhai.smsmanager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import android.telephony.SmsMessage

/**
 * 通用短信 - 实时监听 Receiver
 *
 * 收到 SMS_RECEIVED 广播后，用关键词规则做一次轻量分类（与 Dart 侧
 * lib/services/sms_classifier.dart 的规则保持同步），据此决定通知的
 * 优先级/文案：
 *   - 重要紧急：高优先级通知 + 震动 + 短暂亮屏
 *   - 账务 / 待办 / 其他：普通通知
 *   - 垃圾：不弹通知（静默过滤，用户打开 app 仍能在"垃圾"分类里看到）
 *
 * 注：黑名单号码的静默过滤在 app 内（Dart 侧）生效；原生侧这里只做
 * 内容关键词分类，不读取黑名单（黑名单存于 Flutter shared_preferences，
 * 跨端直接读取格式耦合度高，收益有限，故未在此实现）。
 *
 * 关键：
 *   - 即使 app 进程被杀掉（系统回收 / 用户划掉），receiver 仍可触发
 *   - 点击通知 → 启动 MainActivity 并带上短信内容，直达详情
 */
class SmsReceiver : BroadcastReceiver() {
    companion object {
        private const val CHANNEL_ID_URGENT = "smsmanager_urgent"
        private const val CHANNEL_NAME_URGENT = "重要紧急"
        private const val CHANNEL_ID_NORMAL = "smsmanager_normal"
        private const val CHANNEL_NAME_NORMAL = "普通通知"
        private const val NOTIFICATION_ID = 1001

        enum class Category { URGENT, FINANCE, TODO, SPAM, OTHER }

        // 以下关键词集合需与 lib/services/sms_classifier.dart 保持一致
        private val URGENT_KEYWORDS = setOf(
            "异常登录", "安全提醒", "风险提示", "盗刷", "涉嫌", "违法", "冻结", "紧急",
            "立即处理", "逾期", "欠费", "停机", "断网", "限电", "停水", "催收",
            "法院", "诉讼", "传票", "开庭", "失信", "仲裁", "强制执行"
        )
        private val FINANCE_KEYWORDS = setOf(
            "消费", "支出", "转账", "转入", "转出", "还款", "已还", "入账", "退款",
            "工资", "充值", "提现", "取现", "支付", "存入", "汇入", "到账", "扣款",
            "代扣", "余额", "账单", "还款日", "待还"
        )
        private val TODO_KEYWORDS = setOf(
            "取件", "快递", "包裹", "预约", "会议", "面试", "体检", "续费", "签收",
            "挂号", "请于", "截止", "领取", "核酸", "提醒您", "到期", "确认"
        )
        private val SPAM_KEYWORDS = setOf(
            "优惠", "特价", "秒杀", "中奖", "抽奖", "点击链接", "回复td退订", "退订回t",
            "免费领取", "限时", "抢购", "助力", "砍价", "贷款额度", "白条", "借呗",
            "网贷", "私彩", "博彩", "股票内幕", "加微信", "扫码领取", "尊享特权",
            "最高可借", "无抵押", "低息"
        )

        fun classify(body: String): Category {
            fun hits(keywords: Set<String>) = keywords.count { body.contains(it, ignoreCase = true) }

            val urgent = hits(URGENT_KEYWORDS)
            val finance = hits(FINANCE_KEYWORDS)
            val spam = hits(SPAM_KEYWORDS)
            val todo = hits(TODO_KEYWORDS)

            return when {
                urgent > 0 -> Category.URGENT
                finance > 0 -> Category.FINANCE
                spam > 0 -> Category.SPAM
                todo > 0 -> Category.TODO
                else -> Category.OTHER
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "android.provider.Telephony.SMS_RECEIVED") return

        val pdus = intent.extras?.get("pdus") as? Array<*> ?: return
        val format = intent.extras?.getString("format")

        val messages = pdus.mapNotNull { pdu ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                SmsMessage.createFromPdu(pdu as ByteArray, format)
            } else {
                @Suppress("DEPRECATION")
                SmsMessage.createFromPdu(pdu as ByteArray)
            }
        }
        if (messages.isEmpty()) return

        val sender = messages.first().displayOriginatingAddress
            ?: messages.first().originatingAddress
            ?: messages.first().serviceCenterAddress
            ?: return
        val body = messages.joinToString("") { it.displayMessageBody ?: "" }
        if (body.isBlank()) return

        val category = classify(body)
        if (category == Category.SPAM) return // 垃圾短信静默过滤，不弹通知

        postNotification(context.applicationContext, sender, body, category)
        if (category == Category.URGENT) wakeScreen(context.applicationContext)
    }

    private fun postNotification(context: Context, sender: String, body: String, category: Category) {
        val isUrgent = category == Category.URGENT
        val channelId = if (isUrgent) CHANNEL_ID_URGENT else CHANNEL_ID_NORMAL

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(channelId) == null) {
                val importance = if (isUrgent) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_DEFAULT
                val name = if (isUrgent) CHANNEL_NAME_URGENT else CHANNEL_NAME_NORMAL
                val channel = NotificationChannel(channelId, name, importance).apply {
                    if (isUrgent) {
                        enableVibration(true)
                        vibrationPattern = longArrayOf(0, 300, 200, 300)
                    }
                }
                nm.createNotificationChannel(channel)
            }
        }

        // 点通知启动 app 并直达该短信详情
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply {
                putExtra("alert_sender", sender)
                putExtra("alert_body", body)
                putExtra("alert_at", System.currentTimeMillis())
            }
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val title = when (category) {
            Category.URGENT -> "重要，请紧急处理"
            Category.FINANCE -> "已帮您完成记账"
            Category.TODO -> "已帮您加入待办事项"
            else -> "新短信"
        }
        val preview = if (body.length > 80) body.substring(0, 80) + "..." else body

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(preview)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$sender\n$body"))
            .setPriority(if (isUrgent) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notifManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notifManager.notify(NOTIFICATION_ID, notification)
    }

    private fun wakeScreen(context: Context) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wakeLock = pm.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "smsmanager:receiver"
        )
        wakeLock.acquire(5 * 1000L)
    }
}
