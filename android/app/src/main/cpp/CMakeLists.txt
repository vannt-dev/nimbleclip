cmake_minimum_required(VERSION 3.22.1)

project(nimbleclip_mp3 C)

# libmp3lame (LAME 3.100, LGPL) built as its own shared library, with the small
# JNI layer Mp3Encoder.kt talks to. Only the encoder is built: mpglib, the
# decoder LAME can carry, is left out because Android decodes the source.
set(LAME_DIR ${CMAKE_CURRENT_SOURCE_DIR}/lame)

add_library(
  nimbleclip_mp3
  SHARED
  mp3_encoder_jni.c
  ${LAME_DIR}/VbrTag.c
  ${LAME_DIR}/bitstream.c
  ${LAME_DIR}/encoder.c
  ${LAME_DIR}/fft.c
  ${LAME_DIR}/gain_analysis.c
  ${LAME_DIR}/id3tag.c
  ${LAME_DIR}/lame.c
  ${LAME_DIR}/newmdct.c
  ${LAME_DIR}/presets.c
  ${LAME_DIR}/psymodel.c
  ${LAME_DIR}/quantize.c
  ${LAME_DIR}/quantize_pvt.c
  ${LAME_DIR}/reservoir.c
  ${LAME_DIR}/set_get.c
  ${LAME_DIR}/tables.c
  ${LAME_DIR}/takehiro.c
  ${LAME_DIR}/util.c
  ${LAME_DIR}/vbrquantize.c
  ${LAME_DIR}/version.c
)

target_include_directories(nimbleclip_mp3 PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${LAME_DIR})
target_compile_definitions(nimbleclip_mp3 PRIVATE HAVE_CONFIG_H)
# The vendored sources are 2017 C and are not ours to tidy.
target_compile_options(nimbleclip_mp3 PRIVATE -O2 -w)
target_link_libraries(nimbleclip_mp3 m)
