package local.callme.android

import android.content.Context
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

enum class CallMode(val label: String) {
    SYSTEM_PHONE("手机来电"),
    WECHAT_VOICE("微信语音"),
    WECHAT_VIDEO("微信视频");

    val usesSystemPhoneUi: Boolean
        get() = this == SYSTEM_PHONE

    companion object {
        fun fromStorage(value: String?): CallMode = entries.firstOrNull { it.name == value }
            ?: SYSTEM_PHONE
    }
}

enum class BuiltInRingtone(val label: String, private val resourceName: String?) {
    SYSTEM("系统默认", null),
    WECHAT_CLASSIC("微信经典", "wechat_classic"),
    CLASSIC_DIGITAL("经典数字", "chat_classic"),
    CRYSTAL("清脆旋律", "chat_crystal"),
    MINIMAL("极简轻响", "chat_minimal");

    fun uri(context: Context): String = resourceName?.let {
        "android.resource://${context.packageName}/raw/$it"
    }.orEmpty()

    companion object {
        fun choices(mode: CallMode): List<BuiltInRingtone> = if (mode.usesSystemPhoneUi) {
            listOf(SYSTEM)
        } else {
            listOf(WECHAT_CLASSIC, CLASSIC_DIGITAL, CRYSTAL, MINIMAL)
        }

        fun matching(context: Context, uri: String): BuiltInRingtone? = entries.firstOrNull {
            it.uri(context) == uri
        }

        fun defaultFor(context: Context, mode: CallMode): Pair<String, String> =
            if (mode.usesSystemPhoneUi) {
                SYSTEM.uri(context) to SYSTEM.label
            } else {
                WECHAT_CLASSIC.uri(context) to WECHAT_CLASSIC.label
            }
    }
}

fun CallConfiguration.withModeDefaults(context: Context, newMode: CallMode): CallConfiguration {
    if (newMode == mode) return this
    val (defaultUri, defaultName) = BuiltInRingtone.defaultFor(context, newMode)
    return copy(mode = newMode, ringtoneUri = defaultUri, ringtoneName = defaultName)
}

data class CallConfiguration(
    val mode: CallMode = CallMode.SYSTEM_PHONE,
    val callerName: String = TelecomController.DEFAULT_CALLER_NAME,
    val callerNumber: String = TelecomController.DEFAULT_CALLER_NUMBER,
    val avatarUri: String = "",
    val delayMillis: Long = 10_000L,
    val ringtoneUri: String = "",
    val ringtoneName: String = "系统默认铃声",
    val answerAudioUri: String = "",
    val answerAudioName: String = "无（静音）"
)

data class CallTemplate(
    val id: String = UUID.randomUUID().toString(),
    val callerName: String,
    val callerNumber: String,
    val avatarUri: String = "",
    val mode: CallMode,
    val delayMillis: Long,
    val ringtoneUri: String,
    val ringtoneName: String,
    val answerAudioUri: String,
    val answerAudioName: String,
    val updatedAtMillis: Long = System.currentTimeMillis()
) {
    fun toConfiguration(): CallConfiguration = CallConfiguration(
        mode = mode,
        callerName = callerName,
        callerNumber = callerNumber,
        avatarUri = avatarUri,
        delayMillis = delayMillis,
        ringtoneUri = ringtoneUri,
        ringtoneName = ringtoneName,
        answerAudioUri = answerAudioUri,
        answerAudioName = answerAudioName
    )

    companion object {
        fun fromConfiguration(config: CallConfiguration, existingId: String? = null) = CallTemplate(
            id = existingId ?: UUID.randomUUID().toString(),
            callerName = config.callerName,
            callerNumber = config.callerNumber,
            avatarUri = config.avatarUri,
            mode = config.mode,
            delayMillis = config.delayMillis,
            ringtoneUri = config.ringtoneUri,
            ringtoneName = config.ringtoneName,
            answerAudioUri = config.answerAudioUri,
            answerAudioName = config.answerAudioName
        )
    }
}

object CallTemplateStore {
    private const val PREFS = "callme_templates"
    private const val KEY_TEMPLATES = "templates"
    private const val MAX_TEMPLATES = 12

