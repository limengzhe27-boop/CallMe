package local.callme.android

import android.os.Build
import java.util.Locale

/**
 * Device-family layout values for CallMe's in-app voice/video surface.
 *
 * System phone calls never use these values: Telecom hands those calls to the device's default
 * phone app. These profiles only keep the custom voice/video surface usable across different
 * status-bar, navigation-bar and display proportions. Xiaomi/HyperOS is the reference profile
 * because it has been verified against screenshots from a real Xiaomi device; other profiles are
 * conservative starting points that can be refined with screenshots from those devices.
 */
data class AndroidCallUiProfile(
    val family: AndroidCallUiFamily,
    val displayName: String,
    val referenceStatus: String,
    val incomingVoiceIdentityFraction: Float,
    val incomingVideoIdentityFraction: Float,
    val incomingVoiceInviteFraction: Float,
    val incomingVideoInviteFraction: Float,
    val connectedVoiceIdentityFraction: Float,
    val videoPipTopDp: Int,
    val videoPipWidthDp: Int,
    val videoPipHeightDp: Int,
    val incomingActionDiameterDp: Int,
    val voiceActionDiameterDp: Int,
    val videoActionDiameterDp: Int,
    val incomingBottomDp: Int,
    val voiceBottomDp: Int,
    val videoBottomDp: Int
)

enum class AndroidCallUiFamily {
    XIAOMI,
    HUAWEI_HONOR,
    OPPO_FAMILY,
    VIVO_FAMILY,
    SAMSUNG,
    GOOGLE_AOSP
}

object AndroidCallUiProfiles {
    fun current(): AndroidCallUiProfile = resolve(Build.MANUFACTURER, Build.BRAND)

    fun resolve(manufacturer: String?, brand: String?): AndroidCallUiProfile {
        val identity = listOfNotNull(manufacturer, brand)
            .joinToString(" ")
            .lowercase(Locale.ROOT)
        return when {
            identity.containsAny("xiaomi", "redmi", "poco") -> xiaomi
            identity.containsAny("huawei", "honor") -> huaweiHonor
            identity.containsAny("oppo", "oneplus", "realme") -> oppoFamily
            identity.containsAny("vivo", "iqoo") -> vivoFamily
            identity.contains("samsung") -> samsung
            else -> googleAosp
        }
    }

    private fun String.containsAny(vararg values: String): Boolean = values.any(::contains)

    private val xiaomi = AndroidCallUiProfile(
        family = AndroidCallUiFamily.XIAOMI,
        displayName = "小米 / Redmi / POCO",
        referenceStatus = "已按小米真机截图校准",
        incomingVoiceIdentityFraction = 0.185f,
        incomingVideoIdentityFraction = 0.105f,
        incomingVoiceInviteFraction = 0.63f,
        incomingVideoInviteFraction = 0.56f,
        connectedVoiceIdentityFraction = 0.205f,
        videoPipTopDp = 76,
        videoPipWidthDp = 112,
        videoPipHeightDp = 218,
        incomingActionDiameterDp = 76,
        voiceActionDiameterDp = 76,
        videoActionDiameterDp = 68,
        incomingBottomDp = 22,
        voiceBottomDp = 24,
        videoBottomDp = 18
    )

    private val huaweiHonor = AndroidCallUiProfile(
        family = AndroidCallUiFamily.HUAWEI_HONOR,
        displayName = "华为 / 荣耀",
        referenceStatus = "自适应基线，待对应真机截图校准",
        incomingVoiceIdentityFraction = 0.17f,
        incomingVideoIdentityFraction = 0.10f,
        incomingVoiceInviteFraction = 0.61f,
        incomingVideoInviteFraction = 0.54f,
        connectedVoiceIdentityFraction = 0.19f,
        videoPipTopDp = 70,
        videoPipWidthDp = 108,
        videoPipHeightDp = 204,
        incomingActionDiameterDp = 74,
        voiceActionDiameterDp = 74,
        videoActionDiameterDp = 66,
        incomingBottomDp = 28,
        voiceBottomDp = 30,
        videoBottomDp = 24
    )

    private val oppoFamily = AndroidCallUiProfile(
        family = AndroidCallUiFamily.OPPO_FAMILY,
        displayName = "OPPO / 一加 / realme",
        referenceStatus = "自适应基线，待对应真机截图校准",
        incomingVoiceIdentityFraction = 0.18f,
        incomingVideoIdentityFraction = 0.105f,
        incomingVoiceInviteFraction = 0.62f,
        incomingVideoInviteFraction = 0.55f,
        connectedVoiceIdentityFraction = 0.20f,
        videoPipTopDp = 74,
        videoPipWidthDp = 110,
        videoPipHeightDp = 210,
        incomingActionDiameterDp = 74,
        voiceActionDiameterDp = 74,
        videoActionDiameterDp = 66,
        incomingBottomDp = 26,
        voiceBottomDp = 28,
        videoBottomDp = 22
    )

    private val vivoFamily = AndroidCallUiProfile(
        family = AndroidCallUiFamily.VIVO_FAMILY,
        displayName = "vivo / iQOO",
        referenceStatus = "自适应基线，待对应真机截图校准",
        incomingVoiceIdentityFraction = 0.175f,
        incomingVideoIdentityFraction = 0.10f,
        incomingVoiceInviteFraction = 0.615f,
        incomingVideoInviteFraction = 0.545f,
        connectedVoiceIdentityFraction = 0.195f,
        videoPipTopDp = 72,
        videoPipWidthDp = 108,
        videoPipHeightDp = 206,
        incomingActionDiameterDp = 74,
        voiceActionDiameterDp = 74,
        videoActionDiameterDp = 66,
        incomingBottomDp = 28,
        voiceBottomDp = 30,
        videoBottomDp = 24
    )

    private val samsung = AndroidCallUiProfile(
        family = AndroidCallUiFamily.SAMSUNG,
        displayName = "Samsung Galaxy",
        referenceStatus = "自适应基线，待对应真机截图校准",
        incomingVoiceIdentityFraction = 0.16f,
        incomingVideoIdentityFraction = 0.095f,
        incomingVoiceInviteFraction = 0.59f,
        incomingVideoInviteFraction = 0.53f,
        connectedVoiceIdentityFraction = 0.18f,
        videoPipTopDp = 68,
        videoPipWidthDp = 106,
        videoPipHeightDp = 198,
        incomingActionDiameterDp = 72,
        voiceActionDiameterDp = 72,
        videoActionDiameterDp = 64,
        incomingBottomDp = 32,
        voiceBottomDp = 34,
        videoBottomDp = 28
    )

    private val googleAosp = AndroidCallUiProfile(
        family = AndroidCallUiFamily.GOOGLE_AOSP,
        displayName = "Google / AOSP 通用",
        referenceStatus = "响应式通用基线",
        incomingVoiceIdentityFraction = 0.17f,
        incomingVideoIdentityFraction = 0.10f,
        incomingVoiceInviteFraction = 0.60f,
        incomingVideoInviteFraction = 0.54f,
        connectedVoiceIdentityFraction = 0.19f,
        videoPipTopDp = 70,
        videoPipWidthDp = 108,
        videoPipHeightDp = 202,
        incomingActionDiameterDp = 72,
        voiceActionDiameterDp = 72,
        videoActionDiameterDp = 64,
        incomingBottomDp = 30,
        voiceBottomDp = 32,
        videoBottomDp = 26
    )
}
