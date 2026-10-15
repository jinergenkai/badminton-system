// ============================================================
// ANDROID SIDE: MainActivity.kt (Kotlin + MethodChannel for Flutter)
// 
// Hoặc dùng trực tiếp native Android nếu không cần Flutter.
// File này là Android-native Kotlin, không phải Flutter Dart.
// Đặt ở: android/app/src/main/kotlin/com/hung/bandcounter/MainActivity.kt
// ============================================================

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
import com.xiaomi.xms.wearable.message.MessageClient
import com.xiaomi.xms.wearable.message.OnMessageReceivedListener
import com.xiaomi.xms.wearable.node.NodeClient
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

// ─── Shared state (singleton để MessageClient callback cập nhật) ─
object AppState {
    var scoreA by mutableStateOf(0)
    var scoreB by mutableStateOf(0)
    var connected by mutableStateOf(false)
    val eventLog = mutableStateListOf<ScoreEvent>()

    fun handleAction(action: String, rawScoreA: Int, rawScoreB: Int) {
        when (action) {
            "score_A" -> scoreA++
            "score_B" -> scoreB++
            "undo"    -> {
                // Undo logic: giảm điểm dựa trên score cao hơn score watch gửi
                // Đơn giản: so sánh với state hiện tại
                if (scoreA > 0 && rawScoreA < scoreA) scoreA--
                else if (scoreB > 0 && rawScoreB < scoreB) scoreB--
                // Hoặc đơn giản hơn: watch là source of truth, sync thẳng
                // scoreA = rawScoreA; scoreB = rawScoreB
            }
        }

        val fmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        eventLog.add(0, ScoreEvent(action, scoreA, scoreB, fmt.format(Date())))

        // Giữ log không quá dài
        if (eventLog.size > 50) eventLog.removeLast()
    }
}

// ─── Main Activity ───────────────────────────────────────────
class MainActivity : ComponentActivity() {

    private lateinit var messageClient: MessageClient
    private lateinit var nodeClient: NodeClient
    private val TAG = "BandCounter"

    // Listener nhận message từ watch
    private val messageListener = OnMessageReceivedListener { message ->
        Log.d(TAG, "Received raw: ${message.data}")
        try {
            val json = JSONObject(String(message.data))
            val action = json.getString("action")
            val rawScoreA = json.optInt("scoreA", AppState.scoreA)
            val rawScoreB = json.optInt("scoreB", AppState.scoreB)

            // Chạy trên main thread để update UI
            runOnUiThread {
                AppState.handleAction(action, rawScoreA, rawScoreB)
                Log.d(TAG, "Action: $action | A=${AppState.scoreA} B=${AppState.scoreB}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Parse error: ${e.message}")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Khởi tạo Xiaomi Wearable SDK
        messageClient = Wearable.getMessageClient(this)
        nodeClient = Wearable.getNodeClient(this)

        // Đăng ký nhận message từ watch
        // Package name "com.hung.bandcounter" phải khớp với manifest.json của watch app
        messageClient.addListener(messageListener)

        // Check xem có watch đang kết nối không
        nodeClient.connectedNodes.addOnSuccessListener { nodes ->
            AppState.connected = nodes.isNotEmpty()
            Log.d(TAG, "Connected nodes: ${nodes.size}")
        }

        setContent {
            BandCounterApp()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        messageClient.removeListener(messageListener)
    }
}

// ─── Compose UI ──────────────────────────────────────────────
@Composable
fun BandCounterApp() {
    val darkBg = Color(0xFF0D0D0D)
    val cardBg = Color(0xFF1A1A1A)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(darkBg)
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Header
        Text(
            text = "Band Counter",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            modifier = Modifier.padding(bottom = 4.dp)
        )

        // Connection status
        Text(
            text = if (AppState.connected) "● Watch connected" else "○ Watch not connected",
            fontSize = 12.sp,
            color = if (AppState.connected) Color(0xFF4CAF50) else Color(0xFF666666),
            modifier = Modifier.padding(bottom = 20.dp)
        )

        // Score display
        Row(
            horizontalArrangement = Arrangement.spacedBy(40.dp),
            modifier = Modifier.padding(bottom = 24.dp)
        ) {
            ScoreCard("A", AppState.scoreA, Color(0xFF1565C0))
            ScoreCard("B", AppState.scoreB, Color(0xFFB71C1C))
        }

        // Manual reset button
        OutlinedButton(
            onClick = {
                AppState.scoreA = 0
                AppState.scoreB = 0
                AppState.eventLog.clear()
            },
            modifier = Modifier.padding(bottom = 20.dp),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFF888888))
        ) {
            Text("Reset")
        }

        // Event log
        Text(
            text = "Event log",
            fontSize = 13.sp,
            color = Color(0xFF888888),
            modifier = Modifier
                .align(Alignment.Start)
                .padding(bottom = 8.dp)
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(cardBg, shape = MaterialTheme.shapes.medium)
                .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            if (AppState.eventLog.isEmpty()) {
                item {
                    Text(
                        text = "Waiting for events from watch...",
                        fontSize = 12.sp,
                        color = Color(0xFF444444),
                        modifier = Modifier.padding(8.dp)
                    )
                }
            } else {
                items(AppState.eventLog) { event ->
                    EventRow(event)
                }
            }
        }
    }
}

@Composable
fun ScoreCard(label: String, score: Int, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = label,
            fontSize = 16.sp,
            color = Color(0xFF888888),
            fontWeight = FontWeight.Bold
        )
        Text(
            text = score.toString(),
            fontSize = 56.sp,
            fontWeight = FontWeight.Bold,
            color = color
        )
    }
}

@Composable
fun EventRow(event: ScoreEvent) {
    val actionColor = when (event.action) {
        "score_A" -> Color(0xFF4FC3F7)
        "score_B" -> Color(0xFFEF9A9A)
        "undo"    -> Color(0xFFFFCC80)
        else      -> Color(0xFF888888)
    }
    val actionLabel = when (event.action) {
        "score_A" -> "+A"
        "score_B" -> "+B"
        "undo"    -> "↩ undo"
        else      -> event.action
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = actionLabel,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = actionColor,
            modifier = Modifier.width(60.dp)
        )
        Text(
            text = "${event.scoreA} – ${event.scoreB}",
            fontSize = 13.sp,
            color = Color.White,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = event.time,
            fontSize = 11.sp,
            color = Color(0xFF555555)
        )
    }
}
