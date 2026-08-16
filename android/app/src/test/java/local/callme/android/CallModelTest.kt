package local.callme.android

import org.junit.Assert.assertEquals
import org.junit.Test

class CallModelTest {
    @Test
    fun unknownStoredModeFallsBackToSystemPhone() {
        assertEquals(CallMode.SYSTEM_PHONE, CallMode.fromStorage("UNKNOWN"))
        assertEquals(CallMode.SYSTEM_PHONE, CallMode.fromStorage(null))
    }

    @Test
    fun scheduledCallReportsPositiveAndNegativeDeviation() {
        val call = ScheduledCall(
            triggerAtMillis = 10_000L,
            mode = CallMode.WECHAT_VOICE,
            callerName = "老板",
            callerNumber = "01055550123",
            delayMillis = 5_000L,
            ringtoneUri = "content://ringtone",
            answerAudioUri = "content://answer"
        )
        assertEquals(250L, call.deviationMillis(10_250L))
        assertEquals(-50L, call.deviationMillis(9_950L))
    }

    @Test
    fun scheduledCallExpiresOnlyAfterGraceWindow() {
        val call = ScheduledCall(
            triggerAtMillis = 10_000L,
            mode = CallMode.WECHAT_VIDEO,
            callerName = "同事",
            callerNumber = "10086",
            delayMillis = 5_000L,
            ringtoneUri = "ring",
            answerAudioUri = "answer"
        )

        assertEquals(false, call.isExpired(130_000L))
        assertEquals(true, call.isExpired(130_001L))
        assertEquals(CallMode.WECHAT_VIDEO, call.toConfiguration().mode)
        assertEquals("10086", call.toConfiguration().callerNumber)
        assertEquals("ring", call.toConfiguration().ringtoneUri)
        assertEquals("answer", call.toConfiguration().answerAudioUri)
    }

    @Test
    fun templatePreservesCurrentConfiguration() {
        val config = CallConfiguration(
            mode = CallMode.WECHAT_VIDEO,
            callerName = "老板",
            callerNumber = "13800138000",
            delayMillis = 180_000L,
            ringtoneUri = "content://ringtone",
            ringtoneName = "铃声.wav",
            answerAudioUri = "content://answer",
            answerAudioName = "接听.mp3"
        )
        val template = CallTemplate.fromConfiguration(config, existingId = "fixed")
        assertEquals("fixed", template.id)
        assertEquals(config, template.toConfiguration())
    }
}
