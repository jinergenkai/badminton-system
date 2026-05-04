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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(files("${projectDir}/libs/xms-wearable-lib_1.4_release.aar"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")
}
