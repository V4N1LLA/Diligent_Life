# v0.3.0 — 지도와 movement portfolio

## 구현 범위

기존 Flutter/SQLite/foreground 위치 서비스/수동 일상 기록 구조를 유지합니다. 로그인, 앱 서버, 타인 위치 공유, 소셜 SDK는 추가하지 않습니다.

- **기록**: 실제 지도, 최근 유효 위치 마커, 경로 polyline. 기본 follow, 지도 탐색 시 follow 해제, 재중앙 버튼으로 복귀. GPS가 없으면 임의 위치 대신 대기 안내.
- **하단 정보**: 시간·거리·평균 페이스·예상 kcal, 약 5초 구간 현재 속도. 세이지·보라색 포인트, 큰 수치, 둥근 패널, 항상 접근 가능한 일시정지/재개/종료 버튼. 큰 글씨에서는 수치 영역을 스크롤하고 버튼을 세로 배치.
- **상세**: 전체 경로 자동 맞춤과 시작/도착 표시. 개인 지도에는 공유용 숨김을 적용하지 않음. 속도 색상 범례, 시간 구간 선택, 선택 위치 마커. 공유 지도는 독립적인 보호된 미리보기.
- **포트폴리오**: 완료된 GPS 세션의 누적 횟수·거리·시간·예상 kcal. kcal를 계산할 몸무게가 없는 세션은 0으로 간주하지 않고 계산 가능한 기록 수를 구분. `MovementSummary.fromSessions(from:, before:)`의 반개방 날짜 범위로 월/연 집계에 재사용 가능. 수동 일상 기록과 합산해 이중 계산하지 않음.
- 기존 루트 뒤로가기의 **계속 기록 / 운동 종료**, 미저장 입력 확인을 유지. 일반 종료 확인은 추가하지 않음.

## GPS 원본과 계산 정책

`TrackingPolicy`에서 필터 버전과 기준값을 관리합니다.

- 정확도: 0 초과 30m 이하. 좌표 범위/유한값 검증, 15초 초과 지연·5초 초과 미래·역순/중복 timestamp는 계산에서 제외.
- 운동별 상한: 걷기 3.5m/s(12.6km/h), 조깅 6m/s(21.6km/h), 달리기/기타 12m/s(43.2km/h). 차량 여부를 판정하는 분류기가 아니라 보수적인 이상치 제한이며 실외 로그로 조정 필요.
- 연속 유효 fix 사이의 속도와 거리 anchor 기준 속도를 모두 검사. 빠른 이동이 30초 이상 지속되어도 anchor를 갱신해 차량 거리를 누적하는 일이 없도록 처리. 이상 이동 뒤에는 새 segment로 복귀해 연결 거리를 제외.
- 작은 흔들림은 `max(4m, 두 accuracy 합 × 0.35)` 미만이면 거리 누적에서 제외. 30초 넘는 위치 공백, 일시정지/재개, 앱 재시작은 연결하지 않음.
- 화면 속도는 센서 raw speed를 직접 노출하지 않음. 채택된 경로를 **최소 5초를 채운 연속 시간 구간의 총 거리 / 총 시간**으로 계산. Android 2초 간격/거리 필터 때문에 보통 5~수 초 더 긴 구간이며 수신 간격이 길면 최대 30초인 단일 edge를 포함할 수 있음. 5초 미만의 마지막 미완성 구간은 수치 분석에서 제외하되 지도와 원본에는 남음.
- 속도 분석은 segment·공백·불가능한 edge를 넘지 않음. 지도 색: <4km/h 세이지, 4–7km/h 청색, ≥7km/h 보라. 분석 불가능한 짧은 부분은 기본 세이지색.
- 현재 속도는 최근 구간 값이며 유효 신호가 오래 없거나 일시정지이면 `—`. 유효 stationary fix가 이어져도 5초간 채택된 이동이 없으면 0.0. 평균 페이스/평균 속도는 일시정지를 제외한 전체 운동 시간 기준이므로 이동 구간 속도와 다를 수 있음.

## SQLite v3 / 향후 재계산

- v1 → v3: 기존 `daily_records` 보존 후 최신 운동 테이블 생성.
- v2 → v3: 기존 `exercise_sessions`, `route_points` 보존. 채택된 `route_points`에 nullable `rawSpeed`(m/s), `cumulativeMeters` 추가. 기존 표본은 NULL을 유지.
- `raw_route_points`: sessionId, latitude, longitude, timestamp, accuracy, rawSpeed, segment, cumulativeMeters, **receivedAt, decision, filterVersion**. 수신 순서 id와 `(sessionId, id)` 인덱스. timestamp 중복도 그대로 저장.
- `decision`: accepted, stationary_noise, implausible_speed, quality, before_segment. 낮은 정확도·이상 속도·중복/지연 표본도 원본 테이블에 보존. 시작/재개 전 timestamp의 캐시 위치는 before_segment로만 저장.
- 센서 값과 수신 시간을 보존하고, **원본 표본 + 채택 경로 + 누적 세션 수치**를 한 트랜잭션으로 저장. 화면에는 채택 경로만 사용하므로 원본 전체를 메모리에 계속 복사하지 않음.
- pause/resume과 수신 공백은 segment에 남고, 프로세스 종료 후에는 마지막 통계를 일시정지 상태로 복원. 센서가 아예 보내지 않은 위치, 일시정지 중 위치, v0.2.0에서 이미 버린 표본은 복원하거나 만들어내지 않음. 원본의 음수 rawSpeed 같은 센서 unavailable sentinel도 유지.
- 향후 필터 재계산은 `rawRoute(sessionId)`의 수신 순서·timestamp·receivedAt·segment·버전을 이용하고 결과를 별도 derived 값으로 관리 가능. 시간 집계와 kcal 계산용 체중 snapshot은 세션에 유지. 누적 경로/대표 기록/월간·연간 화면/몸무게 통합 추이는 후속 범위.

