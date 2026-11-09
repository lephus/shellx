// The ShellX Android app (closed source, see LICENSE). Includes ShellX Link for Kotlin (MIT).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "shellx-android"
includeBuild("../shellx-link/kotlin")
include(":core", ":app")
