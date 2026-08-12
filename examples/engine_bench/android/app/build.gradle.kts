plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.thestage.engine_bench"
    compileSdk = 36

    // Genie: optional extra jni dir (Linux QAIRT sync or tarball unpack).
    // Default staging path from sync_qairt_android_genie_libs.sh is
    // src/main/jniLibs/arm64-v8a — no env needed. If you keep libs elsewhere:
    //   export QAIRT_ANDROID_JNI=/path/to/extra/jni
    sourceSets {
        getByName("main") {
            val extra = System.getenv("QAIRT_ANDROID_JNI")
            if (!extra.isNullOrBlank()) {
                jniLibs.srcDir(extra)
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.engine_bench"
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
    implementation(
        files("$pluginLibs/onnxruntime-genai-android.aar")
    )

    // Qualcomm QNN Runtime (signed skel libraries).
    implementation(
        "com.qualcomm.qti:qnn-runtime:2.42.0"
    )

    // TFLite (for litert mode)
    implementation(
        "com.google.ai.edge.litertlm:litertlm-android:0.9.0"
    )

    // Transitive deps of TheStageCore
    implementation("com.google.code.gson:gson:2.11.0")
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
