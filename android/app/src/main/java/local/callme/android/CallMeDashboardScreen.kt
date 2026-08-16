package local.callme.android

import android.Manifest
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import android.telecom.TelecomManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.random.Random

private data class DashboardSetupStatus(
    val phonePermissionGranted: Boolean,
    val phoneAccountEnabled: Boolean,
    val exactAlarmAllowed: Boolean,
    val notificationAllowed: Boolean,
    val fullScreenAllowed: Boolean
)

private enum class DashboardSheet {
    CONTACT,
    TEMPLATES,
    SOUND,
    SETTINGS,
    CUSTOM_DELAY
}

private val dashboardDelayChoices = listOf(
    10_000L to "10 秒",
    30_000L to "30 秒",
    60_000L to "1 分钟",
    180_000L to "3 分钟",
    300_000L to "5 分钟"
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallMeDashboardScreen() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val telecom = remember { TelecomController(context) }
    val previewPlayer = remember { AudioPlayer(context) }

    fun readStatus() = DashboardSetupStatus(
        phonePermissionGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED,
        phoneAccountEnabled = telecom.isAccountEnabled(),
        exactAlarmAllowed = IncomingCallScheduler.canScheduleExact(context),
        notificationAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED,
        fullScreenAllowed = dashboardCanUseFullScreenIntent(context)
    )

    var config by remember { mutableStateOf(CallSettingsStore.load(context)) }
    var setupStatus by remember { mutableStateOf(readStatus()) }
    var scheduledCall by remember { mutableStateOf(ScheduledCallStore.load(context)) }
    var templates by remember { mutableStateOf(CallTemplateStore.load(context)) }
    var events by remember { mutableStateOf(ExperimentLog.read(context)) }
    var message by remember { mutableStateOf("尚未安排") }
    var previewingAudioKey by remember { mutableStateOf<String?>(null) }
    var activeSheet by remember { mutableStateOf<DashboardSheet?>(null) }
    var customDelayValue by remember { mutableStateOf("") }
    var customDelayInMinutes by remember { mutableStateOf(true) }

    fun updateConfig(updated: CallConfiguration) {
        config = updated
        CallSettingsStore.save(context, updated)
    }

    fun persistTemplates(updated: List<CallTemplate>) {
        templates = updated.take(12)
        CallTemplateStore.save(context, templates)
    }

    fun applyTemplate(template: CallTemplate) {
        updateConfig(template.toConfiguration())
        persistTemplates(
            listOf(template.copy(updatedAtMillis = System.currentTimeMillis())) +
                templates.filterNot { it.id == template.id }
        )
    }

    fun refresh() {
        setupStatus = readStatus()
        scheduledCall = ScheduledCallStore.load(context)
        events = ExperimentLog.read(context)
    }

    val phonePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        ExperimentLog.add(context, if (granted) "已允许电话状态权限" else "电话状态权限被拒绝")
        refresh()
    }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        ExperimentLog.add(context, if (granted) "已允许通知权限" else "通知权限被拒绝")
        refresh()
    }
    val avatarPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        dashboardPersistDocumentPermission(context, uri)
        updateConfig(config.copy(avatarUri = uri.toString()))
        ExperimentLog.add(context, "已更新来电人头像")
    }
    val ringtonePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        dashboardPersistAudioPermission(context, uri)
        updateConfig(
            config.copy(
                ringtoneUri = uri.toString(),
                ringtoneName = dashboardQueryDisplayName(context, uri)
            )
        )
        ExperimentLog.add(context, "已选择自定义来电铃声")
    }
    val answerAudioPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        dashboardPersistAudioPermission(context, uri)
        updateConfig(
            config.copy(
                answerAudioUri = uri.toString(),
                answerAudioName = dashboardQueryDisplayName(context, uri)
            )
        )
        ExperimentLog.add(context, "已选择接听后音频")
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refresh()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            previewPlayer.stop()
            previewingAudioKey = null
        }
    }

    val inputsValid = CallInputValidator.callerNameError(config.callerName) == null &&
        CallInputValidator.callerNumberError(config.callerNumber) == null
    val modeReady = if (config.mode.usesSystemPhoneUi) {
        setupStatus.phonePermissionGranted && setupStatus.phoneAccountEnabled
    } else {
        setupStatus.notificationAllowed && setupStatus.fullScreenAllowed
    }
    val ready = inputsValid && setupStatus.exactAlarmAllowed && modeReady

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        val current = scheduledCall
        if (current != null) {
            NativeDashboardWaitingScreen(
                call = current,
                onCancel = {
                    IncomingCallScheduler.cancel(context)
                    message = "已取消安排"
                    refresh()
                }
            )
        } else {
            NativeDashboardHome(
                config = config,
                templates = templates,
                ready = ready,
                message = message,
                onContact = { activeSheet = DashboardSheet.CONTACT },
                onSettings = { activeSheet = DashboardSheet.SETTINGS },
                onTemplate = ::applyTemplate,
                onCustomDelay = {
                    if (dashboardDelayChoices.none { it.first == config.delayMillis }) {
                        if (config.delayMillis % 60_000L == 0L) {
                            customDelayValue = (config.delayMillis / 60_000L).toString()
                            customDelayInMinutes = true
                        } else {
                            customDelayValue = (config.delayMillis / 1_000L).toString()
                            customDelayInMinutes = false
                        }
                    } else {
                        customDelayValue = ""
                        customDelayInMinutes = false
                    }
                    activeSheet = DashboardSheet.CUSTOM_DELAY
                },
                onMode = { updateConfig(config.withModeDefaults(context, it)) },
                onDelay = { updateConfig(config.copy(delayMillis = it)) },
                onSchedule = {
                    IncomingCallScheduler.schedule(context, config)
                        .onSuccess { triggerAt ->
                            val time = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
                                .format(Date(triggerAt))
                            message = "已安排，预计 $time 来电"
                            ExperimentLog.add(
                                context,
                                "已安排 ${config.mode.label}，延迟 ${dashboardDelayLabel(config.delayMillis)}"
                            )
                        }
                        .onFailure {
                            message = "安排失败：${it.message}"
                            ExperimentLog.add(context, message)
                        }
                    refresh()
                }
            )
        }
    }

    if (activeSheet != null) {
        ModalBottomSheet(
            onDismissRequest = { activeSheet = null },
            containerColor = MaterialTheme.colorScheme.surface
        ) {
            when (activeSheet) {
                DashboardSheet.CONTACT -> DashboardContactEditor(
                    config = config,
                    onConfig = ::updateConfig,
                    onChooseAvatar = { avatarPicker.launch(arrayOf("image/*")) },
                    onDone = { activeSheet = null }
                )
                DashboardSheet.TEMPLATES -> DashboardTemplates(
                    config = config,
                    templates = templates,
                    onSave = {
                        val existing = templates.firstOrNull {
                            it.callerName == config.callerName &&
                                it.callerNumber == config.callerNumber &&
                                it.mode == config.mode
                        }
                        val saved = CallTemplate.fromConfiguration(config, existing?.id)
                        persistTemplates(listOf(saved) + templates.filterNot { it.id == saved.id })
                    },
                    onApply = {
                        applyTemplate(it)
                        activeSheet = null
                    },
                    onDelete = { template ->
                        persistTemplates(templates.filterNot { it.id == template.id })
                    },
                    onDone = { activeSheet = null }
                )
                DashboardSheet.SOUND -> DashboardSoundEditor(
                    config = config,
                    onConfig = ::updateConfig,
                    onChooseRingtone = { ringtonePicker.launch(arrayOf("audio/*")) },
                    onChooseAnswerAudio = { answerAudioPicker.launch(arrayOf("audio/*")) },
                    previewingAudioKey = previewingAudioKey,
                    onPreviewRingtone = { uri ->
                        val key = "ringtone:$uri"
                        if (previewingAudioKey == key) {
                            previewPlayer.stop()
                            previewingAudioKey = null
                            message = "已停止试听"
                        } else {
                            previewPlayer.stop()
                            val started = previewPlayer.playRingtone(
                                uriString = uri,
                                looping = false,
                                onCompletion = { previewingAudioKey = null }
                            )
                            previewingAudioKey = if (started) key else null
                            message = if (started) "正在试听" else "无法播放该铃声"
                        }
                    },
                    onPreviewAnswer = {
                        val key = "answer:${config.answerAudioUri}"
                        if (previewingAudioKey == key) {
                            previewPlayer.stop()
                            previewingAudioKey = null
                            message = "已停止试听"
                        } else {
                            previewPlayer.stop()
                            val started = previewPlayer.playAnswerAudio(config.answerAudioUri) {
                                previewingAudioKey = null
                            }
                            previewingAudioKey = if (started) key else null
                            message = if (started) "正在试听" else "无法播放该音频"
                        }
                    },
                    onOpenSystemSound = {
                        context.startActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
                    },
                    onDone = {
                        previewPlayer.stop()
                        previewingAudioKey = null
                        activeSheet = null
                    }
                )
                DashboardSheet.SETTINGS -> DashboardSettings(
                    context = context,
                    config = config,
                    setupStatus = setupStatus,
                    scheduledCall = scheduledCall,
                    events = events,
                    onPhonePermission = {
                        phonePermissionLauncher.launch(Manifest.permission.READ_PHONE_STATE)
                    },
                    onNotificationPermission = {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    },
                    onPhoneAccount = {
                        telecom.registerPhoneAccount()
                        context.startActivity(Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS))
                    },
                    onExactAlarm = {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            dashboardOpenExactAlarmSettings(context)
                        }
                    },
                    onFullScreen = {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            dashboardOpenFullScreenIntentSettings(context)
                        }
                    },
                    onImmediate = {
                        if (config.mode.usesSystemPhoneUi) {
                            telecom.reportIncomingCall(
                                config.callerName,
                                config.callerNumber,
                                config.answerAudioUri
                            ).onFailure { message = "立即测试失败：${it.message}" }
                        } else {
                            SimulatedCallNotifier.showIncoming(context, config)
                        }
                        ExperimentLog.add(context, "立即测试：${config.mode.label}")
                        activeSheet = null
                    },
                    onTemplates = { activeSheet = DashboardSheet.TEMPLATES },
                    onSound = { activeSheet = DashboardSheet.SOUND },
                    onDone = { activeSheet = null }
                )
                DashboardSheet.CUSTOM_DELAY -> DashboardCustomDelay(
                    value = customDelayValue,
                    inMinutes = customDelayInMinutes,
                    onValue = { customDelayValue = it.filter(Char::isDigit) },
                    onUnit = { customDelayInMinutes = it },
                    onApply = {
                        val delayMillis = CallInputValidator.customDelayMillis(
                            customDelayValue,
                            customDelayInMinutes
                        )
                        if (delayMillis == null) {
                            message = "请输入 1 秒到 24 小时之间的有效时间"
                        } else {
                            updateConfig(config.copy(delayMillis = delayMillis))
                            message = "已设为 ${dashboardDelayLabel(delayMillis)}后"
                            activeSheet = null
                        }
                    },
                    onDone = { activeSheet = null }
                )
                null -> Unit
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NativeDashboardHome(
    config: CallConfiguration,
    templates: List<CallTemplate>,
    ready: Boolean,
    message: String,
    onContact: () -> Unit,
    onSettings: () -> Unit,
    onTemplate: (CallTemplate) -> Unit,
    onCustomDelay: () -> Unit,
    onMode: (CallMode) -> Unit,
    onDelay: (Long) -> Unit,
    onSchedule: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 24.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    "CallMe",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    "安排下一通电话",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Surface(
                    shape = CircleShape,
                    color = if (ready) {
                        MaterialTheme.colorScheme.primaryContainer
                    } else {
                        MaterialTheme.colorScheme.errorContainer
                    }
                ) {
                    Text(
                        if (ready) "● 就绪" else "● 待设置",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = if (ready) {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        } else {
                            MaterialTheme.colorScheme.onErrorContainer
                        }
                    )
                }
                Surface(
                    onClick = onSettings,
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceVariant
                ) {
                    Text(
                        "⚙",
                        modifier = Modifier.padding(11.dp),
                        fontSize = 18.sp
                    )
                }
            }
        }

        if (templates.isNotEmpty()) {
            NativeDashboardSectionLabel("快速模板")
            NativeDashboardGroup {
                Column {
                    templates.take(3).forEachIndexed { index, template ->
                        ListItem(
                            modifier = Modifier.fillMaxWidth().clickable { onTemplate(template) },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            leadingContent = {
                                NativeDashboardAvatar(template.callerName, template.avatarUri, 38)
                            },
                            headlineContent = { Text(template.callerName, fontWeight = FontWeight.Medium) },
                            supportingContent = {
                                Text("${nativeDashboardModeLabel(template.mode)} · ${dashboardDelayLabel(template.delayMillis)}")
                            },
                            trailingContent = {
                                Text("套用", style = MaterialTheme.typography.labelMedium)
                            }
                        )
                        if (index < templates.take(3).lastIndex) {
                            HorizontalDivider(modifier = Modifier.padding(start = 62.dp))
                        }
                    }
                }
            }
        }

        NativeDashboardSectionLabel("来电人")
        NativeDashboardGroup {
            ListItem(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onContact),
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                leadingContent = { NativeDashboardAvatar(config.callerName, config.avatarUri, 44) },
                headlineContent = { Text(config.callerName.ifBlank { "未设置" }, fontWeight = FontWeight.Medium) },
                supportingContent = { Text(config.callerNumber) },
                trailingContent = {
                    Text(
                        "›",
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            )
        }

        NativeDashboardSectionLabel("来电方式")
        NativeDashboardGroup {
            SingleChoiceSegmentedButtonRow(
                modifier = Modifier.fillMaxWidth().padding(10.dp)
            ) {
                CallMode.entries.forEachIndexed { index, mode ->
                    SegmentedButton(
                        modifier = Modifier.height(44.dp),
                        shape = SegmentedButtonDefaults.itemShape(index, CallMode.entries.size),
                        selected = config.mode == mode,
                        onClick = { onMode(mode) },
                        icon = {},
                        colors = nativeSegmentedColors()
                    ) {
                        Text(nativeDashboardModeLabel(mode), maxLines = 1, fontSize = 12.sp)
                    }
                }
            }
        }

        NativeDashboardSectionLabel("来电时间")
        NativeDashboardGroup {
            Column {
                Column(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    dashboardDelayChoices.chunked(3).forEach { rowChoices ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            rowChoices.forEach { (delayMillis, label) ->
                                DashboardDelayButton(
                                    label = label,
                                    selected = config.delayMillis == delayMillis,
                                    modifier = Modifier.weight(1f),
                                    onClick = { onDelay(delayMillis) }
                                )
                            }
                        }
                    }
                }
                ListItem(
                    modifier = Modifier.clickable(onClick = onCustomDelay),
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    headlineContent = { Text("精确时间") },
                    supportingContent = {
                        Text("支持 1 秒至 24 小时")
                    },
                    trailingContent = {
                        Text(
                            if (dashboardDelayChoices.none { it.first == config.delayMillis }) {
                                dashboardDelayLabel(config.delayMillis)
                            } else {
                                "自定义  ›"
                            },
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                )
            }
        }

        Button(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 24.dp)
                .height(56.dp),
            enabled = ready,
            shape = RoundedCornerShape(18.dp),
            onClick = onSchedule
        ) {
            Text(
                "${dashboardDelayLabel(config.delayMillis)}后安排来电",
                fontWeight = FontWeight.SemiBold
            )
        }

        Text(
            if (ready) "${dashboardDelayLabel(config.delayMillis)}后来电" else message,
            modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (!ready) {
            TextButton(modifier = Modifier.fillMaxWidth(), onClick = onSettings) {
                Text("完成设备设置")
            }
        }
    }
}

