package local.callme.android

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import androidx.core.net.toUri

class AudioPlayer(private val context: Context) {
    private var mediaPlayer: MediaPlayer? = null
    private var ringtone: Ringtone? = null

    fun playRingtone(
        uriString: String,
        looping: Boolean = true,
        onCompletion: () -> Unit = {}
    ): Boolean {
        stop()
        if (uriString.isBlank()) {
            return runCatching {
                val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ringtone = RingtoneManager.getRingtone(context, defaultUri)?.also {
                    it.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    it.play()
                }
                ringtone != null
            }.onFailure {
                ExperimentLog.add(context, "默认铃声播放失败：${it.message}")
            }.getOrDefault(false)
        }
        mediaPlayer = create(
            uriString,
            AudioAttributes.USAGE_NOTIFICATION_RINGTONE,
            looping,
            onCompletion
        )
        return mediaPlayer != null
    }

    fun playAnswerAudio(uriString: String, onCompletion: () -> Unit = {}): Boolean {
        stop()
        if (uriString.isBlank()) return true
        mediaPlayer = create(
            uriString,
            AudioAttributes.USAGE_VOICE_COMMUNICATION,
            false,
            onCompletion
        )
        return mediaPlayer != null
    }

    fun stop() {
        runCatching { ringtone?.stop() }
        ringtone = null
        runCatching { mediaPlayer?.stop() }
        runCatching { mediaPlayer?.release() }
        mediaPlayer = null
    }

    fun isPlaying(): Boolean = runCatching {
        ringtone?.isPlaying == true || mediaPlayer?.isPlaying == true
    }.getOrDefault(false)

    private fun create(
        uriString: String,
        usage: Int,
        looping: Boolean,
        onCompletion: () -> Unit = {}
    ): MediaPlayer? {
        return runCatching {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(usage)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(context, uriString.toUri())
                isLooping = looping
                setOnPreparedListener { it.start() }
                setOnCompletionListener {
                    it.release()
                    if (mediaPlayer === it) mediaPlayer = null
                    onCompletion()
                }
                setOnErrorListener { player, what, extra ->
                    ExperimentLog.add(context, "音频异步播放失败：what=$what extra=$extra")
                    player.release()
                    if (mediaPlayer === player) mediaPlayer = null
                    true
                }
                prepareAsync()
            }
        }.onFailure {
            ExperimentLog.add(context, "音频播放失败：${it.message}")
        }.getOrNull()
    }
}
