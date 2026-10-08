# Native code

`libnimbleclip_mp3.so` is the MP3 encoder behind **Save audio as MP3**. Android
decodes audio but has no MP3 encoder of its own, so the encoder is LAME.

- `lame/` is the `libmp3lame` directory of **LAME 3.100**, unmodified, plus
  `include/lame.h` and the release's `COPYING`. It comes from
  `lame-3.100.tar.gz` on <https://lame.sourceforge.io/>
  (SHA-256 `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`).
  The decoder part of LAME (`mpglib`) and the x86 assembly are not included.
- `config.h` stands in for what LAME's `configure` would generate.
- `mp3_encoder_jni.c` is the JNI layer used by `Mp3Encoder.kt`.

LAME is licensed under the GNU Library General Public License, version 2 or
later (`lame/COPYING`). It is built as a separate shared library, so it can be
replaced by a rebuilt one: `CMakeLists.txt` in this directory is the whole
build, and Gradle runs it as part of the app build.
