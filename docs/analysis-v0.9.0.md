# Exercise analysis v0.9.0

- Analysis policy 2 invalidates derived caches; session totals and all raw rows remain immutable.
- **Recorded distance / total recorded time** are the original values, used consistently by detail, history, portfolio, report and sharing. Total time includes stops/unknown time, excludes manual pause, and remains the basis of the original MET calorie estimate. **Valid moving distance / moving time** are separately labelled derived values. Reanalysis does not silently rewrite either historical totals or calories.
- Stationary tracking anchors reset every 30 seconds. With no pause evident in the session clocks, adjacent accurate fixes with near-zero sensor speed and negligible displacement may continue a stop across those automatic boundaries. Gaps over 15 seconds, quality failures and sessions with pauses retain their boundaries. Short tails can extend an already established stop; they never create movement.
- A record needs raw sensor coverage of at least 80% of its window, accuracy at most 15m, and agreement between sensor, raw-coordinate and smoothed speeds. Missing/invalid sensors and conflicting speeds remain analysable but cannot earn speed/distance records. Stationary coordinates with consistently moving sensor speed remain unknown.
- Distance records span only contiguous eligible moving windows. Improvements must exceed both candidates' uncertainty floors: max(2 seconds, 2%, twice the route accuracy converted to time). This is a conservative product threshold, not a statistical confidence interval.
- Splits (500m/1km), equal-distance halves and speed distribution use valid moving distance/time. Partial splits and interrupted splits are labelled; neither earns a record. Best routes preserve interpolated endpoints and sampled interior geometry.
- Quality and secondary metrics are collapsed by default. Excluded point counts count rows, not windows. Display geometry is sampled; recorded and analysed distances use their original full-resolution calculations.

## Private S26 regression

S26 is a personal device: do not connect to or manipulate it for development without explicit instruction. Development handset: **SM-G988N / Galaxy S20 Ultra**.

The previously exported private `data.json` has arrays `exercise_sessions`, `route_points`, `raw_route_points`. Set `S26_REGRESSION_DATA` to that file before `flutter test`; the regression is explicitly skipped when the private export is absent. No personal coordinates or device backup files belong in the repository.

Latest session (id 13), v0.8.0 → v0.9.0:

| Metric | Before | After |
|---|---:|---:|
| Recorded distance | 2584.6326m | 2584.6326m |
| Valid moving distance | 2437.4863m | 2414.2759m |
| Recorded minus analysed distance | 147.1463m | 170.3567m |
| Highest eligible speed | 8.1723km/h | 5.9715km/h |
| Moving time | 2180.302s | 2156.817s |
| Stopped time | 3648.125s | 4568.578s |
| Unknown time | 1427.573s (19.67%) | 530.605s (7.31%) |
| 100m | 65.9445s, improvement | 70.1601s, no improvement |
| 500m | 442.1813s | 456.8834s |
| 1km | unavailable | unavailable |

The larger distance delta is deliberate: disputed movement was removed, rather than changing the immutable recorded distance to conceal the difference. Aggregate recorded totals remain 11 sessions, 16489.7194m, 29799s.
