# Android 1.0.0 (12) release verification

Verification performed on 2026-09-23; release status documentation updated on
2026-10-01. Android production-signed APK/AAB builds and signature verification are
complete. S26 (SM-S942N) production installation and existing-data restoration are
complete. No feature, dependency, DB schema 3 or backup format 1 changes were made
for the final signing work. All future device tests use S26 only; S20 (SM-G988N)
is no longer used for testing. S20 results below are historical evidence.

## Completed features

- Weight and manual exercise records, daily reminders.
- GPS start, pause, resume, finish and interrupted-session recovery.
- Route, speed, pace, splits, half comparison, stop statistics, GPS quality and
  reliability-aware best segments.
- Portfolio, monthly/yearly reports, All-time Map and image sharing.
- System Light/Dark, large fonts, accessibility labels and local backup/restore.

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

## Historical S20 smoke test — 2026-09-23

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

## Local tests

The base test run passed 140 tests. The two privacy-dependent tests skipped in
that run subsequently passed with private inputs, for 142 distinct passing tests
across the base and follow-up runs. CI does not receive those private inputs and
explicitly skips these two tests.

The two skips are intentional privacy-dependent fixtures:
`LEGACY_BACKUP_DATA` for an existing export round trip, and `S26_REGRESSION_DATA`
for fixed real-session movement regressions. Missing variables cause explicit skips;
they do not suppress failures when supplied. After a complete S26 export was saved,
ran `test/backup_test.dart` and `test/analysis_reliability_test.dart` with both private
inputs: all 10 tests passed, including both previously skipped tests. The original
backup is unchanged; JSON extraction was to a separate ignored file.

## Remote GitHub Actions

The 1.0.0 release commit: `273bcb254ea1b7fc4ff03e300f6e9226b05efcc4`
(`chore: prepare Android release signing`). Checked through GitHub CLI on
2026-10-01: [Flutter checks run 35820608488](https://github.com/V4N1LLA/Diligent_Life/actions/runs/35820608488)
matches this full commit SHA and completed successfully on `feat/portfolio`.
The push run finished on 2026-09-23 at 14:07:23 KST (05:07:23 UTC).
Format, analyze, tests, disposable CI signing configuration, release APK and
release AAB steps all succeeded. Remote CI verification for the final
signing/version/workflow changes is complete. CI builds use a disposable validation
key, not the production key. Later 1.0.1 changes are not covered by this run;
see [1.0.1 battery validation](battery-v1.0.1.md) for its implementation, S26
update installation, data preservation and remaining real-use measurement.

Historical RC1 [run 35800839551](https://github.com/V4N1LLA/Diligent_Life/actions/runs/35800839551)
succeeded for `e5bd197d65115d8266dd75beaa0f02ca6d3e27e1` on `feat/portfolio`:
format, analyze, tests, release APK and AAB steps all passed. It does not cover the
final signing/version/workflow commit.

## Remaining validation and distribution preparation

- Off-machine secure signing-key backup and distribution channel / Play setup.
- S26 real TalkBack voice navigation remains unverified; automated semantics and
  touch-target checks are complete. The historical S20 TalkBack setup limitation
  is recorded in `release-rc1.md`; it does not establish the S26 setup behavior.
- S26 long outdoor GPS recording with screen off, background operation and
  manufacturer power saving remains unverified. Short historical S20 checks do
  not establish long-duration reliability or S26 behavior.

iOS is outside this Android release; macOS/Xcode and device permission/backup
validation are required before any iOS release.

S26 production-signed installation and existing-data restoration are complete.
Historical S20 migration and smoke flows are also complete and will not be repeated
on S20.
