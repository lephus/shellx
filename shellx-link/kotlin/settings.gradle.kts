// ShellX Link for Kotlin/JVM (MIT License, see ../LICENSE). Included by shellx-android/.
pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenCentral()
    }
}
rootProject.name = "shellx-link-kotlin"
include(":link-core", ":link-account")
