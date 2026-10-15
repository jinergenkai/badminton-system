package com.hung.bandcounter

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.auth.AuthApi
import com.xiaomi.xms.wearable.auth.Permission
import com.xiaomi.xms.wearable.message.MessageApi
import com.xiaomi.xms.wearable.message.OnMessageReceivedListener
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val WATCH_CHANNEL = "com.voice_counter/watch"
    private val WATCH_EVENT_CHANNEL = "com.voice_counter/watch_events"
    private var eventSink: EventChannel.EventSink? = null

    private lateinit var nodeApi: NodeApi
    private lateinit var messageApi: MessageApi
    private lateinit var authApi: AuthApi
    private var watchNodeId: String? = null

    private val scope = CoroutineScope(Dispatchers.Main + Job())

    /** Band "Blank Phone" and the board's max-brightness chip share the window brightness. */
    private var blank = false
    private var brightMax = false
    /** Camera screen while recording: lowest brightness, less heat. */
    private var dim = false

    private var camera: CameraRecorder? = null
    private var cameraSink: EventChannel.EventSink? = null

    private fun windowBrightness(): Float = when {
        blank || dim -> 0.01f
        brightMax -> 1f
        else -> WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
    }

    private fun deviceState(am: AudioManager): Map<String, Any> = mapOf(
        "vol" to am.getStreamVolume(AudioManager.STREAM_MUSIC),
        "volMax" to am.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
        "brightMax" to brightMax,
    )

    /** Last initialize() report, so Dart can re-read it without re-running init. */
    private var lastReport: Map<String, Any?> = mapOf("ok" to false, "error" to "not initialized")

    companion object {
        private const val TAG = "MainActivity"

        /**
         * Step-0 diagnostics tag. Everything interesting goes here so the whole
         * handshake can be read with a single filter:
         *   adb logcat -s BandDiag
         */
        private const val DIAG = "BandDiag"
    }

    /**
     * The SDK reports failures as typed exceptions built from a Status —
     * PermissionDenied, SignatureVerifyFailed, AppNotInstalled,
     * DeviceDisconnected. The class name is the useful part and it is exactly
     * what we have been discarding, so keep it.
     */
    private fun describe(e: Exception?): String {
        if (e == null) return "unknown"
        return "${e.javaClass.simpleName}: ${e.message}"
    }

    private val messageListener = OnMessageReceivedListener { nodeId, message ->
        val raw = String(message)
        // If this line never appears, the receive path is down — that is the
        // whole one-way-traffic symptom in a single log line.
        Log.i(DIAG, "<<< RECV from watch (${message.size} bytes): $raw")
        Log.d(TAG, "RAW From Watch: $raw")
        try {
            val json = JSONObject(raw)
            val map = mutableMapOf<String, Any?>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                map[key] = toCodec(json.get(key))
            }
            map["type"] = "command" // Ensure type is command for ScoreController

            scope.launch(Dispatchers.Main) {
                eventSink?.success(map)
            }
        } catch (e: Exception) { Log.e(TAG, "Parse error: ${e.message}") }
    }

    // The EventChannel codec only takes plain Kotlin values: a raw JSONObject,
    // JSONArray or JSONObject.NULL makes eventSink.success throw and the whole
    // message is lost. Match records carry a nested lineup, so convert deeply.
    private fun toCodec(v: Any?): Any? = when (v) {
        null, JSONObject.NULL -> null
        is JSONObject -> {
            val m = HashMap<String, Any?>()
            val it = v.keys()
            while (it.hasNext()) {
                val k = it.next()
                m[k] = toCodec(v.get(k))
            }
            m
        }
        is JSONArray -> (0 until v.length()).map { toCodec(v.get(it)) }
        else -> v
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            nodeApi = Wearable.getNodeApi(this)
            messageApi = Wearable.getMessageApi(this)
            authApi = Wearable.getAuthApi(this)
        } catch (e: Exception) { Log.e(TAG, "SDK Init error: ${e.message}") }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> initWearableConnect(result)
                // Band "Blank Phone": dim this window to the floor. The screen
                // stays technically on (the score screen's wakelock is kept),
                // so the app and the fragile band link keep running.
                "setBlank" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    val lp = window.attributes
                    blank = on
                    lp.screenBrightness = windowBrightness()
                    window.attributes = lp
                    Log.i(DIAG, "setBlank on=$on")
                    result.success(true)
                }
                "sendMessage" -> {
                    val data = call.argument<Map<String, Any>>("data")
                    val nodeId = watchNodeId
                    if (data != null && nodeId != null) {
                        val json = JSONObject(data).toString()
                        val payload = json.toByteArray()
                        val action = data["action"]
                        // Byte count is logged on every send: the media list is
                        // ~2KB and the per-message limit of this transport is
                        // still unknown, so this is how we find out whether big
                        // payloads are being rejected.
                        Log.i(DIAG, ">>> SEND $action (${payload.size} bytes)")
                        messageApi.sendMessage(nodeId, payload)
                            .addOnSuccessListener {
                                Log.i(DIAG, ">>> SEND ok: $action (${payload.size} bytes)")
                                result.success(true)
                            }
                            .addOnFailureListener { e ->
                                Log.e(DIAG, ">>> SEND FAILED: $action (${payload.size} bytes) ${describe(e)}")
                                result.error("SEND_FAIL", describe(e), null)
                            }
                    } else {
                        Log.w(DIAG, ">>> SEND skipped: data=${data != null} node=${nodeId != null}")
                        result.error("NO_WATCH", "Watch not linked", null)
                    }
                }
                "launchWearApp" -> {
                    val nodeId = watchNodeId
                    if (nodeId == null) {
                        result.error("NO_WATCH", "Watch not linked", null)
                    } else {
                        launchWearApp(nodeId) { ok, detail ->
                            result.success(mapOf("ok" to ok, "detail" to detail))
                        }
                    }
                }
                "getDiagnostics" -> result.success(lastReport)
                "isWatchConnected" -> result.success(watchNodeId != null)
                else -> result.notImplemented()
            }
        }

        // Phone media volume and screen brightness, for the two chips on the board.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.voice_counter/device").setMethodCallHandler { call, result ->
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "state" -> result.success(deviceState(am))
                // Role switch (board <-> camera): a fresh process, so the
                // services of the other role are not left in memory.
                "restartApp" -> {
                    result.success(true)
                    val intent = packageManager.getLaunchIntentForPackage(packageName)!!
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    window.decorView.postDelayed({
                        startActivity(intent)
                        android.os.Process.killProcess(android.os.Process.myPid())
                    }, 150)
                }
                "setVolumeMax" -> {
                    try {
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        // FLAG_SHOW_UI: the system slider shows, so it is clear what changed.
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, max, AudioManager.FLAG_SHOW_UI)
                    } catch (e: Exception) { Log.w(TAG, "setVolumeMax: ${e.message}") }
                    result.success(deviceState(am))
                }
                // Max brightness for this window only: no WRITE_SETTINGS
                // permission needed, and the phone's own setting is untouched.
                "setBrightnessMax" -> {
                    brightMax = call.argument<Boolean>("on") ?: false
                    val lp = window.attributes
                    lp.screenBrightness = windowBrightness()
                    window.attributes = lp
                    result.success(deviceState(am))
                }
                else -> result.notImplemented()
            }
        }

        // Corner camera (docs/camera-recording-requirements.md).
        val cam = CameraRecorder(this, flutterEngine.renderer) { e -> runOnUiThread { cameraSink?.success(e) } }
        camera = cam
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.voice_counter/camera").setMethodCallHandler { call, result ->
            if (call.method == "setDim") {
                dim = call.argument<Boolean>("on") ?: false
                val lp = window.attributes
                lp.screenBrightness = windowBrightness()
                window.attributes = lp
                result.success(true)
            } else {
                cam.handle(call, result)
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.voice_counter/camera_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) { cameraSink = events }
                override fun onCancel(args: Any?) { cameraSink = null }
            }
        )

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(args: Any?) { eventSink = null }
            }
        )
    }

    /**
     * Walks the handshake one step at a time and reports what each step
     * actually returned, instead of collapsing everything into a single
     * boolean the way this used to.
     *
     * Returns a report map rather than `true`. `ok` means the send path is
     * usable (we have a node); `listenerRegistered` separately says whether
     * the receive path came up. They are reported apart on purpose — the bug
     * being chased is exactly the case where one works and the other does not.
     */
    private fun initWearableConnect(result: MethodChannel.Result) {
        val report = mutableMapOf<String, Any?>(
            "ok" to false,
            "listenerRegistered" to false
        )
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)
        fun reply() {
            lastReport = report.toMap()
            // MethodChannel.Result throws if answered twice, and the chain
            // below has several possible exits.
            if (replied.compareAndSet(false, true)) result.success(report)
        }

        Log.i(DIAG, "======== initialize() ========")

        nodeApi.getConnectedNodes().addOnSuccessListener { nodes ->
            Log.i(DIAG, "getConnectedNodes -> ${nodes?.size ?: 0} node(s)")
            nodes?.forEachIndexed { i, n -> Log.i(DIAG, "    node[$i] id=${n.id} name=${n.name}") }

            if (nodes.isNullOrEmpty()) {
                Log.w(DIAG, "NO NODE — is the watch paired and Mi Fitness synced?")
                report["error"] = "NO_NODE"
                reply()
                return@addOnSuccessListener
            }
            val node = nodes[0]
            watchNodeId = node.id
            report["nodeId"] = node.id
            report["nodeName"] = node.name
            report["ok"] = true

            authApi.requestPermission(node.id, Permission.DEVICE_MANAGER)
                .addOnSuccessListener { granted ->
                    // The granted array is the actual answer. A success
                    // callback on its own does NOT mean DEVICE_MANAGER was
                    // given, and addListener needs DEVICE_MANAGER.
                    val names = granted?.map { it.name } ?: emptyList()
                    val hasDm = names.contains(Permission.DEVICE_MANAGER.name)
                    Log.i(DIAG, "requestPermission -> granted=$names  hasDeviceManager=$hasDm")
                    if (!hasDm) Log.w(DIAG, "DEVICE_MANAGER NOT granted — addListener is expected to fail")
                    report["granted"] = names
                    report["hasDeviceManager"] = hasDm

                    nodeApi.isWearAppInstalled(node.id)
                        .addOnSuccessListener { installed ->
                            Log.i(DIAG, "isWearAppInstalled -> $installed")
                            report["wearAppInstalled"] = installed
                            registerListener(node.id, report) {
                                // Fired after the listener is up: if the watch's
                                // channel only opens on a phone-started session,
                                // this is what starts it.
                                launchWearApp(node.id) { ok, detail ->
                                    report["launchWearApp"] = if (ok) "ok" else detail
                                    reply()
                                }
                            }
                        }
                        .addOnFailureListener { e ->
                            Log.w(DIAG, "isWearAppInstalled FAILED: ${describe(e)}")
                            report["wearAppInstalledError"] = describe(e)
                            registerListener(node.id, report) {
                                launchWearApp(node.id) { ok, detail ->
                                    report["launchWearApp"] = if (ok) "ok" else detail
                                    reply()
                                }
                            }
                        }
                }
                .addOnFailureListener { e ->
                    Log.e(DIAG, "requestPermission FAILED: ${describe(e)}")
                    report["error"] = "AUTH: ${describe(e)}"
                    reply()
                }
        }.addOnFailureListener { e ->
            Log.e(DIAG, "getConnectedNodes FAILED: ${describe(e)}")
            report["error"] = "SEARCH: ${describe(e)}"
            reply()
        }
    }

    /**
     * Asks the phone side to start the wear app over the SDK.
     *
     * Why this matters: the 2026-08-23 run showed addListener succeeding while
     * the watch still could not send — its getReadyState was 2, onopen never
     * fired once, and its own send() failed locally. So the watch's outbound
     * channel is never opening, and nothing in either app ever asks it to. The
     * leading theory is that the channel belongs to a session the *phone*
     * starts through launchWearApp, not to the user tapping the app icon on
     * the watch — which would also explain why inbound still works, since the
     * platform can push to the app without that session.
     *
     * Unverified. This call exists to test it.
     */
    private fun launchWearApp(nodeId: String, done: (Boolean, String) -> Unit) {
        val pkg = packageName
        Log.i(DIAG, "launchWearApp(node=$nodeId, pkg=$pkg) ...")
        nodeApi.launchWearApp(nodeId, pkg)
            .addOnSuccessListener {
                Log.i(DIAG, "launchWearApp OK — watch should report onopen if this is the missing step")
                done(true, "ok")
            }
            .addOnFailureListener { e ->
                Log.e(DIAG, "launchWearApp FAILED: ${describe(e)}")
                done(false, describe(e))
            }
    }

    /**
     * removeListener and addListener are independent async Tasks. Fired back
     * to back, the remove can land *after* the add and take out the listener
     * just registered — a silent, intermittent kill of the watch -> phone
     * direction. So the add only starts once the remove has settled, either
     * way: remove legitimately fails when nothing is registered yet.
     */
    private fun registerListener(
        nodeId: String,
        report: MutableMap<String, Any?>,
        reply: () -> Unit
    ) {
        val added = java.util.concurrent.atomic.AtomicBoolean(false)

        fun add() {
            if (!added.compareAndSet(false, true)) return
            messageApi.addListener(nodeId, messageListener)
                .addOnSuccessListener {
                    Log.i(DIAG, ">>> addListener OK — watch -> phone SHOULD work now")
                    report["listenerRegistered"] = true
                    reply()
                }
                .addOnFailureListener { e ->
                    Log.e(DIAG, ">>> addListener FAILED: ${describe(e)}")
                    Log.e(DIAG, ">>> watch -> phone WILL NOT WORK (phone -> watch still will)")
                    report["listenerRegistered"] = false
                    report["listenerError"] = describe(e)
                    reply()
                }
        }

        messageApi.removeListener(nodeId)
            .addOnSuccessListener {
                Log.i(DIAG, "removeListener settled: ok")
                add()
            }
            .addOnFailureListener { e ->
                Log.i(DIAG, "removeListener settled: ${describe(e)} (normal on first run)")
                add()
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CameraRecorder.PERMISSION_REQUEST) camera?.onPermissionsResult()
    }

    override fun onDestroy() {
        camera?.close()
        super.onDestroy()
        scope.cancel()
        watchNodeId?.let { try { messageApi.removeListener(it) } catch (e: Exception) {} }
    }
}
