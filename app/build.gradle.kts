plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.wildfrontier.game"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.wildfrontier.game"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }
    signingConfigs {
        create("release") {
            storeFile = rootProject.file("keystore/wildfrontier-release.jks")
            storePassword = "wildfrontier"
            keyAlias = "wildfrontier"
            keyPassword = "wildfrontier"
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    androidResources { noCompress += listOf("bin", "wfa") }
    lint { abortOnError = false; checkReleaseBuilds = false }
}
dependencies {
    implementation(project(":engine"))
}
