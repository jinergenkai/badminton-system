package com.hung.bandcounter

import android.os.Bundle
import android.util.Log
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

    companion object {
        private const val TAG = "MainActivity"
    }

    private val messageListener = OnMessageReceivedListener { nodeId, message ->
        val raw = String(message)
        Log.d(TAG, "RAW From Watch: $raw")
        try {
            val json = JSONObject(raw)
            val action = json.getString("action")
            val sA = json.optInt("scoreA", -1)
            val sB = json.optInt("scoreB", -1)
            val silent = json.optBoolean("silent", false)
            val reset = json.optBoolean("reset", false)

            scope.launch(Dispatchers.Main) {
                eventSink?.success(mapOf(
                    "type" to "command",
                    "action" to action,
                    "scoreA" to sA,
                    "scoreB" to sB,
                    "silent" to silent,
                    "reset" to reset
                ))
            }
        } catch (e: Exception) { Log.e(TAG, "Parse error: ${e.message}") }
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
                "sendMessage" -> {
                    val data = call.argument<Map<String, Any>>("data")
                    if (data != null && watchNodeId != null) {
                        val payload = JSONObject(data).toString().toByteArray()
                        messageApi.sendMessage(watchNodeId!!, payload)
                            .addOnSuccessListener { result.success(true) }
                            .addOnFailureListener { e -> result.error("SEND_FAIL", e.message, null) }
                    } else { result.error("NO_WATCH", "Watch not linked", null) }
                }
                "isWatchConnected" -> result.success(watchNodeId != null)
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(args: Any?) { eventSink = null }
            }
        )
    }

    private fun initWearableConnect(result: MethodChannel.Result) {
        nodeApi.getConnectedNodes().addOnSuccessListener { nodes ->
            if (nodes.isNullOrEmpty()) {
                Log.w(TAG, "No nodes found")
                result.error("NODE_NOT_FOUND", "Ensure watch is connected in Mi Fitness", null)
                return@addOnSuccessListener
            }
            val node = nodes[0]
            watchNodeId = node.id
            Log.d(TAG, "Node found: ${node.id}, requesting permission...")

            authApi.requestPermission(node.id, Permission.DEVICE_MANAGER).addOnSuccessListener {
                Log.d(TAG, "Auth Success")
                messageApi.removeListener(node.id)
                messageApi.addListener(node.id, messageListener)
                result.success(true)
            }.addOnFailureListener { e ->
                Log.e(TAG, "Auth Fail: ${e.message}")
                result.error("AUTH_DENIED", e.message, null)
            }
        }.addOnFailureListener { e ->
            Log.e(TAG, "Search Fail: ${e.message}")
            result.error("SEARCH_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        watchNodeId?.let { try { messageApi.removeListener(it) } catch (e: Exception) {} }
    }
}
