package local.callme.android

import android.content.Context
import androidx.core.content.edit
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object ExperimentLog {
    private const val PREFERENCES = "callme_experiment"
    private const val KEY_EVENTS = "events"
    private const val MAX_EVENTS = 20

    @Synchronized
    fun add(context: Context, message: String) {
        val time = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        val updated = (listOf("$time  $message") + read(context))
            .take(MAX_EVENTS)
            .joinToString("\n")
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit { putString(KEY_EVENTS, updated) }
    }

    fun read(context: Context): List<String> {
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(KEY_EVENTS, "")
            .orEmpty()
            .lineSequence()
            .filter { it.isNotBlank() }
            .map { event ->
                event
                    .replace("微信风格", "微信")
                    .replace("本地模拟", "")
                    .replace("模拟", "")
            }
            .toList()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit { remove(KEY_EVENTS) }
    }
}
