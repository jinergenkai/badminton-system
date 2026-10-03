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
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.Camera
import androidx.camera.core.CameraEffect
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.effects.OverlayEffect
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
    private var lastStatusAt = 0L

    // Preview: bound always (so turning it on needs no rebind), but only
    // fed frames while someone looks at it — the board keeps its camera
    // preview dark behind the scoreboard.
    private var boundCamera: Camera? = null
    private var previewUseCase: Preview? = null
    private var previewProvider: Preview.SurfaceProvider? = null

    private var permissionResult: MethodChannel.Result? = null

    // ── Score overlay, burned into the video (and the preview) ─────────────
    private var overlay: OverlayEffect? = null
    @Volatile private var ovA = 0
    @Volatile private var ovB = 0
    @Volatile private var ovShow = false
    private val ovBox = Paint().apply { isAntiAlias = true }
    private val ovText = Paint().apply {
        isAntiAlias = true
        color = Color.WHITE
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
    }
    private val ovClock = Paint().apply {
        isAntiAlias = true
        color = Color.WHITE
        typeface = Typeface.MONOSPACE
    }
    private val clockFmt = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)

    companion object {
        const val TAG = "CameraRec"
        const val PERMISSION_REQUEST = 4711
        const val BITRATE = 12_000_000
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestPermissions(result)
            "open" -> open(
                call.argument<String>("lens") ?: "back",
                call.argument<Boolean>("preview") ?: true,
                call.argument<Boolean>("overlay") ?: true,
                call.argument<Boolean>("previewActive") ?: true,
                result,
            )
            "setLock" -> setLock(call.argument<Boolean>("on") ?: false, result)
            "setPreviewActive" -> {
                val on = call.argument<Boolean>("on") ?: false
                previewUseCase?.setSurfaceProvider(main, if (on) previewProvider else null)
                result.success(previewUseCase != null)
            }
            "setOverlay" -> {
                ovA = call.argument<Int>("a") ?: 0
                ovB = call.argument<Int>("b") ?: 0
                ovShow = call.argument<Boolean>("show") ?: false
                result.success(true)
            }
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
            "listVideos" -> Thread { val v = listVideos(); main.execute { result.success(v) } }.start()
            "thumbnail" -> {
                val uri = call.argument<String>("uri")!!
                val w = call.argument<Int>("width") ?: 320
                Thread {
                    val b = thumbnail(uri, w)
                    main.execute { result.success(b) }
                }.start()
            }
            "openVideo" -> result.success(openVideo(call.argument<String>("uri")!!))
            "deleteVideos" -> {
                val uris = call.argument<List<String>>("uris") ?: emptyList()
                Thread { val n = deleteVideos(uris); main.execute { result.success(n) } }.start()
            }
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
    private fun open(lens: String, withPreview: Boolean, withOverlay: Boolean, previewActive: Boolean,
                     result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("OLD_ANDROID", "Recording needs Android 10+", null); return
        }
        if (!granted(Manifest.permission.CAMERA)) { result.error("NO_CAMERA", "Camera permission denied", null); return }
        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener({
            try {
                val p = future.get()
                provider = p
                val tex = if (withPreview) texture ?: textures.createSurfaceTexture().also { texture = it } else null
                // The screen is locked to landscape: the file is written
                // upright for that, and the preview texture (raw sensor
                // frames) is turned by the angle CameraX reports.
                @Suppress("DEPRECATION")
                val rotation = activity.windowManager.defaultDisplay.rotation
                val preview = if (tex == null) null else Preview.Builder().setTargetRotation(rotation).build()
                val provider = Preview.SurfaceProvider { req ->
                    val w = req.resolution.width
                    val h = req.resolution.height
                    val st = tex!!.surfaceTexture()
                    st.setDefaultBufferSize(w, h)
                    val surface = Surface(st)
                    req.provideSurface(surface, main) { surface.release() }
                    req.setTransformationInfoListener(main) { info ->
                        emit(mapOf("type" to "preview", "width" to w, "height" to h,
                            "rotation" to info.rotationDegrees))
                    }
                }
                previewUseCase = preview
                previewProvider = provider
                if (previewActive) preview?.setSurfaceProvider(main, provider)
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
                val group = UseCaseGroup.Builder().addUseCase(vc)
                if (preview != null) group.addUseCase(preview)
                overlay?.close()
                overlay = null
                if (withOverlay) {
                    val targets = CameraEffect.VIDEO_CAPTURE or (if (preview != null) CameraEffect.PREVIEW else 0)
                    val fx = OverlayEffect(targets, 0, Handler(Looper.getMainLooper())) { t ->
                        Log.w(TAG, "overlay: ${t.message}")
                    }
                    fx.setOnDrawListener { frame -> drawOverlay(frame.overlayCanvas); true }
                    group.addEffect(fx)
                    overlay = fx
                }
                val selector = if (lens == "front") CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                p.unbindAll()
                boundCamera = p.bindToLifecycle(activity as LifecycleOwner, selector, group.build())
                result.success(mapOf("textureId" to tex?.id()))
            } catch (e: Exception) {
                Log.e(TAG, "open failed", e)
                result.error("OPEN_FAIL", e.message, null)
            }
        }, main)
    }

    /**
     * Top-left: red and blue score boxes and the wall clock, sized from the
     * frame height so it reads the same at any resolution. Small on purpose:
     * the analysis looks at the court, not the corner.
     */
    private fun drawOverlay(c: android.graphics.Canvas) {
        c.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        // The canvas is the shared camera stream (4:3 on the Redmi 13C); the
        // 16:9 video is its centre band. Measured: drawn at the canvas top,
        // the score boxes were cut off in the file. So place everything in
        // the 16:9 band, which both the video and the preview contain.
        val cw = c.width.toFloat()
        val ch = c.height.toFloat()
        val bandH = minOf(ch, cw * 9f / 16f)
        val bandW = minOf(cw, ch * 16f / 9f)
        val top = (ch - bandH) / 2f
        val left = (cw - bandW) / 2f
        val unit = bandH / 18f
        val pad = unit * 0.5f
        val x = left + pad
        val y = top + pad
        val box = unit * 1.8f
        ovText.textSize = unit * 1.3f
        ovClock.textSize = unit * 0.7f
        if (ovShow) {
            ovBox.color = Color.argb(220, 0xFF, 0x52, 0x52)
            c.drawRoundRect(RectF(x, y, x + box, y + box), unit * 0.3f, unit * 0.3f, ovBox)
            ovBox.color = Color.argb(220, 0x44, 0x8A, 0xFF)
            c.drawRoundRect(RectF(x + box + pad * 0.4f, y, x + 2 * box + pad * 0.4f, y + box), unit * 0.3f, unit * 0.3f, ovBox)
            val base = y + box / 2 - (ovText.descent() + ovText.ascent()) / 2
            c.drawText("$ovA", x + box / 2, base, ovText)
            c.drawText("$ovB", x + box + pad * 0.4f + box / 2, base, ovText)
        }
        val clockY = y + (if (ovShow) box + unit * 0.9f else unit * 0.8f)
        ovBox.color = Color.argb(140, 0, 0, 0)
        val w = ovClock.measureText("00:00:00")
        c.drawRoundRect(RectF(x, clockY - unit * 0.75f, x + w + unit * 0.5f, clockY + unit * 0.25f), unit * 0.2f, unit * 0.2f, ovBox)
        c.drawText(clockFmt.format(java.util.Date()), x + unit * 0.25f, clockY, ovClock)
    }

    fun close() {
        recording?.stop()
        recording = null
        boundCamera = null
        provider?.unbindAll()
        overlay?.close()
        overlay = null
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
                // Status events come with every frame: forward one every 2 s.
                // (Was `startEstimates % 30 == 0`, which stays true once the
                // counter stops at 150: 30 messages a second into Dart, each
                // redrawing the UI. Measured ~56 % CPU on the tablet.)
                if (now - lastStatusAt >= 2000) {
                    lastStatusAt = now
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

    // ── Focus / exposure lock ──────────────────────────────────────────────
    /**
     * The phone's own Camera2 3A locks: focus held where it is (one AF pass
     * at the centre, then no auto-cancel), exposure and white balance
     * frozen. A player walking past the lens then neither refocuses nor
     * darkens the frame. Off: back to continuous auto. Fixed-focus lenses
     * (most front cameras) only get the exposure lock.
     * Replies {focus, exposure}: which of the two this camera could lock.
     */
    @androidx.annotation.OptIn(ExperimentalCamera2Interop::class)
    private fun setLock(on: Boolean, result: MethodChannel.Result) {
        val cam = boundCamera ?: run { result.success(mapOf("focus" to false, "exposure" to false)); return }
        val c2 = Camera2CameraControl.from(cam.cameraControl)
        val info = Camera2CameraInfo.from(cam.cameraInfo)
        val aeLock = info.getCameraCharacteristic(CameraCharacteristics.CONTROL_AE_LOCK_AVAILABLE) == true
        val awbLock = info.getCameraCharacteristic(CameraCharacteristics.CONTROL_AWB_LOCK_AVAILABLE) == true
        val afModes = info.getCameraCharacteristic(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
        val hasAf = afModes != null && afModes.any { it == CaptureRequest.CONTROL_AF_MODE_AUTO }
        if (!on) {
            c2.clearCaptureRequestOptions()
            cam.cameraControl.cancelFocusAndMetering()
            result.success(mapOf("focus" to false, "exposure" to false))
            return
        }
        fun lockExposure() {
            val o = CaptureRequestOptions.Builder()
            if (aeLock) o.setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, true)
            if (awbLock) o.setCaptureRequestOption(CaptureRequest.CONTROL_AWB_LOCK, true)
            c2.setCaptureRequestOptions(o.build())
        }
        if (hasAf) {
            val point = SurfaceOrientedMeteringPointFactory(1f, 1f).createPoint(0.5f, 0.5f)
            val action = FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF)
                .disableAutoCancel()
                .build()
            val f = cam.cameraControl.startFocusAndMetering(action)
            f.addListener({
                lockExposure()
                val focused = try { f.get().isFocusSuccessful } catch (e: Exception) { false }
                result.success(mapOf("focus" to focused, "exposure" to aeLock))
            }, main)
        } else {
            lockExposure()
            result.success(mapOf("focus" to false, "exposure" to aeLock))
        }
    }

    // ── Gallery ────────────────────────────────────────────────────────────
    /**
     * Every finished video under Download/Godminton, newest first. A file
     * still being recorded is pending in MediaStore and not listed.
     */
    private fun listVideos(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val cols = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DURATION,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        try {
            activity.contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, cols,
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND ${MediaStore.MediaColumns.MIME_TYPE} = ?",
                arrayOf("Download/Godminton/%", "video/mp4"),
                "${MediaStore.MediaColumns.DATE_ADDED} DESC",
            )?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getLong(0)
                    val uri = android.content.ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id)
                    var dur = if (c.isNull(3)) 0L else c.getLong(3)
                    if (dur <= 0) dur = durationOf(uri)
                    out.add(mapOf(
                        "uri" to uri.toString(),
                        "name" to c.getString(1),
                        "size" to c.getLong(2),
                        "durationMs" to dur,
                        "added" to c.getLong(4) * 1000,
                        "dir" to c.getString(5),
                    ))
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "listVideos: ${e.message}")
        }
        return out
    }

    private fun durationOf(uri: android.net.Uri): Long = try {
        val r = android.media.MediaMetadataRetriever()
        r.setDataSource(activity, uri)
        val d = r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        r.release()
        d
    } catch (e: Exception) { 0L }

    /** JPEG bytes of a frame, [width] px wide (16:9). */
    private fun thumbnail(uri: String, width: Int): ByteArray? = try {
        val bmp = activity.contentResolver.loadThumbnail(
            android.net.Uri.parse(uri), android.util.Size(width, width * 9 / 16), null)
        val bos = java.io.ByteArrayOutputStream()
        bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, bos)
        bos.toByteArray()
    } catch (e: Exception) {
        Log.w(TAG, "thumbnail: ${e.message}")
        null
    }

    /**
     * Deletes each video and the .json of the same name next to it. Only
     * files this app recorded can be deleted (MediaStore ownership), which
     * is all the gallery lists. Returns how many videos went.
     */
    private fun deleteVideos(uris: List<String>): Int {
        val r = activity.contentResolver
        var n = 0
        for (s in uris) {
            try {
                val uri = android.net.Uri.parse(s)
                var name: String? = null
                var dir: String? = null
                r.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.RELATIVE_PATH),
                    null, null, null)?.use { c -> if (c.moveToFirst()) { name = c.getString(0); dir = c.getString(1) } }
                if (r.delete(uri, null, null) > 0) n++
                val base = name?.substringBeforeLast('.') ?: continue
                r.delete(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
                    arrayOf("$base.json", dir))
            } catch (e: Exception) {
                Log.w(TAG, "delete $s: ${e.message}")
            }
        }
        return n
    }

    /** Plays [uri] in the phone's own video player. */
    private fun openVideo(uri: String): Boolean = try {
        val i = Intent(Intent.ACTION_VIEW)
            .setDataAndType(android.net.Uri.parse(uri), "video/mp4")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(i)
        true
    } catch (e: Exception) {
        Log.w(TAG, "openVideo: ${e.message}")
        false
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
