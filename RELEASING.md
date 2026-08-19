# Releasing NimbleClip

Releases are created by GitHub Actions when a semantic version tag is pushed.
The workflow validates the source, builds a signed Android APK and a Web
archive, generates SHA-256 checksums, and attaches them to a GitHub Release.

## One-time repository setup

Run the setup script from PowerShell. It creates the Android upload key and its
recovery credentials under the Git-ignored `dist/release` directory, then
configures the required GitHub Actions secrets:

```powershell
.\tool\setup_android_signing.ps1
```

Add `-VerifyBuild` to also build a release APK locally, verify its certificate,
and remove the temporary `android/key.properties` file afterward.

The configured secrets are:

- `ANDROID_KEYSTORE_BASE64`: the keystore file encoded as a single Base64 line
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

Keep the keystore and passwords backed up securely. Future APK updates must be
signed with the same key. The ignored files in `dist/release` are the local
source of truth; rerunning the script reuses them instead of rotating the key.

## Create a release

1. Update `version` in `pubspec.yaml`. The part before `+` must match the tag.
2. Move the release notes from `Unreleased` into a new `## [X.Y.Z]` section in
   `CHANGELOG.md`.
3. Commit and push the changes after all local checks pass.
4. Create and push the matching tag:

   ```bash
   git tag -a v1.1.0 -m "NimbleClip 1.1.0"
   git push origin v1.1.0
   ```

The `Release` workflow rejects malformed tags, version mismatches, missing
release notes, missing signing secrets, failed checks, and debug-signed APKs.
An existing tag can also be rerun from the workflow's manual dispatch form.
