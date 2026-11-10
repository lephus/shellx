package com.shellx.app.ui.pairing

import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.shellx.core.platform.CoreLog
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.awaitCancellation

/** Reads each camera frame's luminance plane and reports the QR text it finds on [mainExecutor]. */
class QrAnalyzer(private val onCode: (String) -> Unit, private val mainExecutor: Executor) : ImageAnalysis.Analyzer {
    override fun analyze(image: ImageProxy) {
        try {
            val plane = image.planes[0]
            val buffer = plane.buffer
            val data = ByteArray(plane.rowStride * image.height)
            buffer.get(data, 0, minOf(buffer.remaining(), data.size))
            QrFrameDecoder.decode(data, plane.rowStride, image.width, image.height)?.let { text ->
                mainExecutor.execute { onCode(text) }
            }
        } finally {
            image.close()
        }
    }
}

/**
 * The back camera (CameraX Preview + ImageAnalysis) reporting every QR text it reads, on the main thread. It runs
 * while the screen is in the composition and the lifecycle allows it; a frame read after the scanner left is dropped.
 */
@Composable
fun QrScanner(onCode: (String) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentOnCode by rememberUpdatedState(onCode)
    val view = remember(context) { PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }
    val delivering = remember { AtomicBoolean(true) }
    DisposableEffect(Unit) {
        delivering.set(true)
        onDispose { delivering.set(false) }
    }

    AndroidView(factory = { view }, modifier = modifier)

    LaunchedEffect(lifecycleOwner, view) {
        val main = ContextCompat.getMainExecutor(context)
        val executor = Executors.newSingleThreadExecutor()
        val preview = Preview.Builder().build().also { it.setSurfaceProvider(view.surfaceProvider) }
        val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
        analysis.setAnalyzer(executor, QrAnalyzer({ text -> if (delivering.get()) currentOnCode(text) }, main))
        var provider: ProcessCameraProvider? = null
        try {
            val instance = ProcessCameraProvider.awaitInstance(context)
            provider = instance
            instance.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            awaitCancellation()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // No back camera, or the camera is in use elsewhere: the viewfinder stays black, paste still works.
            CoreLog.log("camera_bind_failed")
        } finally {
            provider?.unbind(preview, analysis)
            analysis.clearAnalyzer()
            // Shut down only once nothing can hand the executor a frame any more.
            executor.shutdown()
        }
    }
}
