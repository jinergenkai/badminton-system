package com.example.voice_counter

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.google.android.gms.wearable.*
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val WATCH_CHANNEL = "com.voice_counter/watch"
    private val WATCH_EVENT_CHANNEL = "com.voice_counter/watch_events"
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private lateinit var messageClient: MessageClient
    private lateinit var nodeClient: NodeClient
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    companion object {
        private const val TAG = "MainActivity"
        private const val GAME_UPDATE_PATH = "/game-update"
        private const val GAME_RESET_PATH = "/game-reset"
        private const val GAME_WINNER_PATH = "/game-winner"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize Wearable clients
        messageClient = Wearable.getMessageClient(this)
        nodeClient = Wearable.getNodeClient(this)

        // Listen for messages from watch
        messageClient.addListener { messageEvent ->
            Log.d(TAG, "Message received from watch: ${messageEvent.path}")
            when (messageEvent.path) {
                "/watch-command" -> {
                    val command = String(messageEvent.data)
                    Log.d(TAG, "Watch command: $command")
                    eventSink?.success(mapOf("type" to "command", "data" to command))
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup MethodChannel for watch communication
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    Log.d(TAG, "Initializing watch connectivity")
                    result.success(true)
                }

                "sendMessage" -> {
                    val path = call.argument<String>("path")
                    val data = call.argument<Map<String, Any>>("data")

                    if (path != null && data != null) {
                        scope.launch {
                            sendMessageToWatch(path, data)
                        }
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing path or data", null)
                    }
                }

                "isWatchConnected" -> {
                    scope.launch {
                        val connected = isWatchConnected()
                        result.success(connected)
                    }
                }

                "getConnectedNodes" -> {
                    scope.launch {
                        val nodes = getConnectedNodes()
                        result.success(nodes)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Setup EventChannel for watch events
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_EVENT_CHANNEL)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                Log.d(TAG, "Watch event channel listener attached")
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                Log.d(TAG, "Watch event channel listener cancelled")
            }
        })
    }

    private suspend fun sendMessageToWatch(path: String, data: Map<String, Any>) = withContext(Dispatchers.IO) {
        try {
            val nodes = nodeClient.connectedNodes.await()
            Log.d(TAG, "Found ${nodes.size} connected nodes")

            val jsonData = JSONObject(data).toString()
            val bytes = jsonData.toByteArray()

            for (node in nodes) {
                if (node.isNearby) {
                    messageClient.sendMessage(node.id, path, bytes).await()
                    Log.d(TAG, "Message sent to watch ${node.displayName}: $path")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending message to watch", e)
        }
    }

    private suspend fun isWatchConnected(): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            val nodes = nodeClient.connectedNodes.await()
            nodes.any { it.isNearby }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking watch connection", e)
            false
        }
    }

    private suspend fun getConnectedNodes(): List<String> = withContext(Dispatchers.IO) {
        return@withContext try {
            val nodes = nodeClient.connectedNodes.await()
            nodes.filter { it.isNearby }.map { it.displayName }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting connected nodes", e)
            emptyList()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        messageClient.removeListener { }
    }
}
