plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.thestage.voice_agent"
    compileSdk = 36
    // Pin the NDK the bundled plugins (jni / sonic / espeak-ng) build
    // against — silences the AGP "plugin requires NDK 28.2" warning.
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.example.voice_agent"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig =
                signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl
                    .JvmTarget.JVM_17
            )
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    packaging {
        // TheStageCore.aar and onnxruntime-android.aar
        // both bundle native libs — pick the custom
        // QNN-enabled ones from TheStageCore.
        jniLibs.pickFirsts.add(
            "lib/arm64-v8a/libonnxruntime.so"
        )
        jniLibs.pickFirsts.add(
            "lib/arm64-v8a/libonnxruntime4j_jni.so"
        )
        jniLibs.pickFirsts.add(
            "lib/arm64-v8a/libc++_shared.so"
        )
    }
}

dependencies {
    // AARs live in the Flutter plugin (single source
    // of truth). scripts/setup.sh symlinks them there
    // once.
    val pluginLibs =
        "../../../../plugin/thestage_android_sdk/android/libs"

    implementation(files("$pluginLibs/TheStageCore.aar"))
    implementation(
        files("$pluginLibs/onnxruntime-android.aar")
    )

    // Qualcomm QNN Runtime (signed skel libraries).
    implementation(
        "com.qualcomm.qti:qnn-runtime:2.42.0"
    )

    // Transitive deps of TheStageCore
    implementation(
        "com.google.code.gson:gson:2.11.0"
    )
    implementation(
        "com.squareup.okhttp3:okhttp:4.12.0"
    )
    implementation(
        "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0"
    )
}

flutter {
    source = "../.."
}
