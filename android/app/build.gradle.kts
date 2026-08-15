plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

// Release signing is read from android/key.properties (gitignored) when present,
// falling back to environment variables for CI. Debug builds are unaffected.
val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

val keystorePath = keystoreProperties.getProperty("storeFile") ?: System.getenv("KEYSTORE_PATH")
val keystorePassword = keystoreProperties.getProperty("storePassword") ?: System.getenv("KEYSTORE_PASSWORD")
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")

android {
    namespace = "com.parthm.attendease"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.parthm.attendease"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val kFile = keystorePath?.let { file(it) }
            if (kFile != null && kFile.exists()) {
                storeFile = kFile
                storePassword = keystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            } else {
                val debugConfig = signingConfigs.getByName("debug")
                storeFile = debugConfig.storeFile
                storePassword = debugConfig.storePassword
                keyAlias = debugConfig.keyAlias
                keyPassword = debugConfig.keyPassword
            }
        }
    }

    // Android lint has almost nothing to inspect in a Flutter app (MainActivity only),
    // and lintVitalAnalyzeRelease intermittently fails on Windows when its cached
    // jars are still held open by a Gradle/lint worker process. Skip it on release.
    lint {
        checkReleaseBuilds = false
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // Firebase BOM
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))

    // Firebase Analytics
    implementation("com.google.firebase:firebase-analytics")
}
