import com.android.build.api.variant.HostTestBuilder
import java.util.Properties
import org.gradle.api.artifacts.dsl.LockMode
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
        // The relay override (3C's ShellXEndpoints.of, ledger A-6): empty in release builds.
        buildConfigField("String", "SHELLX_API_BASE", "\"\"")
    }

    buildTypes {
        debug {
            // `-PshellxApiBase=http://127.0.0.1:<port>` points a debug build at a relay on this Mac (adb reverse).
            val apiBase = providers.gradleProperty("shellxApiBase").getOrElse("")
            require(!apiBase.contains('"') && !apiBase.contains('\\')) { "shellxApiBase must not contain quotes or backslashes" }
            buildConfigField("String", "SHELLX_API_BASE", "\"$apiBase\"")
        }
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
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    implementation(libs.googleid)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.zxing.core)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.junit4)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.androidx.test.ext.junit)
    testDebugImplementation(libs.roborazzi)
    testDebugImplementation(libs.roborazzi.compose)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}

tasks.withType<Test>().configureEach {
    maxHeapSize = "2g"
    // Render tests (app/src/testDebug/.../screenshots) write PNGs; Roborazzi runs without its Gradle plugin, in
    // record mode. `dev.sh screenshots record <dir>` passes -Pshellx.snapshot.dir.
    systemProperty("roborazzi.test.record", "true")
    systemProperty(
        "shellx.snapshot.dir",
        providers.gradleProperty("shellx.snapshot.dir")
            .getOrElse(layout.buildDirectory.dir("shellx-snapshots").get().asFile.absolutePath),
    )
    testLogging {
        events("passed", "skipped", "failed")
        exceptionFormat = TestExceptionFormat.FULL
    }
}

configurations.configureEach {
    if (name == "runtimeClasspath" || name.endsWith("RuntimeClasspath")) resolutionStrategy.activateDependencyLocking()
}

dependencyLocking {
    // An unlocked runtime classpath fails instead of resolving freely (scripts/shellx/check-android-license.sh).
    lockMode.set(LockMode.STRICT)
}

// Firebase (push): both build types share com.shellx.prod, so one app/google-services.json serves both.
if (file("google-services.json").isFile) {
    apply(plugin = "com.google.gms.google-services")
}
