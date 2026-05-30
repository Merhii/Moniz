allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val installedNdkVersion = "25.2.9519653"

fun Project.useInstalledNdkVersion() {
    extensions.findByType<com.android.build.gradle.BaseExtension>()?.ndkVersion = installedNdkVersion
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    if (state.executed) {
        useInstalledNdkVersion()
    } else {
        afterEvaluate {
            useInstalledNdkVersion()
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
