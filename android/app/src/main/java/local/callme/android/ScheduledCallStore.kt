package local.callme.android

import android.content.Context
import androidx.core.content.edit

data class ScheduledCall(
    val triggerAtMillis: Long,
    val mode: CallMode,
    val callerName: String,
    val callerNumber: String,
    val avatarUri: String = "",
    val delayMillis: Long,
    val ringtoneUri: String,
    val answerAudioUri: String
) {
    fun deviationMillis(actualTriggerAtMillis: Long): Long =
        actualTriggerAtMillis - triggerAtMillis

    fun isExpired(nowMillis: Long, graceMillis: Long = EXPIRY_GRACE_MILLIS): Boolean =
        nowMillis > triggerAtMillis + graceMillis

    fun toConfiguration(): CallConfiguration = CallConfiguration(
        mode = mode,
        callerName = callerName,
        callerNumber = callerNumber,
        avatarUri = avatarUri,
        delayMillis = delayMillis,
        ringtoneUri = ringtoneUri,
        answerAudioUri = answerAudioUri
    )

    companion object {
        const val EXPIRY_GRACE_MILLIS = 120_000L
    }
}

object ScheduledCallStore {
    private const val PREFS = "callme_scheduled_call"
    private const val KEY_TRIGGER_AT = "trigger_at"
    private const val KEY_MODE = "mode"
    private const val KEY_CALLER_NAME = "caller_name"
    private const val KEY_CALLER_NUMBER = "caller_number"
    private const val KEY_DELAY = "delay"
    private const val KEY_AVATAR_URI = "avatar_uri"
    private const val KEY_RINGTONE_URI = "ringtone_uri"
    private const val KEY_ANSWER_AUDIO_URI = "answer_audio_uri"

    fun load(context: Context, nowMillis: Long = System.currentTimeMillis()): ScheduledCall? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val triggerAt = prefs.getLong(KEY_TRIGGER_AT, 0L)
        if (triggerAt <= 0L) return null
        val call = ScheduledCall(
            triggerAtMillis = triggerAt,
            mode = CallMode.fromStorage(prefs.getString(KEY_MODE, null)),
            callerName = prefs.getString(KEY_CALLER_NAME, TelecomController.DEFAULT_CALLER_NAME)
                ?: TelecomController.DEFAULT_CALLER_NAME,
            callerNumber = prefs.getString(KEY_CALLER_NUMBER, TelecomController.DEFAULT_CALLER_NUMBER)
                ?: TelecomController.DEFAULT_CALLER_NUMBER,
            avatarUri = prefs.getString(KEY_AVATAR_URI, "").orEmpty(),
            delayMillis = prefs.getLong(KEY_DELAY, 0L),
            ringtoneUri = prefs.getString(KEY_RINGTONE_URI, "").orEmpty(),
            answerAudioUri = prefs.getString(KEY_ANSWER_AUDIO_URI, "").orEmpty()
        )
        if (call.isExpired(nowMillis)) {
            clear(context)
            return null
        }
        return call
    }

    fun save(context: Context, call: ScheduledCall) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
            putLong(KEY_TRIGGER_AT, call.triggerAtMillis)
            putString(KEY_MODE, call.mode.name)
            putString(KEY_CALLER_NAME, call.callerName)
            putString(KEY_CALLER_NUMBER, call.callerNumber)
            putString(KEY_AVATAR_URI, call.avatarUri)
            putLong(KEY_DELAY, call.delayMillis)
            putString(KEY_RINGTONE_URI, call.ringtoneUri)
            putString(KEY_ANSWER_AUDIO_URI, call.answerAudioUri)
        }
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit { clear() }
    }
}
