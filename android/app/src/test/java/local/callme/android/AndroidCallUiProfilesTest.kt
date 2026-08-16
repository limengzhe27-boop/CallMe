package local.callme.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidCallUiProfilesTest {
    @Test
    fun resolvesMajorAndroidDeviceFamilies() {
        assertEquals(
            AndroidCallUiFamily.XIAOMI,
            AndroidCallUiProfiles.resolve("Xiaomi", "Redmi").family
        )
        assertEquals(
            AndroidCallUiFamily.HUAWEI_HONOR,
            AndroidCallUiProfiles.resolve("HONOR", "HONOR").family
        )
        assertEquals(
            AndroidCallUiFamily.OPPO_FAMILY,
            AndroidCallUiProfiles.resolve("OnePlus", "OnePlus").family
        )
        assertEquals(
            AndroidCallUiFamily.VIVO_FAMILY,
            AndroidCallUiProfiles.resolve("vivo", "iQOO").family
        )
        assertEquals(
            AndroidCallUiFamily.SAMSUNG,
            AndroidCallUiProfiles.resolve("samsung", "samsung").family
        )
    }

    @Test
    fun unknownManufacturerUsesResponsiveAospProfile() {
        val profile = AndroidCallUiProfiles.resolve("Example Devices", "Example")
        assertEquals(AndroidCallUiFamily.GOOGLE_AOSP, profile.family)
        assertTrue(profile.incomingActionDiameterDp > 0)
        assertTrue(profile.videoPipHeightDp > profile.videoPipWidthDp)
    }

    @Test
    fun xiaomiProfileRemainsTheScreenshotCalibratedReference() {
        val profile = AndroidCallUiProfiles.resolve("Xiaomi", "POCO")
        assertEquals("已按小米真机截图校准", profile.referenceStatus)
        assertEquals(112, profile.videoPipWidthDp)
        assertEquals(218, profile.videoPipHeightDp)
    }
}