@Composable
private fun NativeDashboardSectionLabel(title: String) {
    Text(
        title,
        modifier = Modifier.padding(horizontal = 22.dp).padding(top = 12.dp, bottom = 7.dp),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun NativeDashboardGroup(content: @Composable () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.48f),
        tonalElevation = 0.dp
    ) {
        content()
    }
}

@Composable
private fun nativeSegmentedColors() = SegmentedButtonDefaults.colors(
    activeContainerColor = MaterialTheme.colorScheme.primaryContainer,
    activeContentColor = MaterialTheme.colorScheme.onPrimaryContainer,
    activeBorderColor = MaterialTheme.colorScheme.outlineVariant,
    inactiveContainerColor = Color.Transparent,
    inactiveContentColor = MaterialTheme.colorScheme.onSurface,
    inactiveBorderColor = MaterialTheme.colorScheme.outlineVariant
)

private fun nativeDashboardModeLabel(mode: CallMode): String = when (mode) {
    CallMode.SYSTEM_PHONE -> "电话"
    CallMode.WECHAT_VOICE -> "微信语音"
    CallMode.WECHAT_VIDEO -> "微信视频"
}

@Composable
private fun NativeDashboardAvatar(name: String, avatarUri: String, size: Int) = CallMeAvatar(
    name = name,
    avatarUri = avatarUri,
    size = size,
    fallbackBackground = MaterialTheme.colorScheme.surfaceVariant,
    fallbackForeground = MaterialTheme.colorScheme.onSurfaceVariant
)