    fun load(context: Context): List<CallTemplate> = runCatching {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_TEMPLATES, "[]") ?: "[]"
        val array = JSONArray(raw)
        buildList {
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                add(
                    CallTemplate(
                        id = item.getString("id"),
                        callerName = item.getString("callerName"),
                        callerNumber = item.getString("callerNumber"),
                        avatarUri = item.optString("avatarUri"),
                        mode = CallMode.fromStorage(item.optString("mode")),
                        delayMillis = item.getLong("delayMillis"),
                        ringtoneUri = item.optString("ringtoneUri"),
                        ringtoneName = item.optString("ringtoneName", "系统默认铃声"),
                        answerAudioUri = item.optString("answerAudioUri"),
                        answerAudioName = item.optString("answerAudioName", "无（静音）"),
                        updatedAtMillis = item.optLong("updatedAtMillis", 0L)
                    )
                )
            }
        }.sortedByDescending(CallTemplate::updatedAtMillis)
    }.getOrDefault(emptyList())

    fun save(context: Context, templates: List<CallTemplate>) {
        val array = JSONArray()
        templates.take(MAX_TEMPLATES).forEach { template ->
            array.put(
                JSONObject()
                    .put("id", template.id)
                    .put("callerName", template.callerName)
                    .put("callerNumber", template.callerNumber)
                    .put("avatarUri", template.avatarUri)
                    .put("mode", template.mode.name)
                    .put("delayMillis", template.delayMillis)
                    .put("ringtoneUri", template.ringtoneUri)
                    .put("ringtoneName", template.ringtoneName)
                    .put("answerAudioUri", template.answerAudioUri)
                    .put("answerAudioName", template.answerAudioName)
                    .put("updatedAtMillis", template.updatedAtMillis)
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit { putString(KEY_TEMPLATES, array.toString()) }
    }
}

object CallSettingsStore {
    private const val PREFS = "callme_settings"
    private const val KEY_MODE = "mode"
    private const val KEY_DELAY = "delay"
    private const val KEY_RINGTONE_URI = "ringtone_uri"
    private const val KEY_RINGTONE_NAME = "ringtone_name"
    private const val KEY_ANSWER_URI = "answer_uri"
    private const val KEY_ANSWER_NAME = "answer_name"
    private const val KEY_AVATAR_URI = "avatar_uri"

    fun load(context: Context): CallConfiguration {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val mode = CallMode.fromStorage(prefs.getString(KEY_MODE, null))
        val storedRingtoneUri = prefs.getString(KEY_RINGTONE_URI, "").orEmpty()
        val hasStoredRingtone = prefs.contains(KEY_RINGTONE_URI)
        val defaultRingtone = BuiltInRingtone.defaultFor(context, mode)
        return CallConfiguration(
            mode = mode,
            callerName = prefs.getString(KEY_CALLER_NAME, TelecomController.DEFAULT_CALLER_NAME)
                ?: TelecomController.DEFAULT_CALLER_NAME,
            callerNumber = prefs.getString(KEY_CALLER_NUMBER, TelecomController.DEFAULT_CALLER_NUMBER)
                ?: TelecomController.DEFAULT_CALLER_NUMBER,
            avatarUri = prefs.getString(KEY_AVATAR_URI, "").orEmpty(),
            delayMillis = prefs.getLong(KEY_DELAY, 10_000L),
            ringtoneUri = if (!mode.usesSystemPhoneUi && (!hasStoredRingtone || storedRingtoneUri.isBlank())) {
                defaultRingtone.first
            } else {
                storedRingtoneUri
            },
            ringtoneName = if (!mode.usesSystemPhoneUi && (!hasStoredRingtone || storedRingtoneUri.isBlank())) {
                defaultRingtone.second
            } else {
                prefs.getString(KEY_RINGTONE_NAME, "系统默认") ?: "系统默认"
            },
            answerAudioUri = prefs.getString(KEY_ANSWER_URI, "").orEmpty(),
            answerAudioName = prefs.getString(KEY_ANSWER_NAME, "无（静音）")
                ?: "无（静音）"
        )
    }

    fun save(context: Context, config: CallConfiguration) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit {
                putString(KEY_MODE, config.mode.name)
                putString(KEY_CALLER_NAME, config.callerName)
                putString(KEY_CALLER_NUMBER, config.callerNumber)
                putString(KEY_AVATAR_URI, config.avatarUri)
                putLong(KEY_DELAY, config.delayMillis)
                putString(KEY_RINGTONE_URI, config.ringtoneUri)
                putString(KEY_RINGTONE_NAME, config.ringtoneName)
                putString(KEY_ANSWER_URI, config.answerAudioUri)
                putString(KEY_ANSWER_NAME, config.answerAudioName)
            }
    }

    private const val KEY_CALLER_NAME = "caller_name"
    private const val KEY_CALLER_NUMBER = "caller_number"
}

object CallIntentExtras {
    const val MODE = "local.callme.extra.MODE"
    const val CALLER_NAME = "local.callme.extra.CALLER_NAME"
    const val CALLER_NUMBER = "local.callme.extra.CALLER_NUMBER"
    const val AVATAR_URI = "local.callme.extra.AVATAR_URI"
    const val RINGTONE_URI = "local.callme.extra.RINGTONE_URI"
    const val ANSWER_AUDIO_URI = "local.callme.extra.ANSWER_AUDIO_URI"
    const val PLANNED_TRIGGER_AT = "local.callme.extra.PLANNED_TRIGGER_AT"
}

object CallInputValidator {
    private val emergencyNumbers = setOf("110", "112", "119", "120", "911", "999")

    fun callerNameError(name: String): String? = when {
        name.trim().isEmpty() -> "来电人姓名不能为空"
        name.trim().length > 30 -> "来电人姓名最多 30 个字符"
        else -> null
    }

    fun callerNumberError(number: String): String? {
        val normalized = number.filter(Char::isDigit)
        return when {
            normalized.isEmpty() -> "号码不能为空"
            normalized in emergencyNumbers -> "请勿使用紧急号码"
            normalized.length > 20 -> "号码最多 20 位"
            else -> null
        }
    }

    fun customDelayMillis(value: String, unitInMinutes: Boolean): Long? {
        val amount = value.trim().toLongOrNull() ?: return null
        if (amount <= 0L) return null
        val multiplier = if (unitInMinutes) 60_000L else 1_000L
        return runCatching { Math.multiplyExact(amount, multiplier) }
            .getOrNull()
            ?.takeIf { it in 1_000L..86_400_000L }
    }
}
