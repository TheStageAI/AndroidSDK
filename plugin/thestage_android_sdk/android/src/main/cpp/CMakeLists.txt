cmake_minimum_required(VERSION 3.22)
project(espeak_ng_jni LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# 16 KB page-size compliance (Google Play, 2025+).
# The AGP-default NDK (r27) still links 4 KB-aligned
# LOAD segments; force 16 KB so the bundled .so passes
# Play's alignment check. No-op on NDK r28+.
add_link_options(
    "-Wl,-z,max-page-size=16384"
    "-Wl,-z,common-page-size=16384")

# ------------------------------------------------------------------
# Source tree paths (cloned by setup_espeak_ng.sh)
# ------------------------------------------------------------------
set(THIRD_PARTY
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../third_party/espeak-ng-spm/Sources)
set(ESPEAK_REPO
    ${THIRD_PARTY}/libespeak-ng/_repo)

# Optional: espeak-ng is TTS-only. Apps that don't ship
# NeuTTS (e.g. voice_transcribe) can skip this entire
# build by leaving third_party/espeak-ng-spm absent —
# the plugin's Kotlin side catches the resulting
# UnsatisfiedLinkError and continues without the
# phonemizer. Run dist/scripts/setup_espeak_ng.sh +
# prepare_espeak_assets.sh when TTS is needed.
if(NOT EXISTS "${ESPEAK_REPO}/src/libespeak-ng/speech.c")
    message(STATUS
        "espeak-ng sources not found at ${ESPEAK_REPO} — "
        "skipping libespeak_ng_jni build (TTS phonemizer "
        "will be unavailable at runtime)")
    return()
endif()

# ------------------------------------------------------------------
# libucd  (static)
# ------------------------------------------------------------------
add_library(ucd STATIC
    ${ESPEAK_REPO}/src/ucd-tools/src/case.c
    ${ESPEAK_REPO}/src/ucd-tools/src/categories.c
    ${ESPEAK_REPO}/src/ucd-tools/src/ctype.c
    ${ESPEAK_REPO}/src/ucd-tools/src/proplist.c
    ${ESPEAK_REPO}/src/ucd-tools/src/scripts.c
    ${ESPEAK_REPO}/src/ucd-tools/src/tostring.c
)
set_property(TARGET ucd PROPERTY
    POSITION_INDEPENDENT_CODE ON)
target_include_directories(ucd PUBLIC
    ${ESPEAK_REPO}/src/ucd-tools/src/include)

# ------------------------------------------------------------------
# libsonic  (static)
# ------------------------------------------------------------------
add_library(sonic STATIC
    ${THIRD_PARTY}/libsonic/sonic.c
)
set_property(TARGET sonic PROPERTY
    POSITION_INDEPENDENT_CODE ON)
target_include_directories(sonic PUBLIC
    ${THIRD_PARTY}/libsonic/include)

# ------------------------------------------------------------------
# libespeak-ng  (static)
# ------------------------------------------------------------------
set(ESPEAK_SRC ${ESPEAK_REPO}/src/libespeak-ng)

add_library(espeak-ng STATIC
    ${ESPEAK_SRC}/common.c
    ${ESPEAK_SRC}/compiledata.c
    ${ESPEAK_SRC}/compiledict.c
    ${ESPEAK_SRC}/compilembrola.c
    ${ESPEAK_SRC}/dictionary.c
    ${ESPEAK_SRC}/encoding.c
    ${ESPEAK_SRC}/error.c
    ${ESPEAK_SRC}/espeak_api.c
    ${ESPEAK_SRC}/espeak_command.c
    ${ESPEAK_SRC}/event.c
    ${ESPEAK_SRC}/fifo.c
    ${ESPEAK_SRC}/ieee80.c
    ${ESPEAK_SRC}/intonation.c
    ${ESPEAK_SRC}/klatt.c
    ${ESPEAK_SRC}/langopts.c
    ${ESPEAK_SRC}/mbrowrap.c
    ${ESPEAK_SRC}/mnemonics.c
    ${ESPEAK_SRC}/numbers.c
    ${ESPEAK_SRC}/phoneme.c
    ${ESPEAK_SRC}/phonemelist.c
    ${ESPEAK_SRC}/readclause.c
    ${ESPEAK_SRC}/setlengths.c
    ${ESPEAK_SRC}/soundicon.c
    ${ESPEAK_SRC}/spect.c
    ${ESPEAK_SRC}/speech.c
    ${ESPEAK_SRC}/ssml.c
    ${ESPEAK_SRC}/synth_mbrola.c
    ${ESPEAK_SRC}/synthdata.c
    ${ESPEAK_SRC}/synthesize.c
    ${ESPEAK_SRC}/tr_languages.c
    ${ESPEAK_SRC}/translate.c
    ${ESPEAK_SRC}/translateword.c
    ${ESPEAK_SRC}/voices.c
    ${ESPEAK_SRC}/wavegen.c
)

set_property(TARGET espeak-ng PROPERTY
    POSITION_INDEPENDENT_CODE ON)

target_include_directories(espeak-ng PRIVATE
    # Our own config.h (Android-compatible, avoids
    # Apple-specific endian.h in the SPM wrapper)
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${ESPEAK_REPO}/src/include
    ${ESPEAK_REPO}/src/include/compat
)

target_compile_definitions(espeak-ng PRIVATE
    LIBESPEAK_NG_EXPORT=1
    # Overridden at runtime via
    # espeak_ng_InitializePath()
    PATH_ESPEAK_DATA="/data/local/tmp"
    N_PATH_HOME=1024
)

target_compile_options(espeak-ng PRIVATE
    -fvisibility=hidden
    -Wno-int-conversion
    -Wno-implicit-function-declaration
    -Wno-format
)

target_link_libraries(espeak-ng PRIVATE
    ucd sonic)

# ------------------------------------------------------------------
# JNI bridge  (shared lib bundled in APK)
# ------------------------------------------------------------------
add_library(espeak_ng_jni SHARED
    espeak_ng_jni.cpp
)

target_include_directories(espeak_ng_jni PRIVATE
    ${ESPEAK_REPO}/src/include)

target_link_libraries(espeak_ng_jni PRIVATE
    espeak-ng android log)