@Composable
private fun NativeDashboardWaitingScreen(call: ScheduledCall, onCancel: () -> Unit) {
    var nowMillis by remember(call.triggerAtMillis) { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(call.triggerAtMillis) {
        while (nowMillis < call.triggerAtMillis) {
            delay(1_000)
            nowMillis = System.currentTimeMillis()
        }
    }
    val seconds = ((call.triggerAtMillis - nowMillis).coerceAtLeast(0L) + 999L) / 1_000L
    val countdown = "%02d:%02d".format(seconds / 60, seconds % 60)

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("已安排", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.weight(1f))
        Text(countdown, fontSize = 64.sp, fontWeight = FontWeight.Normal)
        Spacer(Modifier.height(12.dp))
        Text(
            "${call.callerName} · ${nativeDashboardModeLabel(call.mode)}",
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            "预计 ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(call.triggerAtMillis))} 来电",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.weight(1f))
        Text(
            "现在可以锁屏",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(16.dp))
        OutlinedButton(onClick = onCancel) { Text("取消安排") }
    }
}

@Composable
private fun DashboardContactEditor(
    config: CallConfiguration,
    onConfig: (CallConfiguration) -> Unit,
    onChooseAvatar: () -> Unit,
    onDone: () -> Unit
) {
    DashboardSheetColumn {
        DashboardSheetHeader("编辑来电人", onDone)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            DashboardAvatar(config.callerName, config.avatarUri, 72)
            Column(modifier = Modifier.weight(1f)) {
                TextButton(onClick = onChooseAvatar, contentPadding = PaddingValues(0.dp)) {
                    Text(if (config.avatarUri.isBlank()) "选择头像" else "更换头像")
                }
                if (config.avatarUri.isNotBlank()) {
                    TextButton(
                        onClick = { onConfig(config.copy(avatarUri = "")) },
                        contentPadding = PaddingValues(0.dp)
                    ) { Text("移除头像") }
                }
            }
        }
        OutlinedTextField(
            modifier = Modifier.fillMaxWidth(),
            value = config.callerName,
            onValueChange = { onConfig(config.copy(callerName = it)) },
            label = { Text("姓名") },
            singleLine = true,
            isError = CallInputValidator.callerNameError(config.callerName) != null
        )
        OutlinedTextField(
            modifier = Modifier.fillMaxWidth(),
            value = config.callerNumber,
            onValueChange = { onConfig(config.copy(callerNumber = it)) },
            label = { Text("显示号码") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
            isError = CallInputValidator.callerNumberError(config.callerNumber) != null
        )
        OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = {
            onConfig(config.copy(callerNumber = dashboardRandomMobileNumber()))
        }) { Text("生成随机手机号") }
        Text("号码只用于界面显示，不会拨出真实电话。", fontSize = 12.sp, color = Color(0xFF817B89))
    }
}

