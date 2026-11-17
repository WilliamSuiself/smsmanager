package com.suiyunhai.smsanalyzer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import android.telephony.SmsMessage

/**
 * 短信汇聚分析器 - 实时短信监听 Receiver
 *
 * 收到 SMS_RECEIVED 广播后的通知策略：
 *   - 发送方命中用户关注号码（SharedPreferences 持久化）→ 高优先级通知 + 关联结论
 *   - 内容命中「重要紧急」关键字（逾期 / 冻结 / 法院 / 盗刷 等，与 Dart 侧
 *     SmsClassifier._urgentKeywords 保持一致）→ 高优先级通知
 *   - 其他短信一律静默（只入库，可在 App 内查看）
 *
 * 命中 → 通过 NotificationManager 发系统通知
 *
 * 关键：
 *   - 即使 app 进程被杀掉（系统回收 / 用户划掉），receiver 仍可触发
 *   - receiver 拿到 wake_lock 短暂屏幕点亮 + 振动
 *   - 点击通知 → 启动 MainActivity
 */
class SmsReceiver : BroadcastReceiver() {
    companion object {
        private const val CHANNEL_ID = "ccb_alert_critical"
        private const val CHANNEL_NAME = "重点关注（严重）"
        private const val NOTIFICATION_ID = 1001
        private const val PREFS = "watchlist"
        private const val PREF_KEY = "senders"

        /** 关注号码持久化（SharedPreferences，Dart 侧同步推送） */
        fun saveWatchlist(context: Context, senders: List<String>) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putStringSet(PREF_KEY, senders.toSet()).apply()
        }

        private fun loadWatchlist(context: Context): Set<String> =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getStringSet(PREF_KEY, emptySet()) ?: emptySet()

        /** 号码规范化：去空格 / 横线 / 加号（与 Dart 侧一致） */
        fun normalizeSender(sender: String): String =
            sender.replace(Regex("[\\s\\-+]"), "")

        // 强告警关键字（任一命中即视为告警）
        private val ALERT_KEYWORDS = setOf(
            "告警", "警告", "报警", "异常", "监控", "阈值", "超标",
            "系统告警", "业务告警", "运维告警", "风险预警",
            "故障", "宕机", "中断", "超时", "失败率", "可用率",
            "工单", "任务", "已派发"
        )

        // 重要紧急关键字（与 Dart 侧 SmsClassifier._urgentKeywords 保持一致）
        // 命中 → 高优先级通知（非关注号码也弹）
        private val URGENT_KEYWORDS = setOf(
            "异常登录", "安全提醒", "风险提示", "盗刷", "涉嫌", "违法", "冻结", "紧急",
            "立即处理", "逾期", "欠费", "停机", "断网", "限电", "停水", "催收",
            "法院", "诉讼", "传票", "开庭", "失信", "仲裁", "强制执行"
        )

        // 营销 / 骚扰关键字（通知层过滤：账户变动入库但不通知，营销直接丢）
        private val MARKETING_KEYWORDS = setOf(
            "积分", "抽奖", "商城", "兑换", "优惠", "促销", "礼品",
            "理财", "基金", "投资", "收益", "赎回", "申购", "到期",
            "外汇", "外币", "买入价", "卖出价", "汇率",
            "SOFR", "ESTR", "SONIA", "全量档期", "档期利率",
            "登录提醒", "登录通知", "密码", "地址变更", "开户", "销户"
        )

        /** 发送方是否命中用户关注号码 */
        fun isWatchedSender(context: Context, sender: String): Boolean {
            val cleaned = normalizeSender(sender)
            val watchlist = loadWatchlist(context)
            return watchlist.any { cleaned.contains(it) || it.contains(cleaned) }
        }

        fun isWatchAlert(context: Context, sender: String, body: String): Boolean {
            // 1. 关注号码：全量收录（不限内容）
            if (isWatchedSender(context, sender)) return true

            // 2. 其他号码：仅告警类短信收录
            val hasMarketing = MARKETING_KEYWORDS.any { body.contains(it) }
            if (hasMarketing) return false
            val hasAlert = ALERT_KEYWORDS.any { body.contains(it) }
            return hasAlert
        }

        // ──────────────────────────────────────────────
        // 关联分析（与 Dart 侧 extractObjectKey 保持同一套规则）
        // ──────────────────────────────────────────────

        /**
         * 提取告警对象 key（与 Dart 侧 extractObjectKey 规则保持一致）：
         * 调度作业 → 作业流名称 → 主机名 → 工单号 → 委托人 → 单引号代号 → body前30字符
         */
        fun extractObjectKey(body: String): String {
            // 调度作业：调度域：XX ,'<作业名>'
            Regex("调度域[：:][^,，'\\n]{0,20}[,，]\\s*'([^'\\n]{4,80})'")
                .find(body)?.let { return it.groupValues[1] }
            // 作业流名称:xxx
            Regex("作业流名称[：:]\\s*([A-Za-z0-9_\\-]+)")
                .find(body)?.let { return it.groupValues[1] }
            // 主机名：冒号后紧跟小写主机代号
            Regex("[：:]\\s*([a-z]{1,2}\\d+\\w*(?:\\.\\w+)*)")
                .find(body)?.let { return it.groupValues[1] }
            // 独立引号作业代号（无调度域上下文）
            Regex("'((?:ODAP|ADWNG|NAIS|NEDP|job_)[A-Za-z0-9_\\-]+)'")
                .find(body)?.let { return it.groupValues[1] }
            // 工单号
            Regex("工单[_#：: ]?\\s*([A-Z]{1,3}\\d{5,})")
                .find(body)?.let { return it.groupValues[1] }
            // 工单委托 → 申请人
            Regex("([\\u4e00-\\u9fff]{2,4})申请将待办工单委托")
                .find(body)?.let { return "${it.groupValues[1]}的委托" }
            // 通用兜底：第一个单引号大写代号
            Regex("'([A-Z0-9][\\w.\\-]+)'").find(body)?.let { return it.groupValues[1] }
            return if (body.length <= 30) body else body.substring(0, 30)
        }

