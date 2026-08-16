package local.callme.android

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.hardware.camera2.CameraCharacteristics
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

class SimulatedCallActivity : ComponentActivity() {
    private val callUiProfile by lazy { AndroidCallUiProfiles.current() }
    private val configState = mutableStateOf(CallConfiguration(mode = CallMode.WECHAT_VOICE))
    private val answeredState = mutableStateOf(false)
    private val connectedAtState = mutableLongStateOf(0L)
    private val cameraPermissionState = mutableStateOf(false)
    private val useFrontCameraState = mutableStateOf(true)
    private val cameraEnabledState = mutableStateOf(true)
    private val mutedState = mutableStateOf(false)
    private val speakerEnabledState = mutableStateOf(false)
    private val ignoredState = mutableStateOf(false)
    private val blurEnabledState = mutableStateOf(false)
    private val selfViewPrimaryState = mutableStateOf(false)
    private lateinit var audioPlayer: AudioPlayer

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.BLACK
        audioPlayer = AudioPlayer(this)
        handleIntent(intent, resetCallState = savedInstanceState == null)
        ensureCameraPermission()
        if (savedInstanceState != null) {
            answeredState.value = savedInstanceState.getBoolean(STATE_ANSWERED)
            connectedAtState.longValue = savedInstanceState.getLong(STATE_CONNECTED_AT)
            cameraEnabledState.value = savedInstanceState.getBoolean(STATE_CAMERA_ENABLED, true)
            mutedState.value = savedInstanceState.getBoolean(STATE_MUTED)
            speakerEnabledState.value = savedInstanceState.getBoolean(STATE_SPEAKER)
            ignoredState.value = savedInstanceState.getBoolean(STATE_IGNORED)
            blurEnabledState.value = savedInstanceState.getBoolean(STATE_BLUR_ENABLED)
            selfViewPrimaryState.value = savedInstanceState.getBoolean(STATE_SELF_VIEW_PRIMARY)
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                endCall(if (answeredState.value) "用户返回并结束微信通话" else "用户返回并拒绝微信来电")
            }
        })

        setContent {
            MaterialTheme {
                SimulatedCallScreen(
                    config = configState.value,
                    uiProfile = callUiProfile,
                    answered = answeredState.value,
                    connectedAtMillis = connectedAtState.longValue,
                    cameraPermissionGranted = cameraPermissionState.value,
                    cameraEnabled = cameraEnabledState.value,
                    useFrontCamera = useFrontCameraState.value,
                    muted = mutedState.value,
                    speakerEnabled = speakerEnabledState.value,
                    ignored = ignoredState.value,
                    blurEnabled = blurEnabledState.value,
                    selfViewPrimary = selfViewPrimaryState.value,
                    onAnswer = { answerCall() },
                    onDecline = { endCall("用户拒绝微信来电") },
                    onHangUp = { endCall("用户结束微信通话") },
                    onIgnore = { ignoreIncoming() },
                    onFlipCamera = { useFrontCameraState.value = !useFrontCameraState.value },
                    onToggleCamera = { cameraEnabledState.value = !cameraEnabledState.value },
                    onToggleBlur = { blurEnabledState.value = !blurEnabledState.value },
                    onToggleSelfView = { selfViewPrimaryState.value = !selfViewPrimaryState.value },
                    onToggleMute = { mutedState.value = !mutedState.value },
                    onToggleSpeaker = {
                        setSpeakerEnabled(!speakerEnabledState.value)
                    }
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent, resetCallState = true)
        ensureCameraPermission()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            cameraPermissionState.value = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(STATE_ANSWERED, answeredState.value)
        outState.putLong(STATE_CONNECTED_AT, connectedAtState.longValue)
        outState.putBoolean(STATE_CAMERA_ENABLED, cameraEnabledState.value)
        outState.putBoolean(STATE_MUTED, mutedState.value)
        outState.putBoolean(STATE_SPEAKER, speakerEnabledState.value)
        outState.putBoolean(STATE_IGNORED, ignoredState.value)
        outState.putBoolean(STATE_BLUR_ENABLED, blurEnabledState.value)
        outState.putBoolean(STATE_SELF_VIEW_PRIMARY, selfViewPrimaryState.value)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        resetAudioRoute()
        audioPlayer.stop()
        if (isFinishing) {
            SimulatedCallNotifier.cancel(this)
        }
        super.onDestroy()
    }

    private fun handleIntent(intent: Intent, resetCallState: Boolean) {
        configState.value = CallConfiguration(
            mode = CallMode.fromStorage(intent.getStringExtra(CallIntentExtras.MODE)),
            callerName = intent.getStringExtra(CallIntentExtras.CALLER_NAME)
                ?: TelecomController.DEFAULT_CALLER_NAME,
            callerNumber = intent.getStringExtra(CallIntentExtras.CALLER_NUMBER)
                ?: TelecomController.DEFAULT_CALLER_NUMBER,
            avatarUri = intent.getStringExtra(CallIntentExtras.AVATAR_URI).orEmpty(),
            ringtoneUri = intent.getStringExtra(CallIntentExtras.RINGTONE_URI).orEmpty(),
            answerAudioUri = intent.getStringExtra(CallIntentExtras.ANSWER_AUDIO_URI).orEmpty()
        )

        if (intent.action == SimulatedCallNotifier.ACTION_ANSWER && resetCallState) {
            answerCall()
        } else if (resetCallState) {
            answeredState.value = false
            connectedAtState.longValue = 0L
            useFrontCameraState.value = true
            cameraEnabledState.value = true
            mutedState.value = false
            ignoredState.value = false
            blurEnabledState.value = false
            selfViewPrimaryState.value = false
            setSpeakerEnabled(false)
            ExperimentLog.add(this, "微信来电页面已显示")
        }
    }

    private fun answerCall() {
        if (answeredState.value) return
        answeredState.value = true
        connectedAtState.longValue = System.currentTimeMillis()
        SimulatedCallNotifier.cancel(this)
        ExperimentLog.add(this, "用户已接听微信通话")
        // Commit the connected UI before audio routing/file preparation. Both operations can
        // block briefly on vendor builds and previously made the answer button look unresponsive.
        window.decorView.post {
            if (!audioPlayer.playAnswerAudio(configState.value.answerAudioUri)) {
                ExperimentLog.add(this, "接听后音频无法播放")
            }
        }
        if (configState.value.mode == CallMode.WECHAT_VIDEO) {
            window.decorView.postDelayed({ setSpeakerEnabled(true) }, 120)
        }
    }

    private fun ignoreIncoming() {
        if (answeredState.value || ignoredState.value) return
        ignoredState.value = true
        SimulatedCallNotifier.cancel(this)
        ExperimentLog.add(this, "用户忽略微信来电，已停止铃声和震动")
    }

    private fun ensureCameraPermission() {
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        cameraPermissionState.value = granted
        if (configState.value.mode == CallMode.WECHAT_VIDEO && !granted) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
        }
    }

    private fun endCall(log: String) {
        // Hide the surface immediately. Activity task-removal animations caused the old call page
        // to visibly slide down after the user had already tapped hang up.
        window.decorView.alpha = 0f
        SimulatedCallNotifier.cancel(this)
        ExperimentLog.add(this, log)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        }
        finish()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    private fun setSpeakerEnabled(enabled: Boolean) {
        val audioManager = getSystemService(AudioManager::class.java)
        val applied = runCatching {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (enabled) {
                    val speaker = audioManager.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                    }
                    speaker != null && audioManager.setCommunicationDevice(speaker)
                } else {
                    audioManager.clearCommunicationDevice()
                    true
                }
            } else {
                @Suppress("DEPRECATION")
                audioManager.isSpeakerphoneOn = enabled
                true
            }
        }.getOrDefault(false)
        if (applied) {
            speakerEnabledState.value = enabled
            ExperimentLog.add(this, if (enabled) "已切换到扬声器" else "已切换到听筒/默认输出")
        } else {
            ExperimentLog.add(this, "音频输出切换失败")
        }
    }

    private fun resetAudioRoute() {
        runCatching {
            val audioManager = getSystemService(AudioManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                audioManager.isSpeakerphoneOn = false
            }
            audioManager.mode = AudioManager.MODE_NORMAL
        }
        speakerEnabledState.value = false
    }

    companion object {
        private const val STATE_ANSWERED = "state_answered"
        private const val STATE_CONNECTED_AT = "state_connected_at"
        private const val STATE_CAMERA_ENABLED = "state_camera_enabled"
        private const val STATE_MUTED = "state_muted"
        private const val STATE_SPEAKER = "state_speaker"
        private const val STATE_IGNORED = "state_ignored"
        private const val STATE_BLUR_ENABLED = "state_blur_enabled"
        private const val STATE_SELF_VIEW_PRIMARY = "state_self_view_primary"
        private const val CAMERA_PERMISSION_REQUEST = 42
    }
}