@Composable
private fun DashboardSoundEditor(
    config: CallConfiguration,
    onConfig: (CallConfiguration) -> Unit,
    onChooseRingtone: () -> Unit,
    onChooseAnswerAudio: () -> Unit,
    previewingAudioKey: String?,
    onPreviewRingtone: (String) -> Unit,
    onPreviewAnswer: () -> Unit,
    onOpenSystemSound: () -> Unit,
    onDone: () -> Unit
) {
    val context = LocalContext.current
    val selectedPreset = BuiltInRingtone.matching(context, config.ringtoneUri)

    DashboardSheetColumn {
        DashboardSheetHeader("声音与接听", onDone)

        DashboardInsetCard {
            Text("来电铃声", fontWeight = FontWeight.SemiBold)
            Text(
                if (config.mode.usesSystemPhoneUi) "手机来电" else config.mode.label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            BuiltInRingtone.choices(config.mode).forEachIndexed { index, preset ->
                val uri = preset.uri(context)
                DashboardRingtoneRow(
                    title = preset.label,
                    selected = selectedPreset == preset,
                    playing = previewingAudioKey == "ringtone:$uri",
                    onSelect = {
                        onConfig(config.copy(ringtoneUri = uri, ringtoneName = preset.label))
                    },
                    onPreview = { onPreviewRingtone(uri) }
                )
                if (index < BuiltInRingtone.choices(config.mode).lastIndex) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }

            if (selectedPreset == null && config.ringtoneUri.isNotBlank()) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                DashboardRingtoneRow(
                    title = config.ringtoneName,
                    selected = true,
                    playing = previewingAudioKey == "ringtone:${config.ringtoneUri}",
                    onSelect = {},
                    onPreview = { onPreviewRingtone(config.ringtoneUri) }
                )
            }

            if (config.mode.usesSystemPhoneUi) {
                TextButton(modifier = Modifier.fillMaxWidth(), onClick = onOpenSystemSound) {
                    Text("打开系统声音设置")
                }
            } else {
                OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onChooseRingtone) {
                    Text("导入其他音效")
                }
            }
            Text(
                if (config.mode.usesSystemPhoneUi) {
                    "手机来电由 Android 系统通话界面接管，铃声和音量需在系统设置中修改。"
                } else {
                    "“微信经典”来自本机官方微信安装包。点击名称选择，点击右侧按钮播放或停止。"
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        DashboardInsetCard {
            Text("接听后播放", fontWeight = FontWeight.SemiBold)
            Text(
                config.answerAudioName,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                OutlinedButton(modifier = Modifier.weight(1f), onClick = onChooseAnswerAudio) {
                    Text(if (config.answerAudioUri.isBlank()) "选择音频" else "更换音频")
                }
                Button(
                    modifier = Modifier.weight(1f),
                    enabled = config.answerAudioUri.isNotBlank(),
                    onClick = onPreviewAnswer
                ) {
                    Text(
                        if (previewingAudioKey == "answer:${config.answerAudioUri}") {
                            "停止播放"
                        } else {
                            "播放"
                        }
                    )
                }
            }
            if (config.answerAudioUri.isNotBlank()) {
                TextButton(
                    contentPadding = PaddingValues(0.dp),
                    onClick = {
                        onConfig(config.copy(answerAudioUri = "", answerAudioName = "无（静音）"))
                    }
                ) {
                    Text("删除接听音频")
                }
            }
        }
    }
}

@Composable
private fun DashboardRingtoneRow(
    title: String,
    selected: Boolean,
    playing: Boolean,
    onSelect: () -> Unit,
    onPreview: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(24.dp)
                .background(
                    if (selected) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.surface,
                    CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                if (selected) "✓" else "",
                color = MaterialTheme.colorScheme.onPrimary,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Text(
            title,
            modifier = Modifier.weight(1f).padding(start = 12.dp),
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
        )
        TextButton(onClick = onPreview) {
            Text(if (playing) "■ 停止" else "▶ 播放")
        }
    }
}

@Composable
private fun DashboardSettings(
    context: Context,
    config: CallConfiguration,
    setupStatus: DashboardSetupStatus,
    scheduledCall: ScheduledCall?,
    events: List<String>,
    onPhonePermission: () -> Unit,
    onNotificationPermission: () -> Unit,
    onPhoneAccount: () -> Unit,
    onExactAlarm: () -> Unit,
    onFullScreen: () -> Unit,
    onImmediate: () -> Unit,
    onTemplates: () -> Unit,
    onSound: () -> Unit,
    onDone: () -> Unit
) {
    DashboardSheetColumn {
        DashboardSheetHeader("设置与诊断", onDone)
        ListItem(
            modifier = Modifier.clickable(onClick = onTemplates),
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
            headlineContent = { Text("来电模板") },
            supportingContent = { Text("保存、套用和删除本地模板") },
            trailingContent = { Text("›", style = MaterialTheme.typography.titleLarge) }
        )
        ListItem(
            modifier = Modifier.clickable(onClick = onSound),
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
            headlineContent = { Text("声音与接听") },
            supportingContent = { Text("铃声、试听和接听后音频") },
            trailingContent = { Text("›", style = MaterialTheme.typography.titleLarge) }
        )
        DashboardInsetCard {
            Text("设备准备", fontWeight = FontWeight.SemiBold)
            DashboardStatusRow("精确闹钟", setupStatus.exactAlarmAllowed)
            if (config.mode.usesSystemPhoneUi) {
                DashboardStatusRow("电话状态权限", setupStatus.phonePermissionGranted)
                DashboardStatusRow("CallMe 通话账户", setupStatus.phoneAccountEnabled)
                if (!setupStatus.phonePermissionGranted) {
                    OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onPhonePermission) {
                        Text("允许电话状态权限")
                    }
                }
                if (!setupStatus.phoneAccountEnabled) {
                    OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onPhoneAccount) {
                        Text("启用 CallMe 通话账户")
                    }
                }
            } else {
                DashboardStatusRow("通知权限", setupStatus.notificationAllowed)
                DashboardStatusRow("锁屏全屏来电", setupStatus.fullScreenAllowed)
                if (!setupStatus.notificationAllowed) {
                    OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onNotificationPermission) {
                        Text("允许来电通知")
                    }
                }
                if (!setupStatus.fullScreenAllowed) {
                    OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onFullScreen) {
                        Text("允许全屏来电")
                    }
                }
            }
            if (!setupStatus.exactAlarmAllowed) {
                OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = onExactAlarm) {
                    Text("允许精确闹钟")
                }
            }
        }
        Button(modifier = Modifier.fillMaxWidth(), onClick = onImmediate) {
            Text("立即预览当前来电")
        }
        DashboardInsetCard {
            Text("手机适配", fontWeight = FontWeight.SemiBold)
            Text(
                "${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE}",
                fontSize = 12.sp
            )
            val callUiProfile = AndroidCallUiProfiles.current()
            Text(
                "界面配置：${callUiProfile.displayName}",
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
            )
            Text(
                callUiProfile.referenceStatus,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(dashboardCompatibilityTip(), fontSize = 12.sp, color = Color(0xFF817B89))
            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                onClick = { dashboardOpenVendorBackgroundSettings(context) }
            ) { Text("后台弹窗与自启动设置") }
            OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = {
                context.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        "package:${context.packageName}".toUri()
                    )
                )
            }) { Text("打开系统设置") }
            OutlinedButton(modifier = Modifier.fillMaxWidth(), onClick = {
                val report = dashboardDiagnosticReport(
                    context = context,
                    config = config,
                    setupStatus = setupStatus,
                    scheduledCall = scheduledCall,
                    events = events
                )
                context.getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("CallMe 诊断报告", report))
                Toast.makeText(context, "诊断报告已复制", Toast.LENGTH_SHORT).show()
            }) { Text("复制完整诊断报告") }
            Text(
                "报告不包含铃声或接听音频文件。",
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        DashboardInsetCard {
            Text("最近活动", fontWeight = FontWeight.SemiBold)
            if (events.isEmpty()) {
                Text("暂无记录", color = Color(0xFF817B89), fontSize = 12.sp)
            } else {
                events.take(8).forEach { Text(it, color = Color(0xFF817B89), fontSize = 11.sp) }
            }
        }
    }
}

