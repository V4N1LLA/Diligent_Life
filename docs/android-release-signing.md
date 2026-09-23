# Android release signing

Release version: `1.0.0+12`. App logic and database formats are unchanged.

## Local configuration

The production keystore is outside Git at
`%USERPROFILE%/.diligent-life/signing/release.jks` (RSA 3072, alias
`diligent-life-release`, validity 10,000 days). Its randomly generated password
is stored in the private `key.properties` beside it and in the ignored local
`android/key.properties`. Windows ACLs restrict these files to the current user.
Back up the keystore and credentials to a secure separate location before distribution;
the second properties file on this PC is not a disaster recovery backup.
Never regenerate or overwrite this key for later updates.

Gradle reads these environment variables first, falling back to the corresponding
property in `android/key.properties`:

| Environment variable | Local property |
| --- | --- |
| `DILIGENT_SIGNING_STORE_FILE` | `storeFile` |
| `DILIGENT_SIGNING_STORE_PASSWORD` | `storePassword` |
| `DILIGENT_SIGNING_KEY_ALIAS` | `keyAlias` |
| `DILIGENT_SIGNING_KEY_PASSWORD` | `keyPassword` |

Use an absolute keystore path with forward slashes in the properties file.
Inject environment values through a secret manager; never place passwords in
commands, tracked scripts, logs, or screenshots. Do not run verbose Gradle diagnostics
with signing credentials. No real credentials or keystore belong in Git.

For a new, separate application identity only, create a key interactively:

```powershell
keytool -genkeypair -keystore "$env:USERPROFILE/new-app-release.jks" -storetype JKS -alias release -keyalg RSA -keysize 3072 -validity 10000
```

The command prompts for a password and certificate identity. For this application,
use the existing key above instead. See the
[Flutter Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app).

## Build identities

- Debug/development retains Android's standard debug signing configuration.
- Release always uses the release configuration; absent/incomplete credentials fail
  the release build instead of falling back to debug signing.
- GitHub Actions creates a disposable `CI Validation` key and supplies it via
  environment variables. Those APK/AAB files only validate compilation and must
  never be distributed as production builds. Production secrets are not sent to CI.

```powershell
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

Verify APK with Android SDK `apksigner verify --verbose --print-certs` and AAB
with JDK `jarsigner -verify -verbose -certs`. Compare both certificate SHA-256
fingerprints with the production keystore certificate. Self-signed certificate and
missing timestamp warnings from jarsigner are expected for this Android identity.

The old development-signed installation cannot be updated in place with this key.
Preserve/export existing user data before any later installation migration; no
device installation or removal was performed by the initial signing preparation.
The subsequent verified device migration is recorded in `release-v1-final.md`.
For Google Play, choose/configure Play App Signing separately: this local key can
serve as the upload key, while Play signs delivered APKs with its app signing key.

## Remaining release checks

- Secure off-machine key/credential backup and distribution channel / Play setup.
- Real TalkBack navigation and long outdoor recording under manufacturer power saving
  remain unverified, as recorded in `release-rc1.md`.
- Production-signed device migration and S20 smoke test are complete; see `release-v1-final.md`.
- Remote GitHub Actions results remain pending; no tag, release, merge or push is
  performed as part of this work.

## Verification record — 2026-09-23

- `flutter analyze`: no issues.
- `flutter test`: 140 passed, 2 private-data regressions skipped (fixtures not supplied).
- `flutter build apk --release`: succeeded; 61,430,439 bytes.
- `flutter build appbundle --release`: succeeded; final clean rebuild 59,320,427 bytes.
- APK `apksigner`: verified v2 signature, one RSA 3072 signer, `CN=Diligent Life Release`.
  `aapt` confirms `com.v4n1lla.diligent_life`, versionName `1.0.0`, versionCode `12`.
- AAB `jarsigner`: `jar verified.`; certificate matches APK and local keystore.
  JDK 21 warns about self-signed trust, no timestamp, ZIP attributes, and manifest
  ordering for JarInputStream. A separate verifying JarFile read consumed every
  payload entry: all 404 entries match the exact release certificate, with no
  duplicate ZIP entries. These checks do not assert Google Play upload acceptance.
- An empty environment password overrides the local property and correctly fails
  `:app:validateReleaseSigning`. Debug dry-run task graph excludes release validation.
- `git check-ignore` confirms local secrets are excluded; tracked files contain
  neither secret paths nor the generated password. Keystore lives outside the repo.
- Non-fatal build warning: `flutter_timezone` uses legacy Kotlin Gradle plugin.
  Dependencies and app behavior were not changed; only version constants were synced.

Certificate SHA-256:
`2F:79:54:5E:94:59:E0:98:84:C6:19:76:B6:C0:58:76:AA:E9:FC:B5:E9:AB:B2:B4:FA:70:0D:FC:0B:BA:39:87`

Artifact SHA-256:

| Artifact | SHA-256 |
| --- | --- |
| `build/app/outputs/flutter-apk/app-release.apk` | `09BB9BD6FD2A7F47219AF2ADC628A57565BB0B6CF3FB0FE5EACDBEC6FFB369E8` |
| `build/app/outputs/bundle/release/app-release.aab` | `0554320F26C1B93FB6BA181113A8551A53A88DC6F7FDD960D944E1A3E6686743` |

The initial build had stale RC display constants despite correct Android version metadata.
`flutter clean` and both release builds resolved this without source edits. Both devices
now display `1.0.0 (12)`. Hashes above identify these final rebuilt artifacts.
Final verification/build logs are under ignored `.tools/v100-final/`.
