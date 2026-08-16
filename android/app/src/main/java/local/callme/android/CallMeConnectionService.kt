package local.callme.android

import android.content.Context
import android.net.Uri
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

class CallMeConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest
    ): Connection {
        val callDetails = request.extras
            ?.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS)
        val callerNumber = request.address?.schemeSpecificPart
            ?: callDetails?.getString(TelecomController.EXTRA_CALLER_NUMBER)
            ?: TelecomController.DEFAULT_CALLER_NUMBER
        val callerName = callDetails?.getString(TelecomController.EXTRA_CALLER_NAME)
            ?.takeIf { it.isNotBlank() }
            ?: TelecomController.DEFAULT_CALLER_NAME
        val answerAudioUri = callDetails
            ?.getString(TelecomController.EXTRA_ANSWER_AUDIO_URI)
            .orEmpty()

        ExperimentLog.add(this, "ConnectionService 收到系统来电请求：$callerName")
        return CallMeConnection(this, callerName, callerNumber, answerAudioUri)
    }
}

private class CallMeConnection(
    private val context: Context,
    callerName: String,
    callerNumber: String,
    private val answerAudioUri: String
) : Connection() {
    private val audioPlayer = AudioPlayer(context)
    init {
        setAddress(
            Uri.fromParts(PhoneAccount.SCHEME_TEL, callerNumber, null),
            TelecomManager.PRESENTATION_ALLOWED
        )
        setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
        setConnectionCapabilities(CAPABILITY_MUTE)
        setAudioModeIsVoip(true)
        setInitializing()
        setRinging()
        ExperimentLog.add(context, "通话状态已设为响铃")
    }

    override fun onAnswer() {
        setActive()
        if (!audioPlayer.playAnswerAudio(answerAudioUri)) {
            ExperimentLog.add(context, "接听后音频无法播放")
        }
        ExperimentLog.add(context, "用户已接听，进入通话状态")
    }

    override fun onAnswer(videoState: Int) {
        onAnswer()
    }

    override fun onReject() {
        finish(DisconnectCause.REJECTED, "用户已拒绝")
    }

    override fun onDisconnect() {
        finish(DisconnectCause.LOCAL, "用户已挂断")
    }

    override fun onAbort() {
        finish(DisconnectCause.CANCELED, "系统已取消来电")
    }

    private fun finish(cause: Int, message: String) {
        audioPlayer.stop()
        setDisconnected(DisconnectCause(cause))
        ExperimentLog.add(context, message)
        destroy()
    }
}