@Composable
private fun SimulatedCallScreen(
    config: CallConfiguration,
    uiProfile: AndroidCallUiProfile,
    answered: Boolean,
    connectedAtMillis: Long,
    cameraPermissionGranted: Boolean,
    cameraEnabled: Boolean,
    useFrontCamera: Boolean,
    muted: Boolean,
    speakerEnabled: Boolean,
    ignored: Boolean,
    blurEnabled: Boolean,
    selfViewPrimary: Boolean,
    onAnswer: () -> Unit,
    onDecline: () -> Unit,
    onHangUp: () -> Unit,
    onIgnore: () -> Unit,
    onFlipCamera: () -> Unit,
    onToggleCamera: () -> Unit,
    onToggleBlur: () -> Unit,
    onToggleSelfView: () -> Unit,
    onToggleMute: () -> Unit,
    onToggleSpeaker: () -> Unit
) {
    val isVideo = config.mode == CallMode.WECHAT_VIDEO
    Surface(modifier = Modifier.fillMaxSize(), color = Color(0xFF121212)) {
        Box(modifier = Modifier.fillMaxSize()) {
            CallMeAvatarBackdrop(
                name = config.callerName,
                avatarUri = config.avatarUri,
                modifier = Modifier.fillMaxSize()
            )

            // The camera surface stays edge-to-edge. The selected device-family profile adjusts
            // the PIP geometry for different status bars and display proportions.
            if (isVideo && cameraPermissionGranted && cameraEnabled) {
                val cameraModifier = if (answered && selfViewPrimary) {
                    Modifier
                        .align(Alignment.TopEnd)
                        .statusBarsPadding()
                        .padding(top = uiProfile.videoPipTopDp.dp, end = 16.dp)
                        .size(
                            width = uiProfile.videoPipWidthDp.dp,
                            height = uiProfile.videoPipHeightDp.dp
                        )
                        .clip(RoundedCornerShape(10.dp))
                        .clickable(onClick = onToggleSelfView)
                } else {
                    Modifier.fillMaxSize()
                }
                key(useFrontCamera) {
                    CameraPreview(
                        modifier = cameraModifier.blur(if (blurEnabled) 14.dp else 0.dp),
                        lensFacing = if (useFrontCamera) {
                            CameraCharacteristics.LENS_FACING_FRONT
                        } else {
                            CameraCharacteristics.LENS_FACING_BACK
                        }
                    )
                }
                if (answered && !selfViewPrimary) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .statusBarsPadding()
                            .padding(top = uiProfile.videoPipTopDp.dp, end = 16.dp)
                            .size(
                                width = uiProfile.videoPipWidthDp.dp,
                                height = uiProfile.videoPipHeightDp.dp
                            )
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.Black.copy(alpha = 0.70f))
                            .clickable(onClick = onToggleSelfView),
                        contentAlignment = Alignment.Center
                    ) {
                        CallMeSquareAvatar(config.callerName, config.avatarUri, 52)
                    }
                } else if (answered) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CallMeSquareAvatar(config.callerName, config.avatarUri, 92)
                    }
                }
            } else if (isVideo && answered) {
                // Match the iPhone implementation when the local camera is off: the remote
                // avatar remains the primary surface by default, while tapping the PIP swaps to
                // a dark local placeholder and keeps the remote avatar in the PIP.
                if (selfViewPrimary) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color(0xFF171719)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("我", color = Color.White.copy(alpha = 0.72f), fontSize = 52.sp)
                    }
                } else {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CallMeSquareAvatar(config.callerName, config.avatarUri, 92)
                    }
                }
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .statusBarsPadding()
                        .padding(top = uiProfile.videoPipTopDp.dp, end = 16.dp)
                        .size(
                            width = uiProfile.videoPipWidthDp.dp,
                            height = uiProfile.videoPipHeightDp.dp
                        )
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color.Black.copy(alpha = 0.72f))
                        .clickable(onClick = onToggleSelfView),
                    contentAlignment = Alignment.Center
                ) {
                    if (selfViewPrimary) {
                        CallMeSquareAvatar(config.callerName, config.avatarUri, 52)
                    } else {
                        Text("我", color = Color.White.copy(alpha = 0.72f), fontSize = 28.sp)
                    }
                }
            }

            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        listOf(
                            Color.Black.copy(alpha = if (isVideo) 0.22f else 0.30f),
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.78f)
                        )
                    )
                )
            )

            if (answered) {
                ConnectedCallChrome(
                    uiProfile = uiProfile,
                    isVideo = isVideo,
                    callerName = config.callerName,
                    avatarUri = config.avatarUri,
                    connectedAtMillis = connectedAtMillis,
                    muted = muted,
                    speakerEnabled = speakerEnabled,
                    cameraEnabled = cameraEnabled,
                    blurEnabled = blurEnabled,
                    onToggleMute = onToggleMute,
                    onToggleSpeaker = onToggleSpeaker,
                    onToggleCamera = onToggleCamera,
                    onToggleBlur = onToggleBlur,
                    onFlipCamera = onFlipCamera,
                    onHangUp = onHangUp
                )
            } else {
                IncomingCallChrome(
                    uiProfile = uiProfile,
                    isVideo = isVideo,
                    callerName = config.callerName,
                    avatarUri = config.avatarUri,
                    cameraEnabled = cameraEnabled,
                    ignored = ignored,
                    muted = muted,
                    blurEnabled = blurEnabled,
                    onIgnore = onIgnore,
                    onToggleMute = onToggleMute,
                    onToggleCamera = onToggleCamera,
                    onToggleBlur = onToggleBlur,
                    onFlipCamera = onFlipCamera,
                    onDecline = onDecline,
                    onAnswer = onAnswer
                )
            }
        }
    }
}

