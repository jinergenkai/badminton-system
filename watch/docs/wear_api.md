package com.hung.bandcounter

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout._
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3._
import androidx.compose.runtime.\*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.xiaomi.xms.wearable.Wearable
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

// ─── Shared UI state ────────────────────────────────────────
object AppState {
var scoreA by mutableStateOf(0)
var scoreB by mutableStateOf(0)
var statusText by mutableStateOf("Initializing...")
val eventLog = mutableStateListOf<ScoreEvent>()

    fun handleAction(action: String) {
        when (action) {
            "score_A" -> scoreA++
            "score_B" -> scoreB++
            "undo" -> {
                // Simple: undo điểm vừa ghi gần nhất
                val last = eventLog.firstOrNull()
                when (last?.action) {
                    "score_A" -> if (scoreA > 0) scoreA--
                    "score_B" -> if (scoreB > 0) scoreB--
                }
            }
        }
        val fmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        eventLog.add(0, ScoreEvent(action, scoreA, scoreB, fmt.format(Date())))
        if (eventLog.size > 50) eventLog.removeLast()
    }

}

// ─── Main Activity ───────────────────────────────────────────
class MainActivity : ComponentActivity() {

    private val TAG = "BandCounter"
    private lateinit var nodeApi: NodeApi
    private lateinit var messageApi: MessageApi

    // nodeId của watch — lấy từ getConnectedNodes()
    private var watchNodeId: String? = null

    private val messageListener = OnMessageReceivedListener { nodeId, message ->
        val raw = String(message)
        Log.d(TAG, "Received from $nodeId: $raw")
        try {
            val json = JSONObject(raw)
            val action = json.getString("action")
            runOnUiThread {
                AppState.handleAction(action)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse error: ${e.message}")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        nodeApi = Wearable.getNodeApi(this)
        messageApi = Wearable.getMessageApi(this)

        // Bước 1: Tìm watch đang kết nối
        nodeApi.getConnectedNodes()
            .addOnSuccessListener(OnSuccessListener<List<Node>> { nodes ->
                if (nodes.isEmpty()) {
                    AppState.statusText = "○ No watch connected"
                    Log.w(TAG, "No connected nodes found")
                    return@OnSuccessListener
                }

                // Lấy node đầu tiên (thường chỉ có 1 watch)
                val node = nodes[0]
                watchNodeId = node.id
                AppState.statusText = "● ${node.displayName} connected"
                Log.d(TAG, "Watch found: ${node.displayName} [${node.id}]")

                // Bước 2: Đăng ký nhận message từ nodeId này
                messageApi.addListener(node.id, messageListener)
                    .addOnSuccessListener(OnSuccessListener<Void> {
                        Log.d(TAG, "Message listener registered for ${node.id}")
                    })
                    .addOnFailureListener(OnFailureListener { e ->
                        Log.e(TAG, "Failed to register listener: ${e.message}")
                        AppState.statusText = "Listener error: ${e.message}"
                    })
            })
            .addOnFailureListener(OnFailureListener { e ->
                AppState.statusText = "Error: ${e.message}"
                Log.e(TAG, "getConnectedNodes failed: ${e.message}")
            })

        setContent { BandCounterApp() }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Cleanup: remove listener khi activity bị destroy
        watchNodeId?.let { nodeId ->
            messageApi.removeListener(nodeId)
                .addOnSuccessListener(OnSuccessListener<Void> {
                    Log.d(TAG, "Listener removed")
                })
        }
    }

}

// ─── Compose UI ──────────────────────────────────────────────
@Composable
fun BandCounterApp() {
Column(
modifier = Modifier
.fillMaxSize()
.background(Color(0xFF0D0D0D))
.padding(20.dp),
horizontalAlignment = Alignment.CenterHorizontally
) {
Text(
"Band Counter",
fontSize = 22.sp,
fontWeight = FontWeight.Bold,
color = Color.White,
modifier = Modifier.padding(bottom = 4.dp)
)

        Text(
            AppState.statusText,
            fontSize = 12.sp,
            color = if (AppState.statusText.startsWith("●"))
                Color(0xFF4CAF50) else Color(0xFF666666),
            modifier = Modifier.padding(bottom = 20.dp)
        )

        // Score
        Row(
            horizontalArrangement = Arrangement.spacedBy(40.dp),
            modifier = Modifier.padding(bottom = 24.dp)
        ) {
            ScoreCard("A", AppState.scoreA, Color(0xFF1565C0))
            ScoreCard("B", AppState.scoreB, Color(0xFFB71C1C))
        }

        OutlinedButton(
            onClick = {
                AppState.scoreA = 0
                AppState.scoreB = 0
                AppState.eventLog.clear()
            },
            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFF888888)),
            modifier = Modifier.padding(bottom = 20.dp)
        ) { Text("Reset") }

        // Event log
        Text(
            "Event log",
            fontSize = 13.sp,
            color = Color(0xFF888888),
            modifier = Modifier.align(Alignment.Start).padding(bottom = 8.dp)
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(Color(0xFF1A1A1A), MaterialTheme.shapes.medium)
                .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            if (AppState.eventLog.isEmpty()) {
                item {
                    Text(
                        "Waiting for events from watch...",
                        fontSize = 12.sp,
                        color = Color(0xFF444444),
                        modifier = Modifier.padding(8.dp)
                    )
                }
            } else {
                items(AppState.eventLog) { EventRow(it) }
            }
        }
    }

}

@Composable
fun ScoreCard(label: String, score: Int, color: Color) {
Column(horizontalAlignment = Alignment.CenterHorizontally) {
Text(label, fontSize = 16.sp, color = Color(0xFF888888), fontWeight = FontWeight.Bold)
Text(score.toString(), fontSize = 56.sp, fontWeight = FontWeight.Bold, color = color)
}
}

@Composable
fun EventRow(event: ScoreEvent) {
val (label, color) = when (event.action) {
"score_A" -> "+A" to Color(0xFF4FC3F7)
"score_B" -> "+B" to Color(0xFFEF9A9A)
"undo" -> "↩" to Color(0xFFFFCC80)
else -> event.action to Color(0xFF888888)
}
Row(
modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 2.dp),
horizontalArrangement = Arrangement.SpaceBetween,
verticalAlignment = Alignment.CenterVertically
) {
Text(label, fontSize = 14.sp, fontWeight = FontWeight.Bold,
color = color, modifier = Modifier.width(40.dp))
Text("${event.scoreA} – ${event.scoreB}", fontSize = 13.sp,
color = Color.White, modifier = Modifier.weight(1f))
Text(event.time, fontSize = 11.sp, color = Color(0xFF555555))
}
}
