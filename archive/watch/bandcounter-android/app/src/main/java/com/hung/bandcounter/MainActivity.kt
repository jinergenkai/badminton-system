package com.hung.bandcounter

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
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
    val eventLog = mutableStateListOf<ScoreEvent>()

    fun handleAction(action: String) {
        when (action) {
            "score_A" -> scoreA++
            "score_B" -> scoreB++
            "undo"    -> {
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
    private var watchNodeId: String? = null

    // Listener theo chuẩn SDK 1.4: (String, ByteArray)
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

        try {
            nodeApi = Wearable.getNodeApi(this)
            messageApi = Wearable.getMessageApi(this)

            // Bước 1: Tìm watch đang kết nối
            nodeApi.getConnectedNodes()
                .addOnSuccessListener(OnSuccessListener<List<Node>> { nodes ->
                    if (nodes == null || nodes.isEmpty()) {
                        AppState.statusText = "○ No watch connected"
                        return@OnSuccessListener
                    }

                    val node = nodes[0]
                    watchNodeId = node.id
                    AppState.statusText = "● Watch [${node.id}] connected"
                    Log.d(TAG, "Watch found: ${node.id}")

                    // Bước 2: Đăng ký nhận message
                    messageApi.addListener(node.id, messageListener)
                        .addOnSuccessListener(OnSuccessListener<Void> {
                            Log.d(TAG, "Listener registered for ${node.id}")
                        })
                        .addOnFailureListener(OnFailureListener { e ->
                            AppState.statusText = "Listener error: ${e.message}"
                        })
                })
                .addOnFailureListener(OnFailureListener { e ->
                    AppState.statusText = "Error: ${e.message}"
                })
        } catch (e: Exception) {
            Log.e(TAG, "Init error: ${e.message}")
            AppState.statusText = "SDK Init error"
        }

        setContent {
            BandCounterApp()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        watchNodeId?.let { nodeId ->
            try {
                messageApi.removeListener(nodeId)
            } catch (e: Exception) {
                Log.e(TAG, "Remove listener error: ${e.message}")
            }
        }
    }
}

@Composable
fun BandCounterApp() {
    Column(
        modifier = Modifier.fillMaxSize().background(Color(0xFF0D0D0D)).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Band Counter", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Text(
            AppState.statusText,
            fontSize = 12.sp,
            color = if (AppState.statusText.startsWith("●")) Color(0xFF4CAF50) else Color(0xFF666666),
            modifier = Modifier.padding(vertical = 10.dp)
        )

        Row(horizontalArrangement = Arrangement.spacedBy(40.dp)) {
            ScoreCard("A", AppState.scoreA, Color(0xFF1565C0))
            ScoreCard("B", AppState.scoreB, Color(0xFFB71C1C))
        }

        Spacer(Modifier.height(20.dp))

        Button(onClick = { AppState.scoreA = 0; AppState.scoreB = 0; AppState.eventLog.clear() }) {
            Text("Reset")
        }

        LazyColumn(
            modifier = Modifier.fillMaxWidth().weight(1f).padding(top = 20.dp).background(Color(0xFF1A1A1A)),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(AppState.eventLog) { event ->
                EventRow(event)
            }
        }
    }
}

@Composable
fun ScoreCard(label: String, score: Int, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = Color.Gray, fontSize = 16.sp)
        Text(score.toString(), fontSize = 56.sp, fontWeight = FontWeight.Bold, color = color)
    }
}

@Composable
fun EventRow(event: ScoreEvent) {
    val (label, color) = when (event.action) {
        "score_A" -> "+A" to Color(0xFF4FC3F7)
        "score_B" -> "+B" to Color(0xFFEF9A9A)
        "undo"    -> "↩ undo" to Color(0xFFFFCC80)
        else      -> event.action to Color.Gray
    }
    Row(modifier = Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = color, fontWeight = FontWeight.Bold)
        Text("${event.scoreA} - ${event.scoreB}", color = Color.White)
        Text(event.time, color = Color.Gray, fontSize = 10.sp)
    }
}
