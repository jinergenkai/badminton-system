Extend the existing Wear OS integration. Current state:

- Watch UI exists (lib/views/watch/watch_score_screen.dart) but is display-only
- Phone → Watch score sync already works via MessageClient
- Watch → Phone command path is NOT implemented
- MethodChannel "com.voice_counter/watch" is already set up

Scope of this task: enable the watch to send commands to the phone, and make the phone react to them. Keep Flutter-only architecture (do NOT create a native :wear module). Keep MessageClient (do NOT migrate to DataClient).

## Task 1 — Add buttons to watch UI

File: lib/views/watch/watch_score_screen.dart

Add 5 touch targets to the existing layout:

- Team A "+" button
- Team A "-" button
- Team B "+" button
- Team B "-" button
- Undo button (center, smaller)

Layout requirements:

- Must work on ROUND display (Galaxy Watch 7, 432x432)
- Use WatchShape builder already present
- Buttons should be large (minimum 56dp touch target per Wear OS guidelines)
- Keep score display visible — buttons should not cover it
- Suggested layout: team A score + buttons on left half, team B on right half, undo at bottom center
- Add haptic feedback on tap (HapticFeedback.mediumImpact())
- Buttons should work in AmbientMode = false only; when ambient, show only scores (no buttons)

## Task 2 — Send commands from watch to phone

Use the existing watch_connectivity_service.dart bridge. If it does not yet expose a sendCommand method, add one:

```dart
Future<void> sendCommand(String command) // e.g., "team1_add", "team1_sub", "team2_add", "team2_sub", "undo"
```

On the native side (MainActivity.kt on the WATCH side — or if watch uses same MainActivity, add a handler), use MessageClient.sendMessage with path "/watch-command" and payload = command string bytes.

The PHONE side already listens on "/watch-command" and forwards to Flutter via EventChannel — do not modify that.

## Task 3 — Phone reacts to watch commands

File: lib/controllers/score_controller.dart

It currently sends score TO watch but ignores the incoming stream. Fix this:

1. In controller init, subscribe to watchConnectivityService.watchCommandStream
2. On each command, route to the appropriate existing method:
   - "team1_add" → incrementTeam1() (or whatever the existing method is named)
   - "team1_sub" → decrementTeam1()
   - "team2_add" → incrementTeam2()
   - "team2_sub" → decrementTeam2()
   - "undo" → undo()
3. Make sure the subscription is cancelled on dispose
4. After handling the command, the existing auto-sync will push the new score back to watch — verify this flow, don't duplicate it

## Task 4 — Verify deployment flow

Do NOT create a :wear module. Current deploy flow stays:

- Phone: `flutter run -d <phone-id>`
- Watch: `flutter run -t lib/main_watch.dart -d <watch-id>`

Check pubspec.yaml has the correct entry points. If `main_watch.dart` needs a separate flavor or entry declaration, add it.

## Constraints

- Do NOT migrate MessageClient to DataClient
- Do NOT create android/wear module
- Do NOT refactor existing working code (phone → watch sync, MethodChannel setup)
- Keep changes minimal and focused on the 3 tasks above
- Use existing naming conventions in the codebase

## Deliverables

1. Modified watch_score_screen.dart with buttons
2. Modified/extended watch_connectivity_service.dart with sendCommand
3. Modified score_controller.dart with command subscription
4. Any MainActivity.kt change needed for the watch-side sendMessage
5. Short summary at the end: what files changed, what to test manually

Start by reading the 3 files mentioned above, then propose the minimal diff before writing code.
