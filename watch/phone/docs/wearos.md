Check the current state of Wear OS integration in this project and report back.

Do these checks in order, output as a structured report:

## 1. Module structure

- List all modules in `android/` directory
- Identify if there's a `wear/` module or similar
- Check `settings.gradle` / `settings.gradle.kts` for included modules

## 2. Wear module configuration (if exists)

- Read `android/wear/build.gradle(.kts)` and report:
  - `minSdk`, `targetSdk`, `compileSdk`
  - Dependencies related to Wear OS (look for `play-services-wearable`, `wear-compose`, `wear-tooling`, `androidx.wear.*`)
  - Whether it's configured as standalone (`wearApp true` or manifest `com.google.android.wearable.standalone`)

## 3. Manifest check

- Read `android/wear/src/main/AndroidManifest.xml`
- Report: permissions, activities, services, meta-data tags
- Specifically flag if `WearableListenerService` is declared

## 4. Phone-side Wear integration

- Search `android/app/` for:
  - `WearableListenerService` subclasses
  - `MessageClient` / `DataClient` usages
  - MethodChannel names related to watch/wear/score
- Search `lib/` (Flutter Dart code) for MethodChannel usages that might connect to wear

## 5. Existing watch UI

- If `wear/` exists, list all `.kt` files in `android/wear/src/main/java/` (or kotlin/)
- For each file, 1-line summary of what it does
- Specifically report the main Activity composable — what UI elements exist?

## 6. Gaps vs target

Target architecture: watch has 5 buttons (team1 +/-, team2 +/-, undo) + score display. Phone is source of truth, sends score updates to watch via Wearable Data Layer.

Report what's MISSING to reach this target. Don't write code yet — just a checklist.

## 7. Build & deploy readiness

- Check if `flutter run` would deploy the wear module (it won't, but confirm by looking at how wear module is declared)
- Suggest the correct deploy command for the wear module (e.g., `./gradlew :wear:installDebug` or Android Studio run config name)

Output format: markdown with headings matching the sections above. Be concise, no code yet.
