package local.callme.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class CallInputValidatorTest {
    @Test
    fun rejectsBlankAndEmergencyCallerNumbers() {
        assertNotNull(CallInputValidator.callerNumberError(""))
        assertEquals("请勿使用紧急号码", CallInputValidator.callerNumberError("112"))
        assertEquals("请勿使用紧急号码", CallInputValidator.callerNumberError("9-1-1"))
    }

    @Test
    fun acceptsSafeDisplayNumber() {
        assertNull(CallInputValidator.callerNumberError("010-5555-0123"))
    }

    @Test
    fun convertsCustomDelayAndEnforcesOneDayLimit() {
        assertEquals(15_000L, CallInputValidator.customDelayMillis("15", false))
        assertEquals(300_000L, CallInputValidator.customDelayMillis("5", true))
        assertEquals(86_400_000L, CallInputValidator.customDelayMillis("1440", true))
        assertNull(CallInputValidator.customDelayMillis("0", false))
        assertNull(CallInputValidator.customDelayMillis("1441", true))
        assertNull(CallInputValidator.customDelayMillis("abc", true))
    }

    @Test
    fun validatesCallerNameLength() {
        assertNotNull(CallInputValidator.callerNameError("   "))
        assertNull(CallInputValidator.callerNameError("老板"))
        assertNotNull(CallInputValidator.callerNameError("a".repeat(31)))
    }
}
