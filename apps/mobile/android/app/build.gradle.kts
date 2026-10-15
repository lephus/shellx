import java.util.Properties

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

    // Play upload key (release/mobile/README.md): the properties file named by
    // SHELLX_ANDROID_KEY_PROPERTIES, else android/key.properties (gitignored). Without one, a release
    // build is debug-signed so `flutter run --release` still works; the store script refuses that.
    val keyPropertiesFile = System.getenv("SHELLX_ANDROID_KEY_PROPERTIES")?.let(::file)
        ?: rootProject.file("key.properties")
    val uploadKey = keyPropertiesFile.takeIf { it.isFile }?.let { f ->
        Properties().apply { f.inputStream().use(::load) }
    }

    signingConfigs {
        if (uploadKey != null) {
            create("upload") {
                storeFile = file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (uploadKey != null) "upload" else "debug")
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
}
