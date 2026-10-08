/*
 * Build configuration for the vendored libmp3lame sources in lame/.
 *
 * LAME's own configure script is not run for Android; this file says what it
 * would have found with the NDK's clang and bionic. The sources themselves
 * are unmodified LAME 3.100.
 */
#ifndef NIMBLECLIP_LAME_CONFIG_H
#define NIMBLECLIP_LAME_CONFIG_H

#include <stdint.h>

#define STDC_HEADERS 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDINT_H 1
#define HAVE_STRCHR 1
#define HAVE_MEMCPY 1
#define PROTOTYPES 1
#define USE_FAST_LOG 1
#define PACKAGE "lame"
#define LAME_LIBRARY_BUILD 1

typedef float ieee754_float32_t;
typedef double ieee754_float64_t;

#endif