## 지도와 공유

`flutter_map` 8.3.2, `latlong2`만 직접 추가합니다. OSM 래스터 타일을 사용하며 API 키 불필요. 앱 식별 User-Agent, 화면/PNG의 저작자 표시, SDK의 HTTP 기반 캐시(soft limit 64MiB), viewport 요청만 사용합니다. 오프라인 지도 일괄 다운로드는 하지 않습니다. 지도 요청은 표시 영역/IP를 제공자에게 전달하며 설정 화면과 README에 안내합니다. 원본 운동 데이터를 업로드하는 앱 서버는 없습니다.

지도 로딩 오류 시 재시도 안내를 표시하고 GPS 저장은 계속합니다. 타일 서비스의 가용성은 보장되지 않습니다. 이용 규모가 커질 때는 같은 TileLayer 경계에서 적절한 제공자로 교체할 수 있습니다.

- 공유는 720×930 PNG. 브랜드/날짜/운동 종류/거리, 실제 지도+경로+마커, 시간/페이스/평균 속도/예상 kcal, 짧은 보조 문구.
- 시작·도착 반경 **200m 숨김 기본 ON**. 재방문 표본도 제거하며, 바깥 두 점 사이의 선이 보호 반경을 가로지르면 선을 끊음. 공개된 구간의 처음/끝에 마커를 놓고 실제 출발·도착이 아니라는 보조 설명 표시.
- 공유 지도 bounds도 숨긴 뒤 남은 점으로 계산. 전체 숨김 시 지도 요청/캡처 없이 위치 보호 카드로 대체. 전체 경로는 기기에 보존.
- 공유 버튼은 미리보기를 화면에 보이게 한 뒤 지도 타일 로딩 완료를 확인해 RepaintBoundary로 캡처. 로딩 오류/15초 제한/화면 닫힘은 공유를 중단하고 안내. 공유 중 숨김 토글 비활성화. PNG 캡처 이미지 자원은 해제.
- `share_plus` Android 시스템 공유창 사용. 자동 전송하지 않으며, 별도 카카오톡/SNS SDK 없음. 이미지에 GPS EXIF를 추가하지 않음. 주변 지도와 경로로 장소를 추측할 가능성은 미리보기에 안내.

참고: [flutter_map](https://pub.dev/packages/flutter_map), [기본 캐시](https://docs.fleaflet.dev/layers/tile-layer/caching), [OpenStreetMap 타일 정책](https://operations.osmfoundation.org/policies/tiles/), [표시 의무](https://www.openstreetmap.org/copyright).

## 검증

- `flutter test`: 68개 통과. 기존 오늘/추이/알림/이탈 보호 회귀, 320px·2배 글씨·다크/라이트, 실제 SQLite 원자성/v2 마이그레이션, 원본 제외 표본 보존, 차량 속도·노이즈·pause, 속도 구간/달력 집계, 보호 반경 관통 edge, 지도 follow/탐색/복귀/경로 fit/마커, PNG 생성.
- Android 13 / Galaxy S20 Ultra(SM-G988N): 기존 6개 완료 세션과 898개 route point가 있는 v2 DB에서 업데이트 설치. 실제 지도/기존 전체 경로/시작·도착 표시, 속도 구간 선택, 200m 숨김 공유 PNG 생성, 시스템 공유창 열기·취소 후 복귀 확인. 실제 메시지 전송은 하지 않음.
- `flutter analyze`: No issues found. `flutter build apk --debug`: 성공, `build/app/outputs/flutter-apk/app-debug.apk`. 기존 flutter_timezone의 Kotlin Gradle Plugin 전환 예고 경고는 남아 있으나 빌드를 차단하지 않음.
- 실기기 짧은 정지 테스트: 시작 → 일시정지(00:00:59 고정) → 재개 → 루트 뒤로가기의 계속 기록 → 백그라운드 유지 → 복귀 → 종료. 종료 시 00:03:26, 0m. 기록 중 foreground=true 확인, 종료 후 foreground 해제 확인. 지도 드래그 시 follow 해제와 버튼으로 follow 복귀 확인.
- v3 DB 직접 비교: 기존 6개 세션과 898개 경로 점의 기존 필드 값이 전부 동일. 테스트 세션 id=7에는 raw 25개(accepted 7, stationary_noise 18), rawSpeed/cumulativeMeters/필터 버전 2가 저장됨. 기존 사용자 기록을 수정/삭제하지 않음. **3분 26초·0m의 검증용 완료 기록 1개가 기기에 남아 있음.**
- 생성된 720×930 보호 공유 카드를 직접 열어 지도·경로·공개 구간 마커·거리·시간·페이스·kcal·지도 저작자 표시·보조 문구를 시각 확인. 지도 관련 캡처와 DB 비교본은 개인 경로가 들어 있으므로 Git 제외 경로 `.tools/review/`에만 보관.

추가 현장 확인: 장시간 실외 보행·조깅의 거리/구간 속도 정확도, 차량 이동 제한값 조정, 터널·위치 OFF/복구, 화면 OFF/절전 상태에서 10분 이상 기록, 네트워크 끊김과 지도 재시도, Android 14+ foreground 동작, iOS 빌드/실기기. 정지한 연결 기기의 짧은 테스트로 실외 이동 정확도를 검증했다고 보지 않습니다.
- 최종 APK `versionName=0.3.0`, `versionCode=3`을 같은 실기기에 업데이트 설치했고, 누적 7회·7.17km 요약과 정돈된 2열 상세 수치 표시를 확인했습니다.
