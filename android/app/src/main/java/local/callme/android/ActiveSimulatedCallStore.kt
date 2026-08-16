package local.callme.android

import android.content.Context
import androidx.core.content.edit

/** Persists only an unanswered custom incoming call so the launcher can recover its UI. */
object ActiveSimulatedCallStore {
    private const val PREFS = "callme_active_incoming_call"
    private const val KEY_ACTIVE = "active"
    private const val KEY_STARTED_AT = "started_at"
    private const val KEY_MODE = "mode"
    private const val KEY_CALLER_NAME = "caller_name"
    private const val KEY_CALLER_NUMBER = "caller_number"
    private const val KEY_AVATAR_URI = "avatar_uri"
    private const val KEY_RINGTONE_URI = "ringtone_uri"
    private const val KEY_ANSWER_AUDIO_URI = "answer_audio_uri"
    private const val MAX_RINGING_AGE_MILLIS = 90_000L

    fun save(context: Context, config: CallConfiguration) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
            putBoolean(KEY_ACTIVE, true)
            putLong(KEY_STARTED_AT, System.currentTimeMillis())
            putString(KEY_MODE, config.mode.name)
            putString(KEY_CALLER_NAME, config.callerName)
            putString(KEY_CALLER_NUMBER, config.callerNumber)
            putString(KEY_AVATAR_URI, config.avatarUri)
            putString(KEY_RINGTONE_URI, config.ringtoneUri)
            putString(KEY_ANSWER_AUDIO_URI, config.answerAudioUri)
        }
    }

    fun load(context: Context): CallConfiguration? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ACTIVE, false)) return null
        val startedAt = prefs.getLong(KEY_STARTED_AT, 0L)
        if (startedAt <= 0L || System.currentTimeMillis() - startedAt > MAX_RINGING_AGE_MILLIS) {
            clear(context)
            return null
        }
        return CallConfiguration(
            mode = CallMode.fromStorage(prefs.getString(KEY_MODE, null)),
            callerName = prefs.getString(KEY_CALLER_NAME, TelecomController.DEFAULT_CALLER_NAME)
                ?: TelecomController.DEFAULT_CALLER_NAME,
            callerNumber = prefs.getString(KEY_CALLER_NUMBER, TelecomController.DEFAULT_CALLER_NUMBER)
                ?: TelecomController.DEFAULT_CALLER_NUMBER,
            avatarUri = prefs.getString(KEY_AVATAR_URI, "").orEmpty(),
            ringtoneUri = prefs.getString(KEY_RINGTONE_URI, "").orEmpty(),
            answerAudioUri = prefs.getString(KEY_ANSWER_AUDIO_URI, "").orEmpty()
        )
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit { clear() }
    }
}
