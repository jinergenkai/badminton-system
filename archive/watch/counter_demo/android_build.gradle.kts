// app/build.gradle.kts
// ─────────────────────────────────────────────────────────────
// QUAN TRỌNG: applicationId phải là "com.hung.bandcounter"
// Phải khớp với package trong manifest.json của watch app
// ─────────────────────────────────────────────────────────────

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hung.bandcounter"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.hung.bandcounter"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.10"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // ─── Xiaomi Wearable SDK ───────────────────────────────────
    // SDK này KHÔNG có trên Maven Central.
    // Lấy từ 2 nguồn:
    //   1. Official: đăng ký tại https://iot.mi.com/ → download SDK
    //   2. Extracted: github.com/A5245/WatchSDK có sẵn .aar đã extract
    //      từ Mi Fitness APK (com.xiaomi.xms.wearable)
    //
    // Sau khi có file .aar, đặt vào thư mục app/libs/ rồi dùng:
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))

    // ─── Jetpack Compose UI ───────────────────────────────────
    val composeBom = platform("androidx.compose:compose-bom:2024.02.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.compose.ui:ui-tooling-preview")

    // ─── Core ─────────────────────────────────────────────────
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
}
