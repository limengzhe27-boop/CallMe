package local.callme.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

class MainActivity : ComponentActivity() {
    private var recoveringIncomingCall = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        TelecomController(this).registerPhoneAccount()
            .onSuccess { ExperimentLog.add(this, "已注册 CallMe 系统通话账户") }
            .onFailure { ExperimentLog.add(this, "注册通话账户失败：${it.message}") }

        setContent {
            CallMeTheme {
                CallMeDashboardScreen()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (recoveringIncomingCall) return
        val activeCall = ActiveSimulatedCallStore.load(this) ?: return
        recoveringIncomingCall = true
        ExperimentLog.add(this, "打开 App 时恢复正在响铃的微信来电页面")
        startActivity(SimulatedCallNotifier.incomingActivityIntent(this, activeCall))
    }

    override fun onPause() {
        recoveringIncomingCall = false
        super.onPause()
    }
}

@Composable
private fun CallMeTheme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) {
        darkColorScheme(
            primary = Color(0xFF79D6A5),
            onPrimary = Color(0xFF003824),
            primaryContainer = Color(0xFF145238),
            onPrimaryContainer = Color(0xFFA5F2C7),
            secondary = Color(0xFF79D6A5),
            onSecondary = Color(0xFF003824),
            secondaryContainer = Color(0xFF244C39),
            onSecondaryContainer = Color(0xFFC0F1D5),
            background = Color(0xFF111412),
            onBackground = Color(0xFFE2E4E1),
            surface = Color(0xFF1A1D1B),
            onSurface = Color(0xFFE2E4E1),
            surfaceVariant = Color(0xFF2A2F2C),
            onSurfaceVariant = Color(0xFFBCC4BF),
            outline = Color(0xFF89928D),
            outlineVariant = Color(0xFF3E4742)
        )
    } else {
        lightColorScheme(
            primary = Color(0xFF237A52),
            onPrimary = Color.White,
            primaryContainer = Color(0xFFD8F2E3),
            onPrimaryContainer = Color(0xFF0A3B25),
            secondary = Color(0xFF366A50),
            onSecondary = Color.White,
            secondaryContainer = Color(0xFFDCEFE4),
            onSecondaryContainer = Color(0xFF173D2A),
            background = Color(0xFFF3F5F3),
            onBackground = Color(0xFF1A1C1B),
            surface = Color.White,
            onSurface = Color(0xFF1A1C1B),
            surfaceVariant = Color(0xFFE9EDE9),
            onSurfaceVariant = Color(0xFF5C635F),
            outline = Color(0xFF89918C),
            outlineVariant = Color(0xFFD9DFDB)
        )
    }
    MaterialTheme(colorScheme = colors, content = content)
}
