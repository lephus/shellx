plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.shellx.prod"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (V2-2b B9) needs core-library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.shellx.prod"
        // Spec §3.1: Android 8.0 (API 26)+.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing is configured by the store release process.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LaunchTheme/NormalTheme use Theme.AppCompat parents: local_auth's BiometricPrompt
    // crashes on Android 8 with a non-AppCompat launch theme.
    implementation("androidx.appcompat:appcompat:1.7.1")
    // flutter_local_notifications 22.3.2 (V2-2b B9): java.time on Android 8.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