@Composable
private fun DashboardTemplates(
    config: CallConfiguration,
    templates: List<CallTemplate>,
    onSave: () -> Unit,
    onApply: (CallTemplate) -> Unit,
    onDelete: (CallTemplate) -> Unit,
    onDone: () -> Unit
) {
    DashboardSheetColumn {
        DashboardSheetHeader("来电模板", onDone)
        Button(
            modifier = Modifier.fillMaxWidth(),
            enabled = CallInputValidator.callerNameError(config.callerName) == null &&
                CallInputValidator.callerNumberError(config.callerNumber) == null,
            onClick = onSave
        ) {
            Text("保存当前配置")
        }
        Text(
            "当前：${config.callerName} · ${nativeDashboardModeLabel(config.mode)} · ${dashboardDelayLabel(config.delayMillis)}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (templates.isEmpty()) {
            DashboardInsetCard {
                Text("还没有模板", fontWeight = FontWeight.SemiBold)
                Text(
                    "在首页完成配置后，点击上方按钮保存。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            templates.forEach { template ->
                DashboardInsetCard {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        NativeDashboardAvatar(template.callerName, template.avatarUri, 42)
                        Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
                            Text(template.callerName, fontWeight = FontWeight.SemiBold)
                            Text(
                                template.callerNumber,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                "${nativeDashboardModeLabel(template.mode)} · ${dashboardDelayLabel(template.delayMillis)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        OutlinedButton(
                            modifier = Modifier.weight(1f),
                            onClick = { onDelete(template) }
                        ) { Text("删除") }
                        Button(
                            modifier = Modifier.weight(1f),
                            onClick = { onApply(template) }
                        ) { Text("套用") }
                    }
                }
            }
        }
        Text(
            "模板仅保存在本机，最多 12 个。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun DashboardCustomDelay(
    value: String,
    inMinutes: Boolean,
    onValue: (String) -> Unit,
    onUnit: (Boolean) -> Unit,
    onApply: () -> Unit,
    onDone: () -> Unit
) {
    DashboardSheetColumn {
        DashboardSheetHeader("自定义时间", onDone)
        OutlinedTextField(
            modifier = Modifier.fillMaxWidth(),
            value = value,
            onValueChange = onValue,
            label = { Text("数值") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
        )
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            DashboardDelayButton(
                modifier = Modifier.weight(1f),
                label = "秒",
                selected = !inMinutes,
                onClick = { onUnit(false) }
            )
            DashboardDelayButton(
                modifier = Modifier.weight(1f),
                label = "分钟",
                selected = inMinutes,
                onClick = { onUnit(true) }
            )
        }
        Button(modifier = Modifier.fillMaxWidth().height(54.dp), onClick = onApply) {
            Text("使用这个时间", fontWeight = FontWeight.Bold)
        }
        Text("支持 1 秒到 24 小时。", fontSize = 12.sp, color = Color(0xFF817B89))
    }
}

@Composable
private fun DashboardSheetColumn(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 36.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) { content() }
}

@Composable
private fun DashboardSheetHeader(title: String, onDone: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        TextButton(onClick = onDone) { Text("完成") }
    }
}

