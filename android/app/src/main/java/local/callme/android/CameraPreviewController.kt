package local.callme.android

import android.hardware.camera2.CameraCharacteristics
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner

/**
 * CameraX owns sensor rotation, device orientation and center-crop math. Keeping a single
 * PreviewView mounted across incoming/connected states prevents the answer transition from
 * closing and reopening Camera2, which was both slow and visibly distorted on tall displays.
 */
@Composable
internal fun CameraPreview(
    modifier: Modifier = Modifier,
    lensFacing: Int = CameraCharacteristics.LENS_FACING_FRONT
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { previewView }
    )

    DisposableEffect(lifecycleOwner, lensFacing) {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        val executor = ContextCompat.getMainExecutor(context)
        providerFuture.addListener(
            {
                runCatching {
                    val provider = providerFuture.get()
                    val selector = CameraSelector.Builder()
                        .requireLensFacing(
                            if (lensFacing == CameraCharacteristics.LENS_FACING_BACK) {
                                CameraSelector.LENS_FACING_BACK
                            } else {
                                CameraSelector.LENS_FACING_FRONT
                            }
                        )
                        .build()
                    val preview = Preview.Builder().build().also {
                        it.surfaceProvider = previewView.surfaceProvider
                    }
                    provider.unbindAll()
                    provider.bindToLifecycle(lifecycleOwner, selector, preview)
                }
            },
            executor
        )

        onDispose {
            if (providerFuture.isDone) {
                runCatching { providerFuture.get().unbindAll() }
            }
        }
    }
}
