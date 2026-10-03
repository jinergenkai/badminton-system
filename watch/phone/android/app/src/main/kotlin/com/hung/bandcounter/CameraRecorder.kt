package com.hung.bandcounter

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.util.Log
import android.util.Range
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Corner-camera recording (docs/camera-recording-requirements.md §3).
 *
 * CameraX VideoCapture + Recorder, driven from Dart over
 * `com.voice_counter/camera`; events (started / finalized / start time) go
 * back through [emit]. The settings that matter for court analysis are fixed
 * here and identical every session: 1080p, 30 fps, ~12 Mbps, stabilisation
 * OFF (it crops and warps each frame, which breaks court calibration), back
 * camera at 1x, audio on (racket hits help find shots).
 *
 * Files go to Download/Godminton/<date>/ through MediaStore: a .json next to
 * a video is not allowed under Movies/ (MediaStore only takes video types there),
 * and Download takes both. Visible over USB without root.
 *
 * Splitting a file is stop → wait for Finalize → start: one VideoCapture
 * cannot hold two recordings, so there is a gap of well under a second,
 * which the session places in the break after a set.
 */
class CameraRecorder(
    private val activity: android.app.Activity,
    private val textures: TextureRegistry,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val main = ContextCompat.getMainExecutor(activity)
    private var provider: ProcessCameraProvider? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var texture: TextureRegistry.SurfaceTextureEntry? = null
    private var recording: Recording? = null
    private var recordingUri: String? = null

    /** Best estimate of the wall-clock time of the current file's first frame. */
    private var startWall = Long.MAX_VALUE
    private var startEstimates = 0

    private var permissionResult: MethodChannel.Result? = null

    companion object {
        const val TAG = "CameraRec"
        const val PERMISSION_REQUEST = 4711
        const val BITRATE = 12_000_000
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestPermissions(result)
            "open" -> open(result)
            "close" -> { close(); result.success(true) }
            "start" -> start(call.argument<String>("dir")!!, call.argument<String>("name")!!, result)
            "stop" -> {
                val r = recording
                recording = null
                r?.stop()
                result.success(r != null)
            }
            "rename" -> result.success(rename(call.argument<String>("uri")!!, call.argument<String>("name")!!))
            "writeText" -> result.success(
                writeText(call.argument<String>("dir")!!, call.argument<String>("name")!!,
                    call.argument<String>("text")!!, call.argument<String>("uri"))
            )
            "deviceStatus" -> result.success(deviceStatus())
            "gateway" -> result.success(gateway())
            "openHotspot" -> {
                // No public constant for the tethering page; fall back to
                // the wireless page where hotspot is one tap away.
                val ok = try {
                    activity.startActivity(Intent("android.settings.TETHER_SETTINGS")); true
                } catch (e: Exception) {
                    try { activity.startActivity(Intent(android.provider.Settings.ACTION_WIRELESS_SETTINGS)); true }
                    catch (e2: Exception) { false }
                }
                result.success(ok)
            }
            else -> result.notImplemented()
        }
    }

    // ── Permissions ────────────────────────────────────────────────────────
    private fun granted(p: String) =
        ContextCompat.checkSelfPermission(activity, p) == PackageManager.PERMISSION_GRANTED

    private fun requestPermissions(result: MethodChannel.Result) {
        val need = listOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO).filter { !granted(it) }
        if (need.isEmpty()) { result.success(mapOf("camera" to true, "audio" to true)); return }
        permissionResult = result
        activity.requestPermissions(need.toTypedArray(), PERMISSION_REQUEST)
    }

    fun onPermissionsResult() {
        val r = permissionResult ?: return
        permissionResult = null
        r.success(mapOf(
            "camera" to granted(Manifest.permission.CAMERA),
            "audio" to granted(Manifest.permission.RECORD_AUDIO),
        ))
    }

    // ── Camera ─────────────────────────────────────────────────────────────
    private fun open(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("OLD_ANDROID", "Recording needs Android 10+", null); return
        }
        if (!granted(Manifest.permission.CAMERA)) { result.error("NO_CAMERA", "Camera permission denied", null); return }
        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener({
            try {
                val p = future.get()
                provider = p
                val tex = texture ?: textures.createSurfaceTexture().also { texture = it }
                // The screen is locked to landscape: the file is written
                // upright for that, and the preview texture (raw sensor
                // frames) is turned by the angle CameraX reports.
                @Suppress("DEPRECATION")
                val rotation = activity.windowManager.defaultDisplay.rotation
                val preview = Preview.Builder().setTargetRotation(rotation).build()
                preview.setSurfaceProvider(main) { req ->
                    val w = req.resolution.width
                    val h = req.resolution.height
                    val st = tex.surfaceTexture()
                    st.setDefaultBufferSize(w, h)
                    val surface = Surface(st)
                    req.provideSurface(surface, main) { surface.release() }
                    req.setTransformationInfoListener(main) { info ->
                        emit(mapOf("type" to "preview", "width" to w, "height" to h,
                            "rotation" to info.rotationDegrees))
                    }
                }
                val recorder = Recorder.Builder()
                    .setQualitySelector(QualitySelector.from(Quality.FHD,
                        FallbackStrategy.lowerQualityOrHigherThan(Quality.FHD)))
                    .setTargetVideoEncodingBitRate(BITRATE)
                    .build()
                val vc = VideoCapture.Builder(recorder)
                    .setVideoStabilizationEnabled(false)
                    .setTargetFrameRate(Range(30, 30))
                    .setTargetRotation(rotation)
                    .build()
                videoCapture = vc
                p.unbindAll()
                p.bindToLifecycle(activity as LifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, vc)
                result.success(mapOf("textureId" to tex.id()))
            } catch (e: Exception) {
                Log.e(TAG, "open failed", e)
                result.error("OPEN_FAIL", e.message, null)
            }
        }, main)
    }

    fun close() {
        recording?.stop()
        recording = null
        provider?.unbindAll()
        videoCapture = null
        texture?.release()
        texture = null
    }

    @SuppressLint("MissingPermission")
    private fun start(dir: String, name: String, result: MethodChannel.Result) {
        val vc = videoCapture ?: run { result.error("NOT_OPEN", "Camera not open", null); return }
        if (recording != null) { result.error("BUSY", "Already recording", null); return }
        val cv = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/$dir")
        }
        val opts = MediaStoreOutputOptions.Builder(activity.contentResolver, MediaStore.Downloads.EXTERNAL_CONTENT_URI)
            .setContentValues(cv)
            .build()
        val pending = vc.output.prepareRecording(activity, opts)
        val audio = granted(Manifest.permission.RECORD_AUDIO)
        if (audio) pending.withAudioEnabled()
        startWall = Long.MAX_VALUE
        startEstimates = 0
        recording = pending.start(main) { ev -> onEvent(ev) }
        result.success(mapOf("audio" to audio))
    }

    private fun onEvent(ev: VideoRecordEvent) {
        val now = System.currentTimeMillis()
        val durMs = ev.recordingStats.recordedDurationNanos / 1_000_000
        when (ev) {
            is VideoRecordEvent.Start -> emit(mapOf("type" to "started", "wall" to now))
            is VideoRecordEvent.Status -> {
                // now - duration is the first frame's wall time plus however
                // late this event was delivered; the smallest of the early
                // estimates is the closest. Refined over the first ~5 s.
                if (durMs > 0 && startEstimates < 150) {
                    startEstimates++
                    val est = now - durMs
                    if (est < startWall) {
                        startWall = est
                        emit(mapOf("type" to "startWall", "wall" to est))
                    }
                }
                if (startEstimates % 30 == 0) {
                    emit(mapOf("type" to "status", "durationMs" to durMs,
                        "bytes" to ev.recordingStats.numBytesRecorded))
                }
            }
            is VideoRecordEvent.Finalize -> {
                val uri = ev.outputResults.outputUri.toString()
                recordingUri = uri
                emit(mapOf(
                    "type" to "finalized",
                    "uri" to uri,
                    "durationMs" to durMs,
                    "error" to if (ev.hasError()) "${ev.error}: ${ev.cause?.message}" else null,
                ))
            }
            else -> {}
        }
    }

    private fun rename(uri: String, name: String): Boolean = try {
        val cv = ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, name) }
        activity.contentResolver.update(android.net.Uri.parse(uri), cv, null, null) > 0
    } catch (e: Exception) {
        Log.w(TAG, "rename failed: ${e.message}")
        false
    }

    /** Creates Download/<dir>/<name>, or overwrites [uri]. Returns the uri. */
    private fun writeText(dir: String, name: String, text: String, uri: String?): String? = try {
        val r = activity.contentResolver
        val target = if (uri != null) android.net.Uri.parse(uri) else {
            val cv = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/$dir")
            }
            r.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv)
        }
        target?.let { u ->
            r.openOutputStream(u, "wt")?.use { it.write(text.toByteArray()) }
            u.toString()
        }
    } catch (e: Exception) {
        Log.w(TAG, "writeText failed: ${e.message}")
        null
    }

    // ── Device ─────────────────────────────────────────────────────────────
    private fun deviceStatus(): Map<String, Any?> {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val temp = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val plugged = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        return mapOf(
            "freeBytes" to stat.availableBytes,
            "battery" to if (level >= 0) level * 100 / scale else -1,
            "tempC" to temp / 10.0,
            "charging" to plugged,
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
        )
    }

    /**
     * The Wi-Fi gateway as a.b.c.d, or null. On the phone's hotspot the
     * gateway is the phone itself: that is how the tablet finds the camera
     * without anyone typing an address.
     */
    @Suppress("DEPRECATION")
    private fun gateway(): String? {
        val wm = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val g = wm.dhcpInfo?.gateway ?: 0
        if (g == 0) return null
        return "${g and 0xff}.${g shr 8 and 0xff}.${g shr 16 and 0xff}.${g shr 24 and 0xff}"
    }
}