@Composable
private fun DashboardInsetCard(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(14.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp)
    ) { content() }
}

@Composable
private fun DashboardDelayButton(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Surface(
        modifier = modifier.height(48.dp),
        shape = RoundedCornerShape(13.dp),
        color = if (selected) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surface
        },
        contentColor = if (selected) {
            MaterialTheme.colorScheme.onPrimaryContainer
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
        },
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        onClick = onClick
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                if (selected) "✓  $label" else label,
                fontSize = 14.sp,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun DashboardAvatar(name: String, avatarUri: String, size: Int) = NativeDashboardAvatar(
    name,
    avatarUri,
    size
)

@Composable
private fun DashboardStatusRow(label: String, complete: Boolean) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, fontSize = 13.sp)
        Text(
            if (complete) "已完成" else "待处理",
            color = if (complete) Color(0xFF198754) else Color(0xFFC33C45),
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

private fun dashboardDelayLabel(delayMillis: Long): String = dashboardDelayChoices
    .firstOrNull { it.first == delayMillis }
    ?.second
    ?: when {
        delayMillis % 3_600_000L == 0L -> "${delayMillis / 3_600_000L} 小时"
        delayMillis % 60_000L == 0L -> "${delayMillis / 60_000L} 分钟"
        else -> "${delayMillis / 1_000L} 秒"
    }

private fun dashboardRandomMobileNumber(): String {
    val prefixes = listOf(
        "130", "131", "132", "133", "135", "136", "137", "138", "139",
        "150", "151", "152", "153", "155", "156", "157", "158", "159",
        "166", "173", "175", "176", "177", "178", "180", "181", "182",
        "183", "185", "186", "187", "188", "189", "191", "193", "195",
        "196", "198", "199"
    )
    return prefixes.random() + Random.nextInt(0, 100_000_000).toString().padStart(8, '0')
}

private fun dashboardPersistDocumentPermission(context: Context, uri: Uri) {
    runCatching {
        context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}

private fun dashboardPersistAudioPermission(context: Context, uri: Uri) =
    dashboardPersistDocumentPermission(context, uri)

private fun dashboardQueryDisplayName(context: Context, uri: Uri): String {
    var cursor: Cursor? = null
    return runCatching {
        cursor = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        if (cursor?.moveToFirst() == true) cursor?.getString(0) ?: "已选择音频" else "已选择音频"
    }.getOrDefault("已选择音频").also { cursor?.close() }
}

private fun dashboardCanUseFullScreenIntent(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
    return context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
}

private fun dashboardDiagnosticReport(
    context: Context,
    config: CallConfiguration,
    setupStatus: DashboardSetupStatus,
    scheduledCall: ScheduledCall?,
    events: List<String>
): String {
    val packageVersion = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        "${info.versionName ?: "开发版"} ($versionCode)"
    }.getOrDefault("开发版")
    val scheduled = scheduledCall?.let {
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())
            .format(Date(it.triggerAtMillis))
    } ?: "无"
    val recentEvents = events.take(20).joinToString("\n").ifBlank { "暂无记录" }
    return """
        CallMe Android 诊断报告
        生成时间：${SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault()).format(Date())}
        设备：${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})
        系统：Android ${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}
        界面配置：${AndroidCallUiProfiles.current().displayName}
        配置状态：${AndroidCallUiProfiles.current().referenceStatus}
        App：$packageVersion
        来电方式：${config.mode.label}
        来电人：${config.callerName}
        显示号码：${config.callerNumber}
        延迟：${dashboardDelayLabel(config.delayMillis)}
        计划触发：$scheduled
        精确闹钟：${if (setupStatus.exactAlarmAllowed) "已允许" else "未允许"}
        电话状态权限：${if (setupStatus.phonePermissionGranted) "已允许" else "未允许"}
        CallMe 通话账户：${if (setupStatus.phoneAccountEnabled) "已启用" else "未启用"}
        通知权限：${if (setupStatus.notificationAllowed) "已允许" else "未允许"}
        全屏来电：${if (setupStatus.fullScreenAllowed) "已允许" else "未允许"}
        铃声：${config.ringtoneName}
        接听音频：${config.answerAudioName}

        最近活动：
        $recentEvents
    """.trimIndent()
}

