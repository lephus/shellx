import org.gradle.api.artifacts.dsl.LockMode
import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    `java-library`
    alias(libs.plugins.kotlin.jvm)
}

group = "com.shellx.link"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    api(project(":link-core"))
    api(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    testImplementation(kotlin("test"))
    testImplementation(libs.okhttp.mockwebserver3)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    // The vectors live outside this build (contracts §5), so a test run is never up to date.
    outputs.upToDateWhen { false }
}

tasks.withType<Test>().configureEach {
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
