package local.callme.android

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.ImageDecoder
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import android.widget.RemoteViews

object SimulatedCallNotifier {
    const val NOTIFICATION_ID = 2001
    private const val CHANNEL_ID = "callme_calls_v5"
    private val LEGACY_CHANNEL_IDS = listOf(
        "callme_simulated_calls_v1",
        "callme_simulated_calls_v2",
        "callme_calls_v3",
        "callme_calls_v4"
    )
    const val ACTION_DECLINE = "local.callme.action.DECLINE"
    const val ACTION_ANSWER = "local.callme.action.ANSWER"
    const val ACTION_INCOMING = "local.callme.action.INCOMING"

    fun showIncoming(context: Context, config: CallConfiguration) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ExperimentLog.add(context, "微信来电失败：通知权限未开启")
            return
        }

        ActiveSimulatedCallStore.save(context, config)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val allowed = context.getSystemService(NotificationManager::class.java)
                .canUseFullScreenIntent()
            ExperimentLog.add(
                context,
                if (allowed) "系统允许微信来电全屏显示" else "微信来电只能通知：系统未允许全屏来电"
            )
        }
        val serviceIntent = Intent(context, SimulatedCallRingingService::class.java).apply {
            putExtra(CallIntentExtras.MODE, config.mode.name)
            putExtra(CallIntentExtras.CALLER_NAME, config.callerName)
            putExtra(CallIntentExtras.CALLER_NUMBER, config.callerNumber)
            putExtra(CallIntentExtras.AVATAR_URI, config.avatarUri)
            putExtra(CallIntentExtras.RINGTONE_URI, config.ringtoneUri)
            putExtra(CallIntentExtras.ANSWER_AUDIO_URI, config.answerAudioUri)
        }
        runCatching { ContextCompat.startForegroundService(context, serviceIntent) }
            .onFailure { ExperimentLog.add(context, "启动来电响铃服务失败：${it.message}") }

        // Full-screen notifications are the standards-compliant path. Some vendor systems only
        // present them after their separate "background pop-up" permission is enabled, so also
        // make an explicit best-effort launch. If the OS rejects it, the notification and launcher
        // recovery path remain available.
        runCatching { context.startActivity(incomingActivityIntent(context, config, ACTION_INCOMING)) }
            .onSuccess { ExperimentLog.add(context, "已请求显示微信来电页面") }
            .onFailure { ExperimentLog.add(context, "请求显示微信来电页面失败：${it.message}") }
    }

    fun buildNotification(context: Context, config: CallConfiguration): android.app.Notification {
        createChannel(context)

        val fullScreenIntent = activityPendingIntent(context, config, ACTION_INCOMING, 21)
        val answerIntent = activityPendingIntent(context, config, ACTION_ANSWER, 22)
        val declineIntent = PendingIntent.getBroadcast(
            context,
            23,
            Intent(context, SimulatedCallActionReceiver::class.java).apply {
                action = ACTION_DECLINE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val callerBuilder = Person.Builder()
            .setName(config.callerName)
            .setImportant(true)
        loadCallerIcon(context, config.avatarUri)?.let(callerBuilder::setIcon)
        val caller = callerBuilder.build()
        val invitation = if (config.mode == CallMode.WECHAT_VIDEO) {
            "邀请你视频通话."
        } else {
            "邀请你语音通话."
        }

        val compactCallView = incomingCallRemoteView(
            context = context,
            config = config,
            answerIntent = answerIntent,
            declineIntent = declineIntent
        )

        // CallStyle is deliberately not used here. Its buttons and spacing are rendered by the
        // device system UI, which meant our Xiaomi/WeChat visual changes could never appear in
        // the heads-up card. A custom heads-up RemoteViews surface keeps the locked-screen
        // full-screen intent while making the unlocked banner match the configured caller.
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle(config.callerName)
            .setContentText(invitation)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenIntent, true)
            .setContentIntent(fullScreenIntent)
            .setCustomContentView(compactCallView)
            .setCustomBigContentView(compactCallView)
            .setCustomHeadsUpContentView(compactCallView)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .addPerson(caller)
            .build()
    }

    private fun incomingCallRemoteView(
        context: Context,
        config: CallConfiguration,
        answerIntent: PendingIntent,
        declineIntent: PendingIntent
    ): RemoteViews {
        val invitation = if (config.mode == CallMode.WECHAT_VIDEO) {
            "邀请你视频通话."
        } else {
            "邀请你语音通话."
        }
        return RemoteViews(context.packageName, R.layout.notification_incoming_call).apply {
            setTextViewText(R.id.incoming_caller_name, config.callerName)
            setTextViewText(R.id.incoming_call_type, invitation)
            setOnClickPendingIntent(R.id.incoming_decline, declineIntent)
            setOnClickPendingIntent(R.id.incoming_answer, answerIntent)
            loadCallerBitmap(context, config.avatarUri)?.let {
                setImageViewBitmap(R.id.incoming_avatar, it)
            }
        }
    }

    private fun loadCallerIcon(context: Context, avatarUri: String): IconCompat? {
        if (avatarUri.isBlank()) return null
        return runCatching {
            val uri = Uri.parse(avatarUri)
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri))
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
            }
            IconCompat.createWithAdaptiveBitmap(bitmap)
        }.getOrNull()
    }

    private fun loadCallerBitmap(context: Context, avatarUri: String): Bitmap? {
        if (avatarUri.isBlank()) return null
        return runCatching {
            val uri = Uri.parse(avatarUri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) {
                        decoder, _, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.isMutableRequired = false
                }
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
            }
        }.getOrNull()
    }

    fun cancel(context: Context) {
        ActiveSimulatedCallStore.clear(context)
        context.stopService(Intent(context, SimulatedCallRingingService::class.java))
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    fun incomingActivityIntent(
        context: Context,
        config: CallConfiguration,
        action: String = ACTION_INCOMING
    ): Intent = Intent(context, SimulatedCallActivity::class.java).apply {
        this.action = action
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_ACTIVITY_CLEAR_TOP
        putExtra(CallIntentExtras.MODE, config.mode.name)
        putExtra(CallIntentExtras.CALLER_NAME, config.callerName)
        putExtra(CallIntentExtras.CALLER_NUMBER, config.callerNumber)
        putExtra(CallIntentExtras.AVATAR_URI, config.avatarUri)
        putExtra(CallIntentExtras.RINGTONE_URI, config.ringtoneUri)
        putExtra(CallIntentExtras.ANSWER_AUDIO_URI, config.answerAudioUri)
    }

    private fun activityPendingIntent(
        context: Context,
        config: CallConfiguration,
        action: String,
        requestCode: Int
    ): PendingIntent {
        return PendingIntent.getActivity(
            context,
            requestCode,
            incomingActivityIntent(context, config, action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        LEGACY_CHANNEL_IDS.forEach(manager::deleteNotificationChannel)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "语音和视频来电",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "用于接收已安排的语音和视频来电"
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                enableVibration(true)
                // The foreground ringing service plays the chosen sound.
                setSound(null, null)
            }
        )
    }
}

class SimulatedCallRingingService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable {
        ExperimentLog.add(this, "微信来电 60 秒无人接听，已自动结束")
        SimulatedCallNotifier.cancel(this)
    }
    private lateinit var audioPlayer: AudioPlayer

    override fun onCreate() {
        super.onCreate()
        audioPlayer = AudioPlayer(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        handler.removeCallbacks(timeoutRunnable)
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
        ActiveSimulatedCallStore.save(this, config)
        startForeground(
            SimulatedCallNotifier.NOTIFICATION_ID,
            SimulatedCallNotifier.buildNotification(this, config)
        )
        if (!audioPlayer.playRingtone(config.ringtoneUri)) {
            ExperimentLog.add(this, "自定义铃声无法播放")
        }
        ExperimentLog.add(this, "已启动微信来电响铃和全屏通知")
        handler.postDelayed(timeoutRunnable, 60_000L)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeoutRunnable)
        audioPlayer.stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

class SimulatedCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == SimulatedCallNotifier.ACTION_DECLINE) {
            SimulatedCallNotifier.cancel(context)
            ExperimentLog.add(context, "用户从通知拒绝微信来电")
        }
    }
}
