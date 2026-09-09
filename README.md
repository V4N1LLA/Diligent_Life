# Diligent Life

광고, 로그인, 불필요한 기능 없이 **매일 30초 안에 기록하는 개인용 다이어트 앱**입니다.

## MVP

- 매일 기록 알림
- 몸무게 기록
- 운동 시간 / 거리 기록
- 예상 소모 칼로리 자동 계산 및 저장
- 날짜별 기록 저장
- 몸무게 / 운동량 / 소모 칼로리 추이 그래프
- 시스템 다크/라이트 모드 대응
- 로컬 우선 저장(SQLite), 계정/서버 없음

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
- 한 번도 몸무게를 기록하지 않았다면 운동 저장 전에 몸무게를 입력하도록 안내합니다.
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

파일: `diligent_life.db`, 스키마 버전: 1, 테이블: `daily_records`.

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
앱의 서버·계정·네트워크 요청·분석 SDK는 없습니다. Android 릴리스 매니페스트에 INTERNET 권한을 선언하지 않습니다(Flutter 개발용 debug/profile은 디버깅 통신 권한 사용).
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

현재 개발 환경은 Android SDK/Android 기기가 없으므로 다음은 Android 환경에서 확인해야 합니다.

- 앱 설치, 콜드 스타트, 키보드/뒤로가기, 한 손 30초 입력, 실제 Light/Dark 화면 및 큰 글꼴
- 종료 후 재실행 시 SQLite 기록 유지, 과거 날짜 수정, 7일/30일 경계
- Android 12 이하와 13+에서 알림 허용/거부/재허용, 시간 변경, OFF 후 취소
- 실제 선택 시각 알림, 절전, 재부팅, 앱 업데이트, 시간대/서머타임 변경
- Android 릴리스 빌드의 아이콘 유지 및 배포 서명, iOS 빌드/권한/알림

## 이후 개선 후보

우선 실제 사용자 입력 시간을 측정하고 간격·키보드 동선을 다듬습니다. 필요성이 확인되면 사용자가 직접 관리하는 파일 내보내기/가져오기, 기록 삭제를 추가할 수 있습니다. 계정, 클라우드 동기화, 서버, 광고, 소셜, 결제, 건강 플랫폼 연동은 현재 범위에 포함하지 않습니다.


## MVP v0.1.0 1차 품질 검수

기능 추가 없이 입력·그래프·알림 동작을 보완했습니다. 버전은 `0.1.0+1`입니다.

- 예상 칼로리와 저장 버튼을 하단에 유지합니다. 숫자 키보드, 다음/완료 포커스, 운동 선택 후 시간 입력, 탭 전환 시 키보드 해제를 검증했습니다.
- 잘못된 숫자는 미리보기에도 적용하지 않으며 0분은 약 0kcal로 표시합니다. 검증 실패 시 해당 필드로 스크롤합니다.
- 알림 권한 요청은 OFF → ON에 한정합니다. 시간 변경은 같은 ID를 갱신하고 앱 재진입은 기존 대기 예약을 보존합니다.
- 날짜 조회 중 오래된 비동기 응답은 무시합니다. 이전 날짜 계산은 24시간 차감 대신 달력 날짜를 사용합니다.
- 날짜 공백은 그래프의 선을 끊습니다. 운동 0분은 실제 점으로 유지합니다. 날짜 라벨은 양 끝만 표시하고 Y축 눈금은 단위를 고려합니다. 몸무게 축은 최소 2kg 범위를 확보합니다.
- 저장소에서도 잘못된 날짜, NaN/Infinity, 음수 및 허용 범위를 벗어난 숫자를 거부합니다. 날짜 수정 시 id/createdAt 보존 정책은 동일합니다.

MET 값은 한 곳(`exercise_type.dart`)에 유지했습니다. [2024 Compendium의 걷기](https://pacompendium.com/walking/) 및 [달리기](https://pacompendium.com/running/) 강도 범위와 비교할 때 기존 값은 대표 강도 근삿값으로 사용할 수 있는 수준입니다. 최신 표의 정확한 값을 그대로 옮긴 것은 아니며, 속도나 경사로 실제 강도를 결정하지 않습니다. 기타의 3.0 MET는 가벼운 활동 가정임을 UI에 명시했습니다.

세부 검수 결과와 실기기 미검증 항목은 [품질 검수 기록](docs/quality-review-v0.1.0.md)에 정리합니다.
