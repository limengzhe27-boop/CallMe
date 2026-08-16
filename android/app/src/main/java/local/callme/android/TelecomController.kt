package local.callme.android

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

class TelecomController(private val context: Context) {
    private val telecomManager = context.getSystemService(TelecomManager::class.java)

    val accountHandle: PhoneAccountHandle
        get() = PhoneAccountHandle(
            ComponentName(context, CallMeConnectionService::class.java),
            ACCOUNT_ID
        )

    fun registerPhoneAccount(): Result<Unit> = runCatching {
        val account = PhoneAccount.Builder(accountHandle, ACCOUNT_LABEL)
            .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
            .addSupportedUriScheme(PhoneAccount.SCHEME_TEL)
            .build()
        telecomManager.registerPhoneAccount(account)
    }

    fun isAccountEnabled(): Boolean = runCatching {
        // Some Xiaomi/HyperOS builds hide even the app's own account from getPhoneAccount()
        // although Telecom's system state shows it enabled. A successful registration is
        // therefore the only usable in-app precondition; addNewIncomingCall is authoritative.
        registerPhoneAccount().getOrThrow()
        true
    }.getOrDefault(false)

    fun reportIncomingCall(
        callerName: String = DEFAULT_CALLER_NAME,
        callerNumber: String = DEFAULT_CALLER_NUMBER,
        answerAudioUri: String = ""
    ): Result<Unit> = runCatching {
        require(isAccountEnabled()) { "系统中的 CallMe 通话账户尚未注册" }

        val callDetails = Bundle().apply {
            putString(EXTRA_CALLER_NAME, callerName)
            putString(EXTRA_CALLER_NUMBER, callerNumber)
            putString(EXTRA_ANSWER_AUDIO_URI, answerAudioUri)
        }
        val extras = Bundle().apply {
            putParcelable(
                TelecomManager.EXTRA_INCOMING_CALL_ADDRESS,
                Uri.fromParts(PhoneAccount.SCHEME_TEL, callerNumber, null)
            )
            putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, callDetails)
        }

        // This only reports an incoming call. The app never invokes placeCall().
        telecomManager.addNewIncomingCall(accountHandle, extras)
    }

    companion object {
        const val ACCOUNT_ID = "callme_mvp_provider"
        const val ACCOUNT_LABEL = "CallMe"
        const val DEFAULT_CALLER_NAME = "老板"
        const val DEFAULT_CALLER_NUMBER = "13800138000"
        const val EXTRA_CALLER_NAME = "local.callme.extra.CALLER_NAME"
        const val EXTRA_CALLER_NUMBER = "local.callme.extra.CALLER_NUMBER"
        const val EXTRA_ANSWER_AUDIO_URI = "local.callme.extra.ANSWER_AUDIO_URI"
    }
}
