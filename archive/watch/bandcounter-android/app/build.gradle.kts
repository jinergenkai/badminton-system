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

    signingConfigs {
        // Kiểm tra an toàn trước khi lấy thuộc tính
        val keystorePath = if (project.hasProperty("KEYSTORE_PATH")) project.property("KEYSTORE_PATH").toString() else ""
        val keystoreFile = if (keystorePath.isNotEmpty()) file(keystorePath) else null

        if (keystoreFile != null && keystoreFile.exists()) {
            create("config") {
                storeFile = keystoreFile
                storePassword = project.property("KEYSTORE_PASS").toString()
                keyAlias = project.property("KEY_ALIAS").toString()
                keyPassword = project.property("KEY_PASS").toString()
            }
        }
    }

    buildTypes {
        debug {
            // Chỉ sử dụng signature nếu file tồn tại
            val config = signingConfigs.findByName("config")
            if (config != null) {
                signingConfig = config
            }
        }
        release {
            isMinifyEnabled = false
            val config = signingConfigs.findByName("config")
            if (config != null) {
                signingConfig = config
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    // Khai báo file AAR với đường dẫn đầy đủ từ projectDir
    implementation(files("${projectDir}/libs/xms-wearable-lib_1.4_release.aar"))
    
    val composeBom = platform("androidx.compose:compose-bom:2024.02.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.compose.ui:ui-tooling-preview")

    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