@Composable
private fun IncomingCallChrome(
    uiProfile: AndroidCallUiProfile,
    isVideo: Boolean,
    callerName: String,
    avatarUri: String,
    cameraEnabled: Boolean,
    ignored: Boolean,
    muted: Boolean,
    blurEnabled: Boolean,
    onIgnore: () -> Unit,
    onToggleMute: () -> Unit,
    onToggleCamera: () -> Unit,
    onToggleBlur: () -> Unit,
    onFlipCamera: () -> Unit,
    onDecline: () -> Unit,
    onAnswer: () -> Unit
) {
    BoxWithConstraints(
        Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()
    ) {
        val canvasHeight = maxHeight

        MiniTopAction(
            glyph = CallGlyph.SwitchView,
            modifier = Modifier.align(Alignment.TopStart).padding(start = 18.dp, top = 16.dp)
        )

        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(
                    top = canvasHeight * if (isVideo) {
                        uiProfile.incomingVideoIdentityFraction
                    } else {
                        uiProfile.incomingVoiceIdentityFraction
                    }
                )
                .padding(horizontal = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CallMeSquareAvatar(callerName, avatarUri, if (isVideo) 76 else 96)
            Spacer(Modifier.height(if (isVideo) 12.dp else 16.dp))
            Text(
                callerName,
                color = Color.White,
                fontSize = if (isVideo) 23.sp else 25.sp,
                fontWeight = FontWeight.Normal,
                textAlign = TextAlign.Center,
                maxLines = 2
            )
        }

        Text(
            if (isVideo) "邀请你视频通话." else "邀请你语音通话.",
            color = Color.White.copy(alpha = 0.48f),
            fontSize = 16.sp,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(
                    top = canvasHeight * if (isVideo) {
                        uiProfile.incomingVideoInviteFraction
                    } else {
                        uiProfile.incomingVoiceInviteFraction
                    }
                )
        )

        if (isVideo) {
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(horizontal = 36.dp)
                    .padding(bottom = 150.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                CallAction("翻转", CallGlyph.Flip, darkFill, onFlipCamera, diameter = uiProfile.videoActionDiameterDp.dp, enabled = cameraEnabled)
                CallAction("模糊背景", CallGlyph.Blur, darkFill, onToggleBlur, diameter = uiProfile.videoActionDiameterDp.dp, enabled = cameraEnabled)
                CallAction(
                    if (cameraEnabled) "摄像头已开" else "摄像头已关",
                    if (cameraEnabled) CallGlyph.Video else CallGlyph.VideoOff,
                    if (cameraEnabled) Color.White else darkFill,
                    onToggleCamera,
                    diameter = uiProfile.videoActionDiameterDp.dp,
                    darkIcon = cameraEnabled
                )
            }
        }

        Row(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 48.dp)
                .padding(bottom = uiProfile.incomingBottomDp.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            CallAction(
                "拒绝",
                CallGlyph.PhoneDown,
                weChatRed,
                onDecline,
                diameter = uiProfile.incomingActionDiameterDp.dp
            )
            CallAction(
                "接听",
                CallGlyph.Phone,
                weChatGreen,
                onAnswer,
                diameter = uiProfile.incomingActionDiameterDp.dp
            )
        }
    }
}

