// Android-specific config.h for espeak-ng NDK build.
// Mirrors the SPM config.h but avoids Apple-specific
// headers (endian.h, speechPlayer.h) in that directory.

#define HAVE_MKSTEMP 1
#define USE_ASYNC 0
#define USE_KLATT 1
#define USE_LIBPCAUDIO 0
#define USE_LIBSONIC 1
#define USE_MBROLA 0
// Disabled — we only need phonemization, not
// audio synthesis. Avoids C++ speechPlayer dep.
#define USE_SPEECHPLAYER 0

#define PACKAGE_VERSION "1.52-dev"
