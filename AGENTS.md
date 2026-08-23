# AI development quick start

This repository includes one canonical command for running every local check,
including the Android integration suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\check_all.ps1
```

Run that command directly from the repository root when the user asks to
verify, check, build, or test the source comprehensively. Do not run its
individual Dart, Flutter, Node, Web, fixture-server, or emulator steps first.
The script performs the full workflow itself and cleans up the fixture server.

Useful verification overrides:

```powershell
# Run desktop/Web gates without starting an Android emulator.
.\tool\check_all.ps1 -SkipAndroid

# Skip only the release Web build.
.\tool\check_all.ps1 -SkipWebBuild

# Select an emulator or an already connected Android device.
.\tool\check_all.ps1 -EmulatorId <emulator-name>
.\tool\check_all.ps1 -DeviceId <device-id>
```

For interactively opening or restarting the Android app, use the launcher:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_android_emulator.ps1
```

When the user asks to open, run, or restart the app on an emulator, run that
command directly from the repository root. Do not run `flutter devices`,
`flutter emulators`, `flutter doctor`, `flutter pub get`, or static analysis
first unless the launcher reports an error that requires diagnosis. Use the
all-in-one check command above for automated testing.

The launcher performs the routine work itself:

- reuses a connected Android emulator;
- otherwise starts the default `Aegis_API_34` emulator and waits for it;
- locates ADB through `android/local.properties` when it is not on `PATH`;
- force-stops the previous NimbleClip instance; and
- launches `flutter run --no-pub` on the selected emulator.

Useful overrides:

```powershell
# Choose another configured emulator.
.\tool\run_android_emulator.ps1 -EmulatorId <emulator-name>

# Choose an already connected Android emulator.
.\tool\run_android_emulator.ps1 -DeviceId <device-id>

# Do not force-stop the currently running app first.
.\tool\run_android_emulator.ps1 -KeepRunningApp

# Launch a release build.
.\tool\run_android_emulator.ps1 -Release
```

The command stays attached to `flutter run` so logs and hot-reload commands are
available. If startup appears stuck, stop the command once and run the same
launcher again; its default behavior closes the old app before relaunching.

When the master branding image changes, regenerate every platform asset with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\generate_app_icons.ps1
```

Do not resize individual launcher icons manually; the generator also enforces
opaque iOS icons and produces Android adaptive/round/themed icons and splash
assets.
