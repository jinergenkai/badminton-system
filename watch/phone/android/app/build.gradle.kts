plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hung.bandcounter"
    compileSdk = 35 

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        // Lấy thông tin từ gradle.properties
        val keystorePath = if (project.hasProperty("KEYSTORE_PATH")) project.property("KEYSTORE_PATH").toString() else ""
        val keystoreFile = if (keystorePath.isNotEmpty()) file(keystorePath) else null

        if (keystoreFile != null && keystoreFile.exists()) {
            create("secureConfig") {
                storeFile = keystoreFile
                storePassword = project.property("KEYSTORE_PASS").toString()
                keyAlias = project.property("KEY_ALIAS").toString()
                keyPassword = project.property("KEY_PASS").toString()
            }
        }
    }

    defaultConfig {
        applicationId = "com.hung.bandcounter"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("debug") {
            // ÉP BUỘC dùng key thật ngay cả khi debug
            val config = signingConfigs.findByName("secureConfig")
            if (config != null) {
                signingConfig = config
                println("--- [BUILD] Using secureConfig for DEBUG build ---")
            }
        }
        getByName("release") {
            val config = signingConfigs.findByName("secureConfig")
            if (config != null) {
                signingConfig = config
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

// Voice clips added to audio_src/ are levelled into assets/audio/ before the
// assets are bundled (tools/normalize_voice.py; only new or changed files).
// Without python/ffmpeg on this machine it warns and the build carries on
// with the assets as they are.
val normalizeVoice = tasks.register("normalizeVoice") {
    doLast {
        val root = rootProject.projectDir.parentFile
        try {
            val p = ProcessBuilder("python", "tools/normalize_voice.py", "--changed")
                .directory(root)
                .redirectErrorStream(true)
                .start()
            val out = p.inputStream.bufferedReader().readText()
            if (p.waitFor() == 0) {
                println("--- [normalizeVoice] " + out.trim().lines().last())
            } else {
                logger.warn("normalizeVoice failed, assets used as they are:\n$out")
            }
        } catch (e: Exception) {
            logger.warn("normalizeVoice skipped (python not found): ${e.message}")
        }
    }
}
tasks.named("preBuild") { dependsOn(normalizeVoice) }
tasks.matching { it.name.startsWith("compileFlutterBuild") }.configureEach { dependsOn(normalizeVoice) }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(files("${projectDir}/libs/xms-wearable-lib_1.4_release.aar"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")
    // Corner camera: CameraX controls stabilisation, frame rate and bitrate,
    // which the Flutter camera plugin does not.
    val camerax = "1.4.1"
    implementation("androidx.camera:camera-core:$camerax")
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.camera:camera-video:$camerax")
    implementation("androidx.camera:camera-effects:$camerax")
}