@RequiresApi(Build.VERSION_CODES.S)
private fun dashboardOpenExactAlarmSettings(context: Context) {
    context.startActivity(
        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, "package:${context.packageName}".toUri())
    )
}

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
private fun dashboardOpenFullScreenIntentSettings(context: Context) {
    context.startActivity(
        Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, "package:${context.packageName}".toUri())
    )
}

private fun dashboardCompatibilityTip(): String = when (Build.MANUFACTURER.lowercase(Locale.ROOT)) {
    "xiaomi", "redmi" -> "请允许“后台弹出界面”和自启动，并把省电策略设为“无限制”。"
    "huawei", "honor" -> "在应用启动管理中允许自动启动、关联启动和后台活动。"
    "oppo", "oneplus", "realme" -> "允许自启动和后台运行，并关闭该 App 的省电限制。"
    "vivo", "iqoo" -> "允许后台高耗电、自启动和锁屏显示。"
    "samsung" -> "从“后台使用限制”的休眠应用中移除 CallMe。"
    else -> "允许 CallMe 后台运行并取消电池优化。"
}

private fun dashboardOpenVendorBackgroundSettings(context: Context) {
    val packageName = context.packageName
    val candidates = when (AndroidCallUiProfiles.current().family) {
        AndroidCallUiFamily.XIAOMI -> listOf(
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity"
                )
                putExtra("extra_pkgname", packageName)
            },
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.AppPermissionsEditorActivity"
                )
                putExtra("extra_pkgname", packageName)
            }
        )
        AndroidCallUiFamily.HUAWEI_HONOR -> listOf(
            Intent().setComponent(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"
                )
            )
        )
        AndroidCallUiFamily.OPPO_FAMILY -> listOf(
            Intent().setComponent(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.oplus.safecenter",
                    "com.oplus.safecenter.startupapp.StartupAppListActivity"
                )
            )
        )
        AndroidCallUiFamily.VIVO_FAMILY -> listOf(
            Intent().setComponent(
                ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                )
            )
        )
        AndroidCallUiFamily.SAMSUNG -> listOf(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        )
        AndroidCallUiFamily.GOOGLE_AOSP -> emptyList()
    }
    val fallback = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        "package:$packageName".toUri()
    )
    val openedVendorPage = candidates.any { candidate ->
        runCatching {
            context.startActivity(candidate)
            true
        }.getOrDefault(false)
    }
    if (!openedVendorPage) {
        context.startActivity(fallback)
    }
}