@Composable
private fun ConnectedCallChrome(
    uiProfile: AndroidCallUiProfile,
    isVideo: Boolean,
    callerName: String,
    avatarUri: String,
    connectedAtMillis: Long,
    muted: Boolean,
    speakerEnabled: Boolean,
    cameraEnabled: Boolean,
    blurEnabled: Boolean,
    onToggleMute: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onToggleCamera: () -> Unit,
    onToggleBlur: () -> Unit,
    onFlipCamera: () -> Unit,
    onHangUp: () -> Unit
) {
    BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
        val canvasHeight = maxHeight
        Row(
            modifier = Modifier.align(Alignment.TopCenter).padding(horizontal = if (isVideo) 18.dp else 28.dp, vertical = 18.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (isVideo) {
                TopCallIcon(CallGlyph.SwitchView)
            } else {
                CallGlyphIcon(CallGlyph.SwitchView, Color.White, Modifier.size(27.dp))
            }
            Spacer(Modifier.weight(1f))
            CallDuration(connectedAtMillis)
            Spacer(Modifier.weight(1f))
            if (isVideo) {
                TopCallIcon(CallGlyph.Unlock)
                Spacer(Modifier.width(10.dp))
                TopCallIcon(CallGlyph.PersonAdd)
            } else {
                CallGlyphIcon(CallGlyph.Plus, Color.White, Modifier.size(29.dp))
            }
        }

        if (isVideo) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = uiProfile.videoBottomDp.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    CallAction(if (muted) "麦克风已关" else "麦克风已开", CallGlyph.Mic, if (muted) darkFill else Color.White, onToggleMute, diameter = uiProfile.videoActionDiameterDp.dp, darkIcon = !muted)
                    CallAction(if (speakerEnabled) "扬声器已开" else "扬声器已关", CallGlyph.Speaker, if (speakerEnabled) Color.White else darkFill, onToggleSpeaker, diameter = uiProfile.videoActionDiameterDp.dp, darkIcon = speakerEnabled)
                    CallAction(if (cameraEnabled) "摄像头已开" else "摄像头已关", if (cameraEnabled) CallGlyph.Video else CallGlyph.VideoOff, if (cameraEnabled) Color.White else darkFill, onToggleCamera, diameter = uiProfile.videoActionDiameterDp.dp, darkIcon = cameraEnabled)
                }
                Spacer(Modifier.height(22.dp))
                if (cameraEnabled) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        CallAction("模糊背景", CallGlyph.Blur, darkFill, onToggleBlur, diameter = uiProfile.videoActionDiameterDp.dp)
                        CallAction("挂断", CallGlyph.PhoneDown, weChatRed, onHangUp, diameter = uiProfile.videoActionDiameterDp.dp)
                        CallAction("翻转摄像头", CallGlyph.Flip, darkFill, onFlipCamera, diameter = uiProfile.videoActionDiameterDp.dp)
                    }
                } else {
                    CallAction("挂断", CallGlyph.PhoneDown, weChatRed, onHangUp, diameter = uiProfile.videoActionDiameterDp.dp)
                }
            }

        } else {
            Column(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = canvasHeight * uiProfile.connectedVoiceIdentityFraction)
                    .padding(horizontal = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CallMeSquareAvatar(callerName, avatarUri, 96)
                Spacer(Modifier.height(18.dp))
                Text(
                    callerName,
                    color = Color.White,
                    fontSize = 25.sp,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    modifier = Modifier.padding(horizontal = 28.dp)
                )
            }
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(horizontal = 34.dp)
                    .padding(bottom = uiProfile.voiceBottomDp.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                CallAction(if (muted) "麦克风已关" else "麦克风已开", CallGlyph.Mic, if (muted) darkFill else Color.White, onToggleMute, diameter = uiProfile.voiceActionDiameterDp.dp, darkIcon = !muted)
                CallAction("挂断", CallGlyph.PhoneDown, weChatRed, onHangUp, diameter = uiProfile.voiceActionDiameterDp.dp)
                CallAction(if (speakerEnabled) "扬声器已开" else "扬声器已关", CallGlyph.Speaker, if (speakerEnabled) Color.White else darkFill, onToggleSpeaker, diameter = uiProfile.voiceActionDiameterDp.dp, darkIcon = speakerEnabled)
            }
        }
    }
}

