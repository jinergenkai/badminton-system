package com.hung.bandcounter

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.auth.AuthApi
import com.xiaomi.xms.wearable.auth.Permission
import com.xiaomi.xms.wearable.message.MessageApi
import com.xiaomi.xms.wearable.message.OnMessageReceivedListener
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi
import com.xiaomi.xms.wearable.tasks.OnFailureListener
import com.xiaomi.xms.wearable.tasks.OnSuccessListener
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ─── Data model ─────────────────────────────────────────────
data class ScoreEvent(
    val action: String,
    val scoreA: Int,
    val scoreB: Int,
    val time: String
)

// ─── Shared state ───────────────────────────────────────────
object AppState {
    var scoreA by mutableStateOf(0)
    var scoreB by mutableStateOf(0)
    var statusText by mutableStateOf("Initializing...")
    var isConnected by mutableStateOf(false)
    val eventLog = mutableStateListOf<ScoreEvent>()

    fun handleAction(action: String, rawScoreA: Int, rawScoreB: Int) {
        if (action != "sync") {
            scoreA = rawScoreA
            scoreB = rawScoreB
            val fmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
            eventLog.add(0, ScoreEvent(action, scoreA, scoreB, fmt.format(Date())))
            if (eventLog.size > 50) eventLog.removeLast()
        } else {
            // Chỉ là sync điểm, không log vào lịch sử trận đấu
            scoreA = rawScoreA
            scoreB = rawScoreB
        }
    }
}

// ─── Main Activity ───────────────────────────────────────────
class MainActivity : ComponentActivity() {

    private val TAG = "BandCounter"
    private lateinit var nodeApi: NodeApi
    private lateinit var messageApi: MessageApi
    private lateinit var authApi: AuthApi
    private var watchNodeId: String? = null

    private val messageListener = OnMessageReceivedListener { nodeId, message ->
        val raw = String(message)
        Log.d(TAG, "Received from $nodeId: $raw")
        try {
            val json = JSONObject(raw)
            val action = json.getString("action")
            
            runOnUiThread {
                if (action == "request_sync") {
                    sendSyncToWatch(nodeId, "sync")
                } else {
                    val sA = json.optInt("scoreA", AppState.scoreA)
                    val sB = json.optInt("scoreB", AppState.scoreB)
                    AppState.handleAction(action, sA, sB)
                    // Confirm ngược lại cho Watch
                    sendSyncToWatch(nodeId, "sync_confirm")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse error: ${e.message}")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            nodeApi = Wearable.getNodeApi(this)
            messageApi = Wearable.getMessageApi(this)
            authApi = Wearable.getAuthApi(this)
            initWearableConnect()
        } catch (e: Exception) {
            AppState.statusText = "SDK Error: ${e.message}"
        }
        setContent {
            BandCounterApp(
                onReconnect = { initWearableConnect() },
                onSync = { watchNodeId?.let { sendSyncToWatch(it, "manual_sync") } }
            )
        }
    }

    private fun sendSyncToWatch(nodeId: String, action: String) {
        try {
            val json = JSONObject().apply {
                put("action", action)
                put("scoreA", AppState.scoreA)
                put("scoreB", AppState.scoreB)
            }
            messageApi.sendMessage(nodeId, json.toString().toByteArray())
                .addOnSuccessListener { Log.d(TAG, "Sync sent: $action") }
        } catch (e: Exception) {
            Log.e(TAG, "sendSync error: ${e.message}")
        }
    }

    private fun initWearableConnect() {
        AppState.statusText = "Searching..."
        AppState.isConnected = false
        nodeApi.getConnectedNodes()
            .addOnSuccessListener { nodes ->
                if (nodes == null || nodes.isEmpty()) {
                    AppState.statusText = "○ No watch (Tap to retry)"
                    return@addOnSuccessListener
                }
                val node = nodes[0]
                watchNodeId = node.id
                authApi.requestPermission(node.id, Permission.DEVICE_MANAGER)
                    .addOnSuccessListener {
                        AppState.statusText = "● Linked: ${node.id}"
                        AppState.isConnected = true
                        messageApi.addListener(node.id, messageListener)
                        // Tự động sync khi vừa kết nối thành công
                        sendSyncToWatch(node.id, "init_sync")
                    }
                    .addOnFailureListener { AppState.statusText = "Auth Denied" }
            }
            .addOnFailureListener { AppState.statusText = "Search fail" }
    }

    override fun onDestroy() {
        super.onDestroy()
        watchNodeId?.let { try { messageApi.removeListener(it) } catch (e: Exception) {} }
    }
}

@Composable
fun BandCounterApp(onReconnect: () -> Unit, onSync: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().background(Color(0xFF0D0D0D)).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Band Counter Pro", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White)
        
        Surface(
            modifier = Modifier.padding(vertical = 12.dp).clickable { onReconnect() },
            color = Color(0xFF1A1A1A),
            shape = MaterialTheme.shapes.small
        ) {
            Text(
                AppState.statusText,
                fontSize = 12.sp,
                color = if (AppState.isConnected) Color(0xFF4CAF50) else Color(0xFFE57373),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
            )
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(40.dp),
            modifier = Modifier.padding(vertical = 20.dp)
        ) {
            ScoreCard("TEAM A", AppState.scoreA, Color(0xFF1E88E5))
            ScoreCard("TEAM B", AppState.scoreB, Color(0xFFEF5350))
        }

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Button(onClick = onReconnect, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF333333))) {
                Text("Reconnect")
            }
            Button(onClick = onSync, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1565C0))) {
                Text("Sync")
            }
            OutlinedButton(onClick = { AppState.scoreA = 0; AppState.scoreB = 0; AppState.eventLog.clear(); onSync() }) {
                Text("Reset")
            }
        }

        Spacer(Modifier.height(24.dp))
        Text("Match Log", fontSize = 14.sp, color = Color.Gray, modifier = Modifier.align(Alignment.Start).padding(bottom = 8.dp))

        LazyColumn(
            modifier = Modifier.fillMaxWidth().weight(1f).background(Color(0xFF141414), MaterialTheme.shapes.medium).padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(AppState.eventLog) { EventRow(it) }
        }
    }
}

@Composable
fun ScoreCard(label: String, score: Int, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Text(score.toString(), fontSize = 64.sp, fontWeight = FontWeight.Bold, color = color)
    }
}

@Composable
fun EventRow(event: ScoreEvent) {
    val (label, color) = when (event.action) {
        "score_A" -> "+A" to Color(0xFF64B5F6)
        "score_B" -> "+B" to Color(0xFFE57373)
        "undo"    -> "UNDO" to Color(0xFFFFB74D)
        else      -> event.action to Color.Gray
    }
    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = color, fontWeight = FontWeight.Bold, modifier = Modifier.width(50.dp))
        Text("${event.scoreA} - ${event.scoreB}", color = Color.White, fontSize = 16.sp)
        Text(event.time, color = Color(0xFF444444), fontSize = 11.sp)
    }
}
