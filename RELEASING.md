# Releasing NimbleClip

Releases are created automatically after a version-bump commit reaches `main`
and every CI job succeeds. The release workflow builds a signed Android APK and
a Web archive, verifies the artifacts, creates the matching semantic version
tag, generates SHA-256 checksums, and attaches everything to a GitHub Release.

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

No manual tag is required. CI compares the release version with the previous
`main` revision. If the semantic version increased, the changelog contains a
non-empty matching section, and the tag does not already exist, publishing
starts only after all normal CI jobs pass. If publishing is interrupted before
the tag is created, the next successful `main` push retries the pending release.

The `Release` workflow rejects malformed or decreasing versions, version/tag
mismatches, missing release notes or signing secrets, failed checks, and
debug-signed APKs. A matching tag can still trigger the workflow directly, and
an existing tag can be rerun from the workflow's manual dispatch form.