@Composable
private fun MiniTopAction(glyph: CallGlyph, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.size(48.dp).background(Color.Black.copy(alpha = 0.42f), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        CallGlyphIcon(glyph, Color.White, Modifier.size(24.dp))
    }
}

@Composable
private fun TopCallIcon(glyph: CallGlyph) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .background(Color.Black.copy(alpha = 0.42f), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        CallGlyphIcon(glyph, Color.White, Modifier.size(23.dp))
    }
}

@Composable
private fun CallDuration(connectedAtMillis: Long) {
    var nowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            nowMillis = System.currentTimeMillis()
        }
    }
    val seconds = ((nowMillis - connectedAtMillis).coerceAtLeast(0L) / 1_000L).toInt()
    Text(
        "%02d:%02d".format(seconds / 60, seconds % 60),
        color = Color.White.copy(alpha = 0.75f),
        fontSize = 20.sp,
        textAlign = TextAlign.Center
    )
}

@Composable
private fun CallAction(
    label: String,
    glyph: CallGlyph,
    color: Color,
    onClick: () -> Unit,
    diameter: Dp = 76.dp,
    enabled: Boolean = true,
    darkIcon: Boolean = false
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            modifier = Modifier
                .size(diameter)
                .alpha(if (enabled) 1f else 0.30f)
                .clip(CircleShape)
                .background(color)
                .clickable(enabled = enabled, onClick = onClick),
            contentAlignment = Alignment.Center
        ) {
            CallGlyphIcon(
                glyph = glyph,
                tint = if (darkIcon) Color.Black else Color.White,
                modifier = Modifier.size(diameter * 0.42f)
            )
        }
        Text(
            label,
            color = Color.White.copy(alpha = if (enabled) 0.88f else 0.32f),
            fontSize = if (diameter <= 62.dp) 11.sp else 13.sp,
            maxLines = 1
        )
    }
}

