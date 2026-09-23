# Android v1.0.0 final device verification — 2026-09-23

No feature changes or refactoring. No merge, tag, GitHub Release, commit or push.

## Installation and preservation

SM-G988N (Galaxy S20 Ultra) had the Android Debug certificate. `adb install -r`
correctly rejected the production certificate with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
Before removal, exported all records through the app and verified the backup through
the real backup prepare/replace/export regression test. Every row also matched the
prior read-only baseline database. The DUAL_APP user 95 export contained zero rows
in all four tables; that backup was also retained. User authorized migration with
data preservation. Installed the production APK, restored the main user's backup,
and re-enabled the empty DUAL_APP installation.

An actual artifact issue was found: Android metadata was 1.0.0/12, but the UI still
displayed RC constants. Source constants were correct. A clean APK/AAB rebuild fixed
the stale compiled output; same-production-key `install -r` then succeeded on S20.
After all smoke flows and the final update, exported again and compared every row
and column, not only counts:

| Device | Daily records (including weight) | Sessions | Route points | Raw GPS | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| S20 Ultra | 1 | 8 | 2546 | 4972 | Exact before/after equality |
| S26 (SM-S942N) | 2 | 11 | 3366 | 8458 | Exact before/after equality |

S26 installation followed S20 verification. Its existing v0.8.0 also used the debug
certificate. Exported and validated its own backup, retained its original APK,
installed the final production APK, restored its own records, then exported again
for exact equality. No S20 data was imported into S26. Both devices' notification
switch and 20:00 time were restored, along with their existing location/notification
permissions. Location/weight backup data and APK copies remain only under ignored
`.tools/v100-final/` and device-local Downloads. No records were created or deleted.

## Core S20 smoke test

- Launch and settings: visible `1.0.0 (12)`.
- Existing exercise detail: recorded distance/time, map and analysis displayed.
- Portfolio and monthly report agree on 8 sessions, 13.34 km, 04:51:44.
- Portfolio image preview generated and Android ChooserActivity opened; cancelled
  without selecting a recipient or sending anything.
- Final export remains identical after these flows.

Both installed APKs were pulled back and their SHA-256 hashes match the final local
APK byte-for-byte. APK `apksigner verify` and AAB `jarsigner -verify` succeeded;
both certificates match the production certificate in `android-release-signing.md`.
The AAB retains self-signed/no-timestamp/ZIP-order warnings noted there; no Play upload
or acceptance claim is made. Final artifact hashes are recorded in that document.

## Skipped tests and CI

The two skips are intentional privacy-dependent fixtures:
`LEGACY_BACKUP_DATA` for an existing export round trip, and `S26_REGRESSION_DATA`
for fixed real-session movement regressions. Missing variables cause explicit skips;
they do not suppress failures when supplied. After a complete S26 export was saved,
ran `test/backup_test.dart` and `test/analysis_reliability_test.dart` with both private
inputs: all 10 tests passed, including both previously skipped tests. The original
backup is unchanged; JSON extraction was to a separate ignored file.

[GitHub Actions run 35800839551](https://github.com/V4N1LLA/Diligent_Life/actions/runs/35800839551)
succeeded for HEAD `e5bd197d65115d8266dd75beaa0f02ca6d3e27e1` on `feat/portfolio`:
format, analyze, tests, release APK and AAB steps all passed. That commit is RC1;
the uncommitted production signing/version/workflow changes are not covered by
that remote run. No remote run of those changes has been claimed.

## Remaining release blockers

- Remote CI for the final signing/version/workflow changes.
- Off-machine secure signing-key backup and distribution channel / Play setup.
- Previously outstanding real TalkBack navigation and long outdoor recording under
  manufacturer power saving remain unverified.

Device migration, data preservation and the requested S20 core flows are complete.
