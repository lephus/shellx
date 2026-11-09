import com.android.build.api.variant.HostTestBuilder
import java.util.Properties
import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// The version lives in shellx-android/version.properties, which release/mobile/android.sh (plan 3H) also reads.
val versionProperties = Properties().apply { rootProject.file("version.properties").inputStream().use { load(it) } }

fun versionProperty(key: String): String =
    versionProperties.getProperty(key)?.trim()?.takeIf { it.isNotEmpty() } ?: error("version.properties: missing $key")

android {
    namespace = "com.shellx.app"
    compileSdk = libs.versions.androidCompileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.shellx.prod"
        minSdk = libs.versions.androidMinSdk.get().toInt()
        targetSdk = libs.versions.androidTargetSdk.get().toInt()
        versionCode = versionProperty("VERSION_CODE").toInt()
        versionName = versionProperty("VERSION_NAME")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        generateLocaleConfig = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

androidComponents {
    // AGP 9 runs unit tests for the tested build type (debug) only. Release runs them too, so the identity tests
    // also check what ships: com.shellx.prod, "ShellX" and the version.
    beforeVariants(selector().withBuildType("release")) { variant ->
        variant.hostTests.getValue(HostTestBuilder.UNIT_TEST_TYPE).enable = true
    }
    // Debug is "ShellX Dev" (com.shellx.dev), so it installs next to the Google Play build "ShellX"
    // (com.shellx.prod). applicationIdSuffix cannot produce com.shellx.dev, and product flavors would add variants.
    // The name comes from src/debug/res/values/strings_android.xml.
    onVariants(selector().withBuildType("debug")) { variant -> variant.applicationId.set("com.shellx.dev") }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.activity.compose)
    testImplementation(libs.junit4)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.ext.junit)
}

tasks.withType<Test>().configureEach {
    maxHeapSize = "2g"
    testLogging {
        events("passed", "skipped", "failed")
        exceptionFormat = TestExceptionFormat.FULL
    }
}

configurations.configureEach {
    if (name == "runtimeClasspath" || name.endsWith("RuntimeClasspath")) resolutionStrategy.activateDependencyLocking()
}

// Firebase (push) needs both config files; Task 10 of plan 3A adds them. Until then push stays off.
if (file("src/debug/google-services.json").isFile && file("src/release/google-services.json").isFile) {
    apply(plugin = "com.google.gms.google-services")
}
