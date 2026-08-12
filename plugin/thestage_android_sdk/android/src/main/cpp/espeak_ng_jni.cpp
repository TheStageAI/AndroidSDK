// ----------------------------------------------------------
// espeak_ng_jni.cpp
// JNI bridge for espeak-ng phonemization on Android.
// Mirrors the iOS EspeakPhonemizer C-interop layer.
// ----------------------------------------------------------

#include <jni.h>
#include <android/log.h>
#include <cstring>
#include <string>
#include <vector>
#include <cstdio>

#include <espeak-ng/speak_lib.h>
#include <espeak-ng/espeak_ng.h>

#define TAG "espeak_ng_jni"
#define LOGE(...) \
    __android_log_print( \
        ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ----------------------------------------------------------
// nativeInitialize
// ----------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_ai_thestage_thestage_1android_1sdk_EspeakNg_nativeInitialize(
    JNIEnv* env,
    jclass,
    jstring j_data_path,
    jstring j_language
) {
    const char* data_path =
        env->GetStringUTFChars(j_data_path, nullptr);
    const char* language =
        env->GetStringUTFChars(j_language, nullptr);

    espeak_ng_InitializePath(data_path);

    int result = espeak_Initialize(
        AUDIO_OUTPUT_SYNCHRONOUS, 0,
        data_path, 0
    );

    if (result <= 0) {
        LOGE("espeak_Initialize failed: %d",
            result);
        env->ReleaseStringUTFChars(
            j_data_path, data_path);
        env->ReleaseStringUTFChars(
            j_language, language);
        return JNI_FALSE;
    }

    espeak_SetVoiceByName(language);

    env->ReleaseStringUTFChars(
        j_data_path, data_path);
    env->ReleaseStringUTFChars(
        j_language, language);
    return JNI_TRUE;
}

// ----------------------------------------------------------
// nativeCompileData
//
// One-time phoneme data compilation, matching iOS
// bundle.m EspeakLib.ensureBundleInstalled().
// ----------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_ai_thestage_thestage_1android_1sdk_EspeakNg_nativeCompileData(
    JNIEnv* env,
    jclass,
    jstring j_data_root,
    jstring j_phsource_path,
    jstring j_dictsource_path
) {
    const char* data_root =
        env->GetStringUTFChars(j_data_root, nullptr);
    const char* phsource =
        env->GetStringUTFChars(
            j_phsource_path, nullptr);
    const char* dictsource =
        env->GetStringUTFChars(
            j_dictsource_path, nullptr);

    // Set the data path so compiled output goes
    // into <data_root>/espeak-ng-data/
    espeak_ng_InitializePath(data_root);

    // Redirect compile output to /dev/null
    FILE* null_out = fopen("/dev/null", "w");

    // Compile intonation data
    espeak_ng_STATUS status =
        espeak_ng_CompileIntonationPath(
            phsource, nullptr, null_out, nullptr);
    if (status != ENS_OK) {
        LOGE("CompileIntonation failed: %d",
            status);
        fclose(null_out);
        goto cleanup;
    }

    // Compile phoneme data at 22050 Hz
    status = espeak_ng_CompilePhonemeDataPath(
        22050, phsource, nullptr,
        null_out, nullptr);
    if (status != ENS_OK) {
        LOGE("CompilePhonemeData failed: %d",
            status);
        fclose(null_out);
        goto cleanup;
    }

    // Compile English dictionary
    {
        espeak_VOICE v;
        memset(&v, 0, sizeof(v));
        v.languages = "en";
        status = espeak_ng_SetVoiceByProperties(&v);
        if (status != ENS_OK) {
            LOGE("SetVoiceByProperties failed: %d",
                status);
            fclose(null_out);
            goto cleanup;
        }

        std::string dict_path =
            std::string(dictsource) + "/";
        status = espeak_ng_CompileDictionary(
            dict_path.c_str(), "en",
            null_out, 0, nullptr);
        if (status != ENS_OK) {
            LOGE("CompileDictionary(en) failed: %d",
                status);
            fclose(null_out);
            goto cleanup;
        }
    }

    fclose(null_out);
    env->ReleaseStringUTFChars(
        j_data_root, data_root);
    env->ReleaseStringUTFChars(
        j_phsource_path, phsource);
    env->ReleaseStringUTFChars(
        j_dictsource_path, dictsource);
    return JNI_TRUE;

cleanup:
    env->ReleaseStringUTFChars(
        j_data_root, data_root);
    env->ReleaseStringUTFChars(
        j_phsource_path, phsource);
    env->ReleaseStringUTFChars(
        j_dictsource_path, dictsource);
    return JNI_FALSE;
}

// ----------------------------------------------------------
// nativeTextToPhonemes
//
// Calls espeak_TextToPhonemes in a loop, matching
// iOS __phonemize_raw(). Flag 0x02 = IPA output
// with stress markers.
// ----------------------------------------------------------
extern "C" JNIEXPORT jstring JNICALL
Java_ai_thestage_thestage_1android_1sdk_EspeakNg_nativeTextToPhonemes(
    JNIEnv* env,
    jclass,
    jstring j_text
) {
    const char* text =
        env->GetStringUTFChars(j_text, nullptr);

    std::string result;
    const void* ptr = text;
    bool first = true;

    while (ptr != nullptr) {
        const char* byte_ptr =
            static_cast<const char*>(ptr);
        if (*byte_ptr == '\0') break;

        const char* phonemes =
            espeak_TextToPhonemes(
                &ptr,
                espeakCHARS_UTF8,
                0x02   // IPA + stress
            );
        if (phonemes == nullptr) break;

        // Trim whitespace from chunk
        std::string chunk(phonemes);
        size_t start = chunk.find_first_not_of(' ');
        size_t end = chunk.find_last_not_of(' ');
        if (start == std::string::npos) continue;
        chunk = chunk.substr(start, end - start + 1);

        if (!chunk.empty()) {
            if (!first) result += " ";
            result += chunk;
            first = false;
        }
    }

    env->ReleaseStringUTFChars(j_text, text);
    return env->NewStringUTF(result.c_str());
}

// ----------------------------------------------------------
// nativeSetVoice
// ----------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_ai_thestage_thestage_1android_1sdk_EspeakNg_nativeSetVoice(
    JNIEnv* env,
    jclass,
    jstring j_voice_name
) {
    const char* voice =
        env->GetStringUTFChars(j_voice_name, nullptr);
    espeak_SetVoiceByName(voice);
    env->ReleaseStringUTFChars(
        j_voice_name, voice);
    return JNI_TRUE;
}
