plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "ai.thestage.thestage_android_sdk"
    compileSdk = 35

    defaultConfig {
        minSdk = 28
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                arguments +=
                    "-DANDROID_STL=c++_shared"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file(
                "src/main/cpp/CMakeLists.txt"
            )
        }
    }

    // libc++_shared.so is already bundled by the
    // SDK AAR (genie_neutts JNI). Exclude the copy
    // produced by our espeak-ng CMake build.
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "lib/arm64-v8a/libc++_shared.so",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            )
        }
    }
}

dependencies {
    // Library module cannot bundle local AARs. compileOnly = classpath for
    // Kotlin; app supplies all runtime AARs (app/build.gradle.kts).
    compileOnly(files("libs/TheStageCore.aar"))
    compileOnly("com.google.code.gson:gson:2.11.0")
    compileOnly(
        "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.1"
    )
    // Play AI-pack delivery (`aipack://` engines source in
    // the SDK). Maven dep, so unlike the local AARs the
    // plugin can carry it transitively — consumer apps
    // need no extra dependency.
    implementation(
        "com.google.android.play:ai-delivery:0.1.1-alpha01"
    )
    // Flutter embedding provided automatically by Flutter Gradle plugin
}
