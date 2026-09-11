# Diligent Life

운동 경로·속도·몸무게의 변화를 쌓아 **나만의 movement portfolio를 만드는 개인 라이프 트래커**입니다. 광고와 로그인 없이 일상 기록은 가볍게, 원본 트래킹 데이터는 기기에 보존합니다.

## MVP

- 매일 기록 알림
- 몸무게 기록
- 운동 시간 / 거리 기록
- 예상 소모 칼로리 자동 계산 및 저장
- 날짜별 기록 저장
- 몸무게 / 운동량 / 소모 칼로리 추이 그래프
- 시스템 다크/라이트 모드 대응
- 로컬 우선 저장(SQLite), 계정/서버 없음
- GPS 운동 시작·일시정지·재개·종료, 경로/통계 이력, 결과 이미지 공유

## Product principles

1. **Fast** — 앱을 열고 30초 안에 오늘 기록을 끝낼 수 있어야 합니다.
2. **Light** — 광고, 피드, 소셜, 계정 시스템을 넣지 않습니다.
3. **Private** — 기본 데이터는 사용자의 기기에만 저장합니다.
4. **Calm** — 자극적인 연속 출석/죄책감 UX 대신 추세와 꾸준함을 보여줍니다.

## Planned stack

- Flutter / Dart
- `sqflite` — 로컬 기록 저장
- `flutter_local_notifications` — 매일 알림
- `fl_chart` — 추이 그래프
- `shared_preferences` — 알림 시간 등 간단한 설정
- `geolocator` 14.0.3 — GPS 및 Android foreground 위치 서비스
- `share_plus` 13.3.0 — 시스템 공유창으로 PNG 카드 공유
- `flutter_map` 8.3.2 / `latlong2` — 실제 지도, 경로, 위치 추적 및 공유용 지도 캡처

## Calorie estimate

예상 운동 소모 칼로리는 MET 기반 공식을 사용합니다.

`kcal = MET × 3.5 × 체중(kg) ÷ 200 × 운동시간(분)`

실제 소모량은 속도, 경사, 체성분, 심박수 등에 따라 달라질 수 있으므로 앱에서는 **예상치**로 표시합니다.

## 구현 및 실행

Flutter 표준 Android/iOS 프로젝트입니다. Flutter **3.47.2 / Dart 3.13.2**로 개발·검증합니다.
Android applicationId는 `com.v4n1lla.diligent_life`입니다.

```sh
flutter pub get
flutter run
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed .
flutter build apk --debug
```

이 작업 환경의 SDK는 Git에서 제외한 `.tools/flutter`에 있습니다. PowerShell에서:

```powershell
$env:PATH = "$PWD\.tools\flutter\bin;$env:PATH"
$env:PUB_CACHE = "$PWD\.tools\pub-cache"
flutter run
```

Android SDK와 JDK 17을 준비하고 `flutter doctor -v`로 확인하세요.
iOS 실행·빌드는 macOS와 Xcode가 필요합니다. iOS 표준 타깃과 알림 권한 흐름은 포함되어 있으나 iOS 기기 검증은 별도로 필요합니다.
릴리스 배포 전에는 Android의 기본 개발용 서명을 배포용 키로 교체해야 합니다.

## 화면과 기록 정책

- **오늘**: 날짜, 몸무게, 운동 프리셋, 시간, 선택 거리 입력. 예상 소모 칼로리 즉시 표시 및 날짜별 저장/수정.
- **추이**: 최근 7일(오늘 포함), 30일, 전체의 몸무게·운동 시간·예상 소모 칼로리 그래프. 빈 기간은 안내 문구 표시.
- **설정**: 매일 기록 알림 ON/OFF, 시간(기본 20:00), 앱 정보, 오픈소스 라이선스.
- 몸무게만 기록할 수 있습니다. 운동 시간은 0분으로 저장됩니다.
- 몸무게를 비우면 선택 날짜 이전의 최근 측정값으로 칼로리를 계산합니다. 과거 날짜를 기록할 때 미래 측정값은 사용하지 않습니다.
- 대체 사용한 몸무게는 새 측정값으로 저장하지 않습니다. 따라서 측정하지 않은 날의 몸무게 추이를 만들지 않습니다.
- 오늘 화면의 수동 운동 기록은 칼로리 계산을 위해 몸무게 입력을 안내합니다. GPS 운동은 몸무게 없이도 경로를 저장하며 kcal를 표시하지 않습니다.
- 거리를 입력하면 운동 시간도 필요합니다. 거리는 칼로리 공식에 사용하지 않습니다.
- 저장된 칼로리는 해당 저장 시점의 추정치입니다. 과거 몸무게 수정으로 다른 날짜의 칼로리를 소급 변경하지 않습니다.
- 그래프는 실제 달력 날짜 간격을 사용합니다. 기록이 없는 날짜를 0으로 채우지 않습니다.
- 오류가 발생하면 재시도할 수 있으며 저장 실패 시 입력값은 유지됩니다.

