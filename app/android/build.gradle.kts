allprojects {
    repositories {
        google()
        mavenCentral()
    }
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
// Một số plugin (vd flutter_blue_plus 1.34.5) hard-code compileSdk cũ,
// không tương thích với các thư viện AndroidX mới. Ép tối thiểu lên 36.
fun Project.forceMinCompileSdk(min: Int) {
    val androidExt = extensions.findByName("android")
    if (androidExt is com.android.build.gradle.BaseExtension) {
        val current = androidExt.compileSdkVersion
            ?.removePrefix("android-")
            ?.toIntOrNull() ?: 0
        if (current < min) {
            androidExt.compileSdkVersion(min)
        }
    }
}

subprojects {
    if (state.executed) forceMinCompileSdk(36) else afterEvaluate { forceMinCompileSdk(36) }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