private val weChatRed = Color(0xFFFA5151)
private val weChatGreen = Color(0xFF07C160)
private val darkFill = Color.Black.copy(alpha = 0.44f)

private enum class CallGlyph {
    Phone, PhoneDown, Mic, Speaker, Video, VideoOff, Flip, Blur, More, SwitchView, Plus,
    Unlock, PersonAdd, MutedBell
}

@Composable
private fun CallGlyphIcon(glyph: CallGlyph, tint: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val stroke = androidx.compose.ui.graphics.drawscope.Stroke(
            width = w * 0.095f,
            cap = androidx.compose.ui.graphics.StrokeCap.Round,
            join = androidx.compose.ui.graphics.StrokeJoin.Round
        )
        when (glyph) {
            CallGlyph.Phone -> {
                val path = androidx.compose.ui.graphics.Path().apply {
                    moveTo(w * 0.27f, h * 0.17f)
                    cubicTo(w * 0.12f, h * 0.34f, w * 0.37f, h * 0.69f, w * 0.65f, h * 0.82f)
                    cubicTo(w * 0.77f, h * 0.88f, w * 0.88f, h * 0.76f, w * 0.81f, h * 0.64f)
                }
                drawPath(path, tint, style = stroke)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.27f, h * 0.17f), androidx.compose.ui.geometry.Offset(w * 0.39f, h * 0.27f), strokeWidth = w * 0.16f, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.81f, h * 0.64f), androidx.compose.ui.geometry.Offset(w * 0.70f, h * 0.55f), strokeWidth = w * 0.16f, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            CallGlyph.PhoneDown -> {
                val path = androidx.compose.ui.graphics.Path().apply {
                    moveTo(w * 0.17f, h * 0.64f)
                    cubicTo(w * 0.27f, h * 0.35f, w * 0.72f, h * 0.35f, w * 0.83f, h * 0.64f)
                }
                drawPath(path, tint, style = stroke)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.17f, h * 0.64f), androidx.compose.ui.geometry.Offset(w * 0.28f, h * 0.70f), strokeWidth = w * 0.16f, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.83f, h * 0.64f), androidx.compose.ui.geometry.Offset(w * 0.72f, h * 0.70f), strokeWidth = w * 0.16f, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            CallGlyph.Mic -> {
                drawRoundRect(tint, topLeft = androidx.compose.ui.geometry.Offset(w * 0.36f, h * 0.10f), size = androidx.compose.ui.geometry.Size(w * 0.28f, h * 0.48f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.14f))
                drawArc(tint, 0f, 180f, false, topLeft = androidx.compose.ui.geometry.Offset(w * 0.22f, h * 0.28f), size = androidx.compose.ui.geometry.Size(w * 0.56f, h * 0.45f), style = stroke)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.50f, h * 0.70f), androidx.compose.ui.geometry.Offset(w * 0.50f, h * 0.88f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            CallGlyph.Speaker -> {
                val path = androidx.compose.ui.graphics.Path().apply {
                    moveTo(w * 0.12f, h * 0.40f); lineTo(w * 0.34f, h * 0.40f); lineTo(w * 0.57f, h * 0.20f); lineTo(w * 0.57f, h * 0.80f); lineTo(w * 0.34f, h * 0.60f); lineTo(w * 0.12f, h * 0.60f); close()
                }
                drawPath(path, tint)
                drawArc(tint, -55f, 110f, false, topLeft = androidx.compose.ui.geometry.Offset(w * 0.48f, h * 0.26f), size = androidx.compose.ui.geometry.Size(w * 0.38f, h * 0.48f), style = stroke)
            }
            CallGlyph.Video -> {
                drawRoundRect(tint, topLeft = androidx.compose.ui.geometry.Offset(w * 0.10f, h * 0.25f), size = androidx.compose.ui.geometry.Size(w * 0.58f, h * 0.50f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.08f))
                val path = androidx.compose.ui.graphics.Path().apply { moveTo(w * 0.72f, h * 0.38f); lineTo(w * 0.92f, h * 0.26f); lineTo(w * 0.92f, h * 0.74f); lineTo(w * 0.72f, h * 0.62f); close() }
                drawPath(path, tint)
            }
            CallGlyph.VideoOff -> {
                drawRoundRect(tint, topLeft = androidx.compose.ui.geometry.Offset(w * 0.10f, h * 0.25f), size = androidx.compose.ui.geometry.Size(w * 0.58f, h * 0.50f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.08f))
                val path = androidx.compose.ui.graphics.Path().apply { moveTo(w * 0.72f, h * 0.38f); lineTo(w * 0.92f, h * 0.26f); lineTo(w * 0.92f, h * 0.74f); lineTo(w * 0.72f, h * 0.62f); close() }
                drawPath(path, tint)
                drawLine(Color(0xFF151515), androidx.compose.ui.geometry.Offset(w * 0.08f, h * 0.08f), androidx.compose.ui.geometry.Offset(w * 0.92f, h * 0.92f), strokeWidth = w * 0.13f, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            CallGlyph.Flip -> {
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.17f, h * 0.34f), androidx.compose.ui.geometry.Offset(w * 0.80f, h * 0.34f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.80f, h * 0.34f), androidx.compose.ui.geometry.Offset(w * 0.67f, h * 0.22f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.80f, h * 0.34f), androidx.compose.ui.geometry.Offset(w * 0.67f, h * 0.46f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.83f, h * 0.66f), androidx.compose.ui.geometry.Offset(w * 0.20f, h * 0.66f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.20f, h * 0.66f), androidx.compose.ui.geometry.Offset(w * 0.33f, h * 0.54f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.20f, h * 0.66f), androidx.compose.ui.geometry.Offset(w * 0.33f, h * 0.78f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            CallGlyph.Blur -> {
                drawRoundRect(tint, topLeft = androidx.compose.ui.geometry.Offset(w * 0.12f, h * 0.12f), size = androidx.compose.ui.geometry.Size(w * 0.76f, h * 0.76f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.10f), style = stroke)
                repeat(3) { index -> drawLine(tint, androidx.compose.ui.geometry.Offset(w * (0.27f + index * 0.18f), h * 0.27f), androidx.compose.ui.geometry.Offset(w * (0.18f + index * 0.18f), h * 0.72f), strokeWidth = w * 0.055f, cap = androidx.compose.ui.graphics.StrokeCap.Round) }
            }
            CallGlyph.More -> repeat(3) { drawCircle(tint, radius = w * 0.09f, center = androidx.compose.ui.geometry.Offset(w * (0.25f + it * 0.25f), h * 0.50f)) }
            CallGlyph.SwitchView -> {
                drawRoundRect(tint, topLeft = androidx.compose.ui.geometry.Offset(w * 0.08f, h * 0.12f), size = androidx.compose.ui.geometry.Size(w * 0.55f, h * 0.55f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.06f), style = stroke)
                drawRoundRect(tint, topLeft = androidx.compose.ui.geometry.Offset(w * 0.38f, h * 0.40f), size = androidx.compose.ui.geometry.Size(w * 0.54f, h * 0.48f), cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.06f), style = stroke)
            }
            CallGlyph.Plus -> {
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.5f, h * 0.15f), androidx.compose.ui.geometry.Offset(w * 0.5f, h * 0.85f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.15f, h * 0.5f), androidx.compose.ui.geometry.Offset(w * 0.85f, h * 0.5f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            CallGlyph.Unlock -> {
                drawRoundRect(
                    tint,
                    topLeft = androidx.compose.ui.geometry.Offset(w * 0.22f, h * 0.46f),
                    size = androidx.compose.ui.geometry.Size(w * 0.56f, h * 0.40f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.08f),
                    style = stroke
                )
                drawArc(
                    tint,
                    startAngle = 180f,
                    sweepAngle = -210f,
                    useCenter = false,
                    topLeft = androidx.compose.ui.geometry.Offset(w * 0.34f, h * 0.11f),
                    size = androidx.compose.ui.geometry.Size(w * 0.45f, h * 0.52f),
                    style = stroke
                )
            }
            CallGlyph.PersonAdd -> {
                drawCircle(tint, radius = w * 0.17f, center = androidx.compose.ui.geometry.Offset(w * 0.40f, h * 0.28f), style = stroke)
                drawArc(
                    tint,
                    startAngle = 200f,
                    sweepAngle = 140f,
                    useCenter = false,
                    topLeft = androidx.compose.ui.geometry.Offset(w * 0.16f, h * 0.43f),
                    size = androidx.compose.ui.geometry.Size(w * 0.48f, h * 0.42f),
                    style = stroke
                )
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.76f, h * 0.43f), androidx.compose.ui.geometry.Offset(w * 0.76f, h * 0.79f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.58f, h * 0.61f), androidx.compose.ui.geometry.Offset(w * 0.94f, h * 0.61f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            CallGlyph.MutedBell -> {
                drawArc(tint, 190f, 160f, false, topLeft = androidx.compose.ui.geometry.Offset(w * 0.26f, h * 0.18f), size = androidx.compose.ui.geometry.Size(w * 0.48f, h * 0.56f), style = stroke)
                drawLine(tint, androidx.compose.ui.geometry.Offset(w * 0.13f, h * 0.13f), androidx.compose.ui.geometry.Offset(w * 0.87f, h * 0.87f), strokeWidth = stroke.width, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
        }
    }
}