## 주요 파일

```text
lib/
  main.dart                       앱 시작, NavigationBar, 한국어/테마 설정
  models/daily_record.dart         SQLite 레코드 변환
  models/exercise_type.dart        운동 프리셋 및 MET
  data/record_repository.dart      SQLite 생성, 날짜 조회, 트랜잭션 저장
  services/reminder_service.dart   알림 권한·예약·설정 저장
  screens/today_screen.dart        빠른 입력과 날짜별 수정
  screens/trends_screen.dart       fl_chart 그래프 및 기간 필터
  screens/settings_screen.dart     최소 설정
  theme/app_theme.dart             차분한 Material 3 Light/Dark 테마
  utils/calories.dart              독립적인 칼로리 계산
  utils/dates.dart                 지역 날짜 정규화
 test/                            계산, 실제 SQLite, 알림 시간, 화면 테스트
```

## SQLite 구조

파일: `diligent_life.db`, 스키마 버전: 3. 기존 `daily_records`와 운동/경로를 유지하며 원본 GPS 표본 테이블을 추가합니다. 아래 표는 일상 기록 구조이며, 운동 데이터의 상세 구조는 [v0.3.0 기록](docs/movement-v0.3.0.md)에 있습니다.

| 필드 | SQLite 타입 | 정책 |
| --- | --- | --- |
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| date | TEXT | NOT NULL UNIQUE, 지역 날짜 YYYY-MM-DD |
| weightKg | REAL | nullable, 실제 입력한 측정값, > 0 |
| exerciseType | TEXT | NOT NULL, enum 식별자 |
| durationMinutes | INTEGER | NOT NULL, >= 0 |
| distanceKm | REAL | nullable, >= 0 |
| estimatedCalories | REAL | NOT NULL, >= 0, 반올림 전 값 |
| createdAt | TEXT | NOT NULL, UTC ISO 8601 |
| updatedAt | TEXT | NOT NULL, UTC ISO 8601 |

날짜 UNIQUE 인덱스로 빠르게 조회합니다. 트랜잭션 안에서 해당 날짜를 먼저 UPDATE하고 없을 때 INSERT합니다. 수정 시 `id`, `createdAt`을 보존합니다.
알림 설정은 `shared_preferences`에 `reminder_enabled`, `reminder_hour`, `reminder_minute`로 저장합니다. `reminder_timezone`은 예약한 시간대를 기억해 불필요한 재예약을 방지합니다.
앱 자체 서버·계정·분석 SDK는 없습니다. v0.3.0부터 실제 지도 표시를 위해 INTERNET 권한을 사용하고 OpenStreetMap 지도 타일을 요청합니다. 지도 제공자는 요청한 지도 영역과 IP 주소를 알 수 있습니다. 원본 GPS·몸무게·운동 통계를 업로드하지 않습니다. 네트워크가 없어도 GPS 기록과 SQLite 저장은 계속되며, 미캐시 지도 로딩과 지도 이미지 공유에는 연결이 필요합니다.
Android 자동 클라우드 백업 및 기기 이전에서 로컬 데이터를 제외합니다. iOS OS 백업 정책은 iOS 출시 전에 별도 확인해야 합니다. 앱 삭제 시 복원 기능은 제공하지 않습니다.

