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

    packaging {
        jniLibs {
            // libdatastore_shared_counter.so reaches the bundle through
            // firebase-analytics -> firebase-common -> androidx.datastore, and is
            // the reason Play Console warns "Your app could crash on 16 KB
            // devices": it is compiled with NDK r20 (2019), whose linker has the
            // bug that warning is about. Every other native library in the
            // bundle is current — libflutter.so is r28c, libsqlite3.so is r29.
            //
            // Upgrading is not the fix. datastore-core 1.2.0 ships a copy built
            // with r20 while 1.1.7's is built with r25c, so the newer release
            // regressed and both versions are flagged. There is no good version
            // to move to.
            //
            // Dropping it is safe because nothing here loads it. The library
            // backs androidx.datastore.core.SharedCounter, which only
            // MultiProcessDataStoreFactory instantiates, and Firebase uses
            // single-process DataStore. Saves 51 KB per ABI as a side effect.
            //
            // If a future Firebase release switches to multi-process DataStore
            // this turns into an UnsatisfiedLinkError at runtime. Re-check when
            // bumping the Firebase BOM: if the .so is still built with an NDK
            // older than r27, keep the exclude; if it has been rebuilt with a
            // current one, delete this block instead.
            //
            //   llvm-readelf --notes <lib>.so | grep -A1 NT_ANDROID_TYPE_IDENT
            excludes += "**/libdatastore_shared_counter.so"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Firebase BOM
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))

    // Firebase Analytics.
    //
    // No Dart code logs events; this is here for the reports the SDK collects
    // on its own (app opens, screen views, retention) in the Firebase console.
    // Two consequences are easy to forget, and both are declared in Play
    // Console rather than being visible in this file:
    //
    //   * it pulls play-services-ads-identifier, which merges
    //     com.google.android.gms.permission.AD_ID into the manifest, so the
    //     Advertising ID declaration must answer "Yes" (purpose: Analytics);
    //   * Data safety must list Device or other IDs and App interactions,
    //     collected for Analytics.
    //
    // Removing this line reverses both, and would also make the "no analytics
    // SDKs" style of claim in store_listing/ and web/privacy-policy.html true
    // again. Do not drop it without updating those three places together.
    implementation("com.google.firebase:firebase-analytics")
}
