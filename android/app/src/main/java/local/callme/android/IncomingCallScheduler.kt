package local.callme.android

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

object IncomingCallScheduler {
    private const val REQUEST_CODE = 1001

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    }

    fun schedule(context: Context, config: CallConfiguration): Result<Long> =
        scheduleAt(context, config, System.currentTimeMillis() + config.delayMillis)

    fun scheduleAt(
        context: Context,
        config: CallConfiguration,
        triggerAt: Long
    ): Result<Long> = runCatching {
        check(canScheduleExact(context)) { "尚未允许精确闹钟权限" }
        check(triggerAt > System.currentTimeMillis()) { "计划时间已经过去" }

        val alarmIntent = Intent(context, IncomingCallAlarmReceiver::class.java).apply {
            putExtra(CallIntentExtras.MODE, config.mode.name)
            putExtra(CallIntentExtras.CALLER_NAME, config.callerName)
            putExtra(CallIntentExtras.CALLER_NUMBER, config.callerNumber)
            putExtra(CallIntentExtras.AVATAR_URI, config.avatarUri)
            putExtra(CallIntentExtras.RINGTONE_URI, config.ringtoneUri)
            putExtra(CallIntentExtras.ANSWER_AUDIO_URI, config.answerAudioUri)
            putExtra(CallIntentExtras.PLANNED_TRIGGER_AT, triggerAt)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        // Alarm-clock alarms receive the strongest wake-up treatment available to ordinary apps.
        // This reduces the 10–30 second delivery drift seen on aggressive vendor power managers.
        alarmManager.setAlarmClock(
            AlarmManager.AlarmClockInfo(triggerAt, pendingIntent),
            pendingIntent
        )
        ScheduledCallStore.save(
            context,
            ScheduledCall(
                triggerAtMillis = triggerAt,
                mode = config.mode,
                callerName = config.callerName,
                callerNumber = config.callerNumber,
                avatarUri = config.avatarUri,
                delayMillis = config.delayMillis,
                ringtoneUri = config.ringtoneUri,
                answerAudioUri = config.answerAudioUri
            )
        )
        triggerAt
    }

    fun cancel(context: Context) {
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, IncomingCallAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent)
        pendingIntent.cancel()
        ScheduledCallStore.clear(context)
        ExperimentLog.add(context, "已取消尚未触发的来电")
    }
}

class ScheduledCallRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val savedCall = ScheduledCallStore.load(context) ?: return
        if (!IncomingCallScheduler.canScheduleExact(context)) {
            ExperimentLog.add(context, "系统事件后无法恢复计划：精确闹钟权限未开启")
            return
        }

        IncomingCallScheduler.scheduleAt(
            context,
            savedCall.toConfiguration(),
            savedCall.triggerAtMillis
        ).onSuccess {
            ExperimentLog.add(context, "系统事件后已恢复等待中的来电：${intent?.action}")
        }.onFailure {
            ScheduledCallStore.clear(context)
            ExperimentLog.add(context, "恢复计划失败，已清除过期状态：${it.message}")
        }
    }
}

class IncomingCallAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val actualTriggerAt = System.currentTimeMillis()
        val plannedTriggerAt = intent?.getLongExtra(CallIntentExtras.PLANNED_TRIGGER_AT, 0L) ?: 0L
        ScheduledCallStore.clear(context)
        val config = CallConfiguration(
            mode = CallMode.fromStorage(intent?.getStringExtra(CallIntentExtras.MODE)),
            callerName = intent?.getStringExtra(CallIntentExtras.CALLER_NAME)
                ?: TelecomController.DEFAULT_CALLER_NAME,
            callerNumber = intent?.getStringExtra(CallIntentExtras.CALLER_NUMBER)
                ?: TelecomController.DEFAULT_CALLER_NUMBER,
            avatarUri = intent?.getStringExtra(CallIntentExtras.AVATAR_URI).orEmpty(),
            ringtoneUri = intent?.getStringExtra(CallIntentExtras.RINGTONE_URI).orEmpty(),
            answerAudioUri = intent?.getStringExtra(CallIntentExtras.ANSWER_AUDIO_URI).orEmpty()
        )
        val deviation = if (plannedTriggerAt > 0L) actualTriggerAt - plannedTriggerAt else 0L
        ExperimentLog.add(
            context,
            "定时器已触发：${config.mode.label}，偏差 ${deviation} ms"
        )

        if (!config.mode.usesSystemPhoneUi) {
            SimulatedCallNotifier.showIncoming(context, config)
            return
        }

        val telecom = TelecomController(context)
        telecom.registerPhoneAccount()
            .onFailure {
                ExperimentLog.add(context, "重新注册通话账户失败：${it.message}")
                return
            }

        telecom.reportIncomingCall(
            callerName = config.callerName,
            callerNumber = config.callerNumber,
            answerAudioUri = config.answerAudioUri
        )
            .onSuccess { ExperimentLog.add(context, "已调用 addNewIncomingCall") }
            .onFailure { ExperimentLog.add(context, "报告来电失败：${it.message}") }
    }
}