        data class Correlation(val objKey: String, val count7d: Int, val lastSeen: Long?)

        /**
         * 查短信库：近 7 天内同对象告警次数 + 上一次告警时间
         *
         * 只统计同样命中 isCcbAlert 的短信，与 App 列表口径一致。
         * READ_SMS 未授予时静默降级为「首次」。
         */
        fun correlate(context: Context, body: String): Correlation {
            val objKey = extractObjectKey(body)
            val now = System.currentTimeMillis()
            val since = now - 7L * 24 * 3600 * 1000
            var count = 0
            var lastSeen: Long? = null
            try {
                                context.contentResolver.query(                    Telephony.Sms.Inbox.CONTENT_URI,
                    arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
                    "${Telephony.Sms.DATE} >= ?",
                    arrayOf(since.toString()),
                    "${Telephony.Sms.DATE} DESC"
                )?.use { c ->
                    val iAddr = c.getColumnIndex(Telephony.Sms.ADDRESS)
                    val iBody = c.getColumnIndex(Telephony.Sms.BODY)
                    val iDate = c.getColumnIndex(Telephony.Sms.DATE)
                    while (c.moveToNext()) {
                        val addr = c.getString(iAddr) ?: continue
                        val b = c.getString(iBody) ?: continue
                        if (!isWatchAlert(context, addr, b)) continue
                        if (extractObjectKey(b) != objKey) continue
                        count++
                        val d = c.getLong(iDate)
                        // 早于本条 1 分钟以上才算「上一次」
                        if (d < now - 60_000 && (lastSeen == null || d > lastSeen!!)) {
                            lastSeen = d
                        }
                    }
                }
            } catch (_: SecurityException) {
                // 无 READ_SMS 权限 → 无法做关联，按首次处理
            }
            return Correlation(objKey, count, lastSeen)
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

        val appCtx = context.applicationContext

        // 通知策略：关注号码 → 关联通知；非关注号码仅「重要紧急」类 → 高优先级通知；其余静默
        val watched = isWatchedSender(appCtx, sender)
        val urgent = URGENT_KEYWORDS.any { body.contains(it) }
        if (!watched && !urgent) return

        // 关联查询走后台线程（contentResolver 查询不应占用主线程，且 onReceive 有 ~10s 时限）
        val pendingResult = goAsync()
        Thread {
            try {
                if (watched) {
                    val corr = correlate(appCtx, body)
                    postNotification(appCtx, sender, body, corr)
                } else {
                    postUrgentNotification(appCtx, sender, body)
                }
                wakeScreen(appCtx)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    /** 创建通知 channel（Android 8+），两个通知路径共用 */
    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "关注号码 / 重要紧急类短信通知"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 300, 200, 300)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    /** 点通知启动 app 并直达详情（携带正文，Dart 侧匹配/兜底展示） */
    private fun launchPendingIntent(context: Context, sender: String, body: String): PendingIntent? {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply {
                putExtra("alert_sender", sender)
                putExtra("alert_body", body)
                putExtra("alert_at", System.currentTimeMillis())
            }
        return launchIntent?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    /** 重要紧急短信通知（非关注号码）：无关联结论，标题直接给分类 */
    private fun postUrgentNotification(context: Context, sender: String, body: String) {
        ensureChannel(context)
        val pendingIntent = launchPendingIntent(context, sender, body)
        val preview = if (body.length > 80) body.substring(0, 80) + "..." else body

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("重要紧急 · $sender")
            .setContentText(preview)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setGroup("ccb_alert")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notifManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notifId = 11001 + (sender.hashCode() and 0x7fffffff) % 9001
        notifManager.notify(notifId, notification)
    }

    /** 构建并发出通知，标题/正文携带关联结论 */
    private fun postNotification(context: Context, sender: String, body: String, corr: Correlation) {
        ensureChannel(context)
        val pendingIntent = launchPendingIntent(context, sender, body)

        // 关联结论行：「对象 B1 · 近7天第 N 次 · 上次 MM-dd HH:mm」或「首次出现」
        val corrLine = if (corr.count7d > 1) {
            val last = corr.lastSeen?.let {
                java.text.SimpleDateFormat("MM-dd HH:mm", java.util.Locale.getDefault())
                    .format(java.util.Date(it))
            }
            "对象 ${corr.objKey} · 近7天第 ${corr.count7d} 次" +
                (last?.let { " · 上次 $it" } ?: "")
        } else {
            "对象 ${corr.objKey} · 首次出现"
        }
        val title = if (corr.count7d > 1) "重点关注 · 复发" else "重点关注 · 新增"
        val preview = if (body.length > 80) body.substring(0, 80) + "..." else body

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText("$corrLine\n$preview")
            .setStyle(NotificationCompat.BigTextStyle().bigText("$corrLine\n\n$body"))
            // 对象 key 做通知 ID：同对象复发更新同一条，不同对象各占一条（不互相覆盖、各自响铃）
            .setGroup("ccb_alert")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notifManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // 同对象复用同 ID（更新不重复响），不同对象不同 ID（互不覆盖、各自响铃）
        val notifId = 1001 + (corr.objKey.hashCode() and 0x7fffffff) % 9001
        notifManager.notify(notifId, notification)
    }

    private fun wakeScreen(context: Context) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wakeLock = pm.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "ccb_alert:receiver"
        )
        wakeLock.acquire(5 * 1000L)
    }
}