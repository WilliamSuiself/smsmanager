package com.suiyunhai.smsmanager

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
 * 建行告警 - 实时短信监听 Receiver
 *
 * 收到 SMS_RECEIVED 广播后过滤：
 *   - 发送方：95533 / 10695533 / 1069...95533 等建行号段
 *   - 内容：必须含告警关键字（告警 / 异常 / 监控 / 故障 / 工单 等）
 *   - 不能含支付 / 账户 / 营销 / 外汇 等非告警关键字
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
        private const val CHANNEL_ID = "smsmanager_critical"
        private const val CHANNEL_NAME = "建行告警（严重）"
        private const val NOTIFICATION_ID = 1001

        // 建行号段
        private val CCB_SENDERS = setOf("95533", "10695533", "12368")

        // 强告警关键字（任一命中即视为告警）
        // 与 lib/services/ccb_parser.dart 的 _alertKeywords 保持一致，
        // 避免 App 内列表能看到的告警，原生实时通知却识别不出来。
        private val ALERT_KEYWORDS = setOf(
            "告警", "警告", "报警", "异常", "监控", "阈值", "超标",
            "系统告警", "业务告警", "运维告警", "风险预警", "风险提示",
            "故障", "宕机", "中断", "超时", "失败率", "可用率",
            "不可用", "降级", "熔断", "连接异常",
            "CPU", "内存", "磁盘", "IO", "带宽", "流量",
            "接口", "主机", "服务", "数据库", "服务器", "网络",
            "部署", "上线", "回滚", "发版", "升级",
            "工单", "任务", "处理中", "已派发", "已分派",
            "延迟", "积压", "堆积"
        )

        // 非告警关键字（任一命中 → 视为个人支付 / 账户 / 营销 / 外汇，过滤）
        // 与 lib/services/ccb_parser.dart 的 _nonAlertKeywords 保持一致。
        private val NON_ALERT_KEYWORDS = setOf(
            "消费", "支出", "转账", "转入", "转出", "还款", "已还",
            "入账", "退款", "退货", "工资", "充值", "提现", "取现",
            "支付", "存入", "汇入", "到账", "缴费", "党费",
            "POS", "扫码", "被扫", "网联", "银联",
            "储蓄卡", "信用卡", "龙卡", "理财卡",
            "尾号", "账号末四位", "卡号末四位", "末四位",
            "登录提醒", "登录通知", "密码", "地址变更", "开户", "销户", "激活",
            "绑定", "解绑", "签约", "客户等级", "星级", "回访", "生日",
            "临时额度", "额度调整", "额度最高", "境外使用", "境外网站",
            "积分", "抽奖", "商城", "兑换", "优惠", "促销", "礼品",
            "优惠券", "活动券", "推荐", "邀您", "尊享",
            "理财", "基金", "投资", "收益", "赎回", "申购", "到期",
            "外汇", "外币", "买入价", "卖出价", "汇率", "钞汇", "现钞", "现汇",
            "外汇买卖", "汇兑", "结售汇", "结汇", "售汇", "汇率牌价",
            "SOFR", "ESTR", "SONIA", "TONAR", "EONIA",
            "全量档期", "档期利率", "利率数据重复", "自动发布",
            "生效的", "档期",
            "美元", "欧元", "英镑", "日元", "港币", "澳元", "加元", "瑞郎", "新加坡元"
        )

        fun isCcbAlert(sender: String, body: String): Boolean {
            // 1. 发送方判断
            val cleaned = sender.replace(Regex("[\\s\\-]"), "")
            val senderOk = CCB_SENDERS.any { cleaned.contains(it) } ||
                (cleaned.startsWith("1069") && cleaned.contains("95533"))
            if (!senderOk) return false

            // 2. 告警关键字命中
            val hasAlert = ALERT_KEYWORDS.any { body.contains(it) }
            if (!hasAlert) return false

            // 3. 不能含非告警关键字
            val hasNonAlert = NON_ALERT_KEYWORDS.any { body.contains(it) }
            return !hasNonAlert
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

        /** 同对象的一次历史出现（供"分别是什么时间"+ diff 用） */
        data class Occurrence(val at: Long, val body: String)

        data class Correlation(
            val objKey: String,
            val count7d: Int,
            val lastSeen: Long?,
            /** 同对象近期历史出现（不含本次），时间倒序，最多 [historyLimit] 条 */
            val history: List<Occurrence>,
            /** 前后 ±30 分钟内其他对象的告警条数（告警风暴信号） */
            val burstCount: Int,
        )

        private const val historyLimit = 3

        /**
         * 查短信库：近 7 天内同对象告警次数 / 历史出现时间+正文 / 同期（±30min）其他对象告警数
         *
         * 只统计同样命中 isCcbAlert 的短信，与 App 列表口径一致。
         * READ_SMS 未授予时静默降级为「首次」。
         */
        fun correlate(context: Context, body: String): Correlation {
            val objKey = extractObjectKey(body)
            val now = System.currentTimeMillis()
            val since = now - 7L * 24 * 3600 * 1000
            val burstWindowMs = 30L * 60 * 1000
            var count = 0
            var lastSeen: Long? = null
            val history = mutableListOf<Occurrence>()
            var burstCount = 0
            try {
                context.contentResolver.query(
                    Telephony.Sms.Inbox.CONTENT_URI,
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
                        if (!isCcbAlert(addr, b)) continue
                        val d = c.getLong(iDate)
                        val sameObj = extractObjectKey(b) == objKey
                        // 早于本条 1 分钟以上才算「历史」，避免把本条自己算进去
                        val isHistorical = d < now - 60_000
                        if (sameObj) {
                            count++
                            if (isHistorical) {
                                if (lastSeen == null || d > lastSeen!!) lastSeen = d
                                if (history.size < historyLimit) history.add(Occurrence(d, b))
                            }
                        } else if (isHistorical && Math.abs(d - now) <= burstWindowMs) {
                            burstCount++
                        }
                    }
                }
            } catch (_: SecurityException) {
                // 无 READ_SMS 权限 → 无法做关联，按首次处理
            }
            return Correlation(objKey, count, lastSeen, history, burstCount)
        }

        /**
         * 简单文本 diff：取公共前缀 + 公共后缀，中间不同的部分即为本次与上次的差异。
         * 适合建行告警这种"模板固定、中间变量（作业名/数值/时间戳）变化"的场景。
         */
        fun diffSummary(previous: String, current: String): String {
            if (previous == current) return "内容与上次完全一致"
            val minLen = minOf(previous.length, current.length)
            var prefix = 0
            while (prefix < minLen && previous[prefix] == current[prefix]) prefix++
            var suffix = 0
            while (suffix < minLen - prefix &&
                previous[previous.length - 1 - suffix] == current[current.length - 1 - suffix]
            ) suffix++
            val prevMid = previous.substring(prefix, previous.length - suffix).trim()
            val currMid = current.substring(prefix, current.length - suffix).trim()
            if (prevMid.isEmpty() && currMid.isEmpty()) return "内容与上次完全一致"
            fun clip(s: String) = if (s.length > 36) s.take(36) + "…" else s
            val prevShown = if (prevMid.isEmpty()) "(无)" else clip(prevMid)
            val currShown = if (currMid.isEmpty()) "(无)" else clip(currMid)
            return "上次「$prevShown」→ 本次「$currShown」"
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

        if (!isCcbAlert(sender, body)) return

        // 关联查询走后台线程（contentResolver 查询不应占用主线程，且 onReceive 有 ~10s 时限）
        val appCtx = context.applicationContext
        val pendingResult = goAsync()
        Thread {
            try {
                val corr = correlate(appCtx, body)
                postNotification(appCtx, sender, body, corr)
                wakeScreen(appCtx)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    /** 构建并发出通知，标题/正文携带关联结论 */
    private fun postNotification(context: Context, sender: String, body: String, corr: Correlation) {
        // 创建通知 channel（Android 8+）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "建行系统告警 / 业务告警通知"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 300, 200, 300)
                }
                nm.createNotificationChannel(channel)
            }
        }

        // 点通知启动 app 并直达该告警详情（携带正文，Dart 侧匹配/兜底展示）
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

        val timeFmt = java.text.SimpleDateFormat("MM-dd HH:mm", java.util.Locale.getDefault())

        // 关联结论行：「对象 B1 · 近7天第 N 次」或「首次出现」
        val corrLine = if (corr.count7d > 1) {
            "对象 ${corr.objKey} · 近7天第 ${corr.count7d} 次"
        } else {
            "对象 ${corr.objKey} · 首次出现"
        }

        // 历史出现时间（"分别是什么时间"）
        val historyLine = if (corr.history.isNotEmpty()) {
            "历史: " + corr.history.joinToString(" / ") { timeFmt.format(java.util.Date(it.at)) }
        } else null

        // 与上一次相比的差异（"和本次有什么差别"）
        val diffLine = corr.history.firstOrNull()?.let {
            "差异: " + diffSummary(it.body, body)
        }

        // 同期爆发提示（阈值与 Dart 侧 CorrelationService.stormCount 保持一致）
        val burstLine = if (corr.burstCount >= 2) {
            "⚠ 前后 30 分钟内还有 ${corr.burstCount} 条其他告警" +
                (if (corr.burstCount >= 3) "，疑似告警风暴/连锁故障" else "")
        } else null

        val title = when {
            corr.burstCount >= 3 -> "建行告警 · 疑似告警风暴"
            corr.count7d > 1 -> "建行告警 · 复发"
            else -> "建行告警 · 新增"
        }

        val detailLines = listOfNotNull(corrLine, historyLine, diffLine, burstLine)
        val preview = if (body.length > 80) body.substring(0, 80) + "..." else body
        val summary = detailLines.joinToString("\n")

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText("$corrLine\n$preview")
            .setStyle(NotificationCompat.BigTextStyle().bigText("$summary\n\n$body"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
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