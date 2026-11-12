plugins {
    id("org.jetbrains.kotlin.jvm")
    application
}
kotlin { jvmToolchain(21) }
val lwjglVersion = "3.3.4"
dependencies {
    implementation(project(":engine"))
    implementation("org.lwjgl:lwjgl:$lwjglVersion")
    implementation("org.lwjgl:lwjgl-egl:$lwjglVersion")
    implementation("org.lwjgl:lwjgl-opengles:$lwjglVersion")
    runtimeOnly("org.lwjgl:lwjgl:$lwjglVersion:natives-linux")
    runtimeOnly("org.lwjgl:lwjgl-opengles:$lwjglVersion:natives-linux")
}
application {
    mainClass.set("wildfrontier.desktop.HarnessKt")
    applicationDefaultJvmArgs = listOf("-Xmx2g")
}
tasks.named<JavaExec>("run") {
    workingDir = rootProject.projectDir
    environment("EGL_PLATFORM", "surfaceless")
    environment("LIBGL_ALWAYS_SOFTWARE", "1")
    environment("GALLIUM_DRIVER", "llvmpipe")
}