## MET와 예상 칼로리

`kcal = MET × 3.5 × weightKg / 200 × durationMinutes`

| 프리셋 | 기본 MET |
| --- | ---: |
| 가벼운 걷기 | 2.8 |
| 빠른 걷기 | 4.3 |
| 조깅 | 7.0 |
| 달리기 | 9.8 |
| 기타 | 3.0 |

MVP의 고정 강도 가정입니다. 특히 기타는 모든 운동을 정확히 나타내지 않습니다. 70kg, 빠른 걷기 30분은 158.025kcal이며 화면에는 약 158kcal로 표시합니다. 몸무게와 강도는 개인별 실제 소모량을 보장하지 않으므로 항상 **예상 소모 칼로리**로 표시합니다.

## 알림 구현

[`flutter_local_notifications` 공식 설정](https://pub.dev/packages/flutter_local_notifications)에 따라 Android desugaring, 알림 아이콘, 수신기와 권한을 구성했습니다.

- 기본 OFF. 사용자가 켤 때만 Android 13+ POST_NOTIFICATIONS 및 iOS 알림 권한을 요청합니다.
- 권한이 거부되면 OFF를 유지하고 기기 설정 안내를 표시합니다.
- timezone DB와 `flutter_timezone`의 실제 기기 시간대로 다음 알림을 계산합니다.
- `zonedSchedule`, 고정 ID 1, `DateTimeComponents.time`으로 하루 한 번 예약합니다. 시간 변경 시 같은 ID를 갱신하고 OFF 시 취소합니다.
- Android는 `inexactAllowWhileIdle`을 사용합니다. 별도의 정확한 알람 권한은 필요하지 않으며 OS 절전으로 선택 시간보다 늦게 도착할 수 있습니다.
- BOOT_COMPLETED/MY_PACKAGE_REPLACED 수신기로 재부팅·앱 업데이트 후 예약을 복원합니다.
- 앱 재진입 시 시간대 및 권한을 확인합니다. 동일 시간대에 예약이 남아 있으면 유지하고, 예약이 없거나 시간대가 달라지면 갱신합니다. 앱이 종료된 동안 시간대를 바꾸면 다음 앱 실행 전에는 기존 시간대를 기준으로 알림이 올 수 있습니다.
- 문구: **오늘의 기록을 남겨볼까요?**

## 검증과 직접 확인할 항목

자동 검증은 `flutter analyze`, `flutter test`, Dart format 확인입니다. SQLite 테스트는 인메모리 SQLite 엔진을 실제로 사용하며 화면 테스트는 메모리 저장소로 UI 동작을 격리합니다. GitHub Actions에는 동일 검증과 Android debug APK 빌드가 포함되어 있습니다. 아직 push하지 않았으므로 CI 실행 결과는 없습니다.

초기 구현 시점의 2026-09-09 검증 결과: `flutter analyze` **No issues found**, `flutter test` **17개 모두 통과**, `dart format --output=none --set-exit-if-changed .` **변경 없음**, `git diff --check` **통과**. 360px 다크 모드에서 단일 데이터 그래프 및 1.5배 글꼴에서 저장 동작도 위젯 테스트로 확인했습니다.

아래는 초기 MVP 검증 당시의 체크리스트입니다. 최신 Android 실기기 결과는 [v0.3.0 검증 기록](docs/movement-v0.3.0.md)을 확인하세요.

- 앱 설치, 콜드 스타트, 키보드/뒤로가기, 한 손 30초 입력, 실제 Light/Dark 화면 및 큰 글꼴
- 종료 후 재실행 시 SQLite 기록 유지, 과거 날짜 수정, 7일/30일 경계
- Android 12 이하와 13+에서 알림 허용/거부/재허용, 시간 변경, OFF 후 취소
- 실제 선택 시각 알림, 절전, 재부팅, 앱 업데이트, 시간대/서머타임 변경
- Android 릴리스 빌드의 아이콘 유지 및 배포 서명, iOS 빌드/권한/알림

## 이후 개선 후보

우선 실제 사용자 입력 시간을 측정하고 간격·키보드 동선을 다듬습니다. 필요성이 확인되면 사용자가 직접 관리하는 파일 내보내기/가져오기, 기록 삭제를 추가할 수 있습니다. 계정, 클라우드 동기화, 서버, 광고, 소셜, 결제, 건강 플랫폼 연동은 현재 범위에 포함하지 않습니다.


## MVP v0.1.0 1차 품질 검수

기능 추가 없이 입력·그래프·알림 동작을 보완했습니다. 당시 버전은 `0.1.0+1`입니다.

- 예상 칼로리와 저장 버튼을 하단에 유지합니다. 숫자 키보드, 다음/완료 포커스, 운동 선택 후 시간 입력, 탭 전환 시 키보드 해제를 검증했습니다.
- 잘못된 숫자는 미리보기에도 적용하지 않으며 0분은 약 0kcal로 표시합니다. 검증 실패 시 해당 필드로 스크롤합니다.
- 알림 권한 요청은 OFF → ON에 한정합니다. 시간 변경은 같은 ID를 갱신하고 앱 재진입은 기존 대기 예약을 보존합니다.
- 날짜 조회 중 오래된 비동기 응답은 무시합니다. 이전 날짜 계산은 24시간 차감 대신 달력 날짜를 사용합니다.
- 날짜 공백은 그래프의 선을 끊습니다. 운동 0분은 실제 점으로 유지합니다. 날짜 라벨은 양 끝만 표시하고 Y축 눈금은 단위를 고려합니다. 몸무게 축은 최소 2kg 범위를 확보합니다.
- 저장소에서도 잘못된 날짜, NaN/Infinity, 음수 및 허용 범위를 벗어난 숫자를 거부합니다. 날짜 수정 시 id/createdAt 보존 정책은 동일합니다.

MET 값은 한 곳(`exercise_type.dart`)에 유지했습니다. [2024 Compendium의 걷기](https://pacompendium.com/walking/) 및 [달리기](https://pacompendium.com/running/) 강도 범위와 비교할 때 기존 값은 대표 강도 근삿값으로 사용할 수 있는 수준입니다. 최신 표의 정확한 값을 그대로 옮긴 것은 아니며, 속도나 경사로 실제 강도를 결정하지 않습니다. 기타의 3.0 MET는 가벼운 활동 가정임을 UI에 명시했습니다.

세부 검수 결과와 실기기 미검증 항목은 [품질 검수 기록](docs/quality-review-v0.1.0.md)에 정리합니다.

## v0.2.0 GPS 운동 기록

상단 운동 버튼에서 GPS 운동을 기록하고 지난 경로/통계를 조회합니다. 결과 이미지 공유에는 시작·도착 주변 200m 숨김이 기본 적용됩니다.
저장 구조, Android 백그라운드 동작 범위 및 실기기 확인 항목은 [GPS 구현 기록](docs/gps-v0.2.0.md)에 정리합니다.


## v0.3.0 지도와 movement portfolio

- 운동 중 실제 지도, 최근 유효 위치 마커, 속도별 경로, 기본 위치 추적과 재중앙 버튼.
- 지도 아래 큰 수치와 고정 일시정지/재개/종료 버튼. 기존 이탈 보호 유지.
- 개인 상세는 전체 경로, 공유 미리보기는 시작·도착 200m 숨김 기본 적용.
- 약 5초 이상 시간 구간의 거리/시간으로 속도·페이스를 분석하고 선택 위치를 지도에 표시.
- 실제 지도와 경로·핵심 수치를 담은 PNG 카드와 Android 시스템 공유창.
- 완료한 GPS 운동의 누적 횟수·거리·시간·예상 kcal. 월/연 단위 경계로 집계 가능한 `MovementSummary`.
- SQLite v3: 기존 경로·일상 기록 보존, raw 센서 표본·제외 사유·필터 버전·누적 거리 추가.

설계, 지도 제공자 정책, 원본 보존 범위, 실기기 검증은 [v0.3.0 구현 기록](docs/movement-v0.3.0.md)에 정리합니다. 월간/연간 화면, 누적 경로 지도, 몸무게와 GPS 운동의 통합 추이는 후속 확장 범위입니다.
