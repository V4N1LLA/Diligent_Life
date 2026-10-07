# GPS 운동 기록 v0.2.0

이 문서는 v0.2.0 구현 당시의 기록입니다. 현재 지도·원본 저장·속도·공유 정책은 [v0.3.0](movement-v0.3.0.md)을 따릅니다.

기존 오늘/추이/설정 탭을 유지합니다. 상단 **운동** 버튼에서 시작하거나 지난 운동을 조회합니다.
운동은 자동 저장되며 수동으로 입력한 오늘 기록과 별개입니다. 추이 그래프는 기존 수동 기록 기준입니다.

## 기록 정책

- 시작 시 최근 저장된 몸무게를 계산용으로 고정합니다. 몸무게가 없으면 GPS 기록은 가능하지만 kcal는 `—`로 표시합니다. 오늘 측정값을 만들어 저장하지 않습니다.
- 운동 시간은 Stopwatch로 계산하고 일시정지를 제외합니다. MET 공식에는 초를 60으로 나눈 분을 전달합니다. 평균 페이스는 운동 시간 / 거리이며 20m 미만은 표시하지 않습니다.
- 정확도 30m 초과, 오래된/역순 위치, 잘못된 좌표, 초속 12m 초과 이동, 정확도를 고려한 작은 흔들림을 제외합니다. 30초 넘는 GPS 공백과 일시정지는 새 경로 구간으로 시작하며 사이 거리는 합산하지 않습니다. 필터 수치는 보행·달리기용이며 실외 검증으로 조정할 수 있습니다.
- 채택한 위치와 누적 통계를 한 트랜잭션으로 저장합니다. 위치가 없을 때도 약 5초마다 시간을 저장합니다. 강제 종료/프로세스 손실 후에는 마지막 저장 상태를 **일시정지**로 복구합니다. 종료되어 있던 시간이나 위치 공백은 추정해서 채우지 않습니다.

## SQLite v2

v1 → v2는 기존 기록을 삭제하지 않고 다음 테이블과 인덱스만 추가합니다.

- `exercise_sessions`: id, startedAt, endedAt, updatedAt, exerciseType, weightKg(계산용 snapshot, nullable), elapsedSeconds, distanceMeters, estimatedCalories(nullable), status(recording/paused/finished).
- `route_points`: id, sessionId(FK), latitude, longitude, timestamp, accuracy, segment.
- 미완료 운동은 부분 UNIQUE 인덱스로 한 개만 허용합니다. 위치는 `(sessionId, timestamp)` UNIQUE이며 `(sessionId, id)` 인덱스로 시간 순서 조회합니다.

주요 구현: `models/exercise_session.dart`, `data/exercise_repository.dart`, `services/exercise_recorder.dart`, `utils/gps.dart`, `screens/exercise_screen.dart`.

## Android 백그라운드

사용자가 화면에서 시작/재개할 때 정확한 위치 권한을 요청합니다. 위치 OFF/거부/영구 거부/대략적 위치는 설명과 설정 이동 또는 재시도로 처리합니다. 운동 중 위치 서비스 OFF와 스트림 오류는 일시정지합니다.

`geolocator`의 location 타입 foreground 서비스, 지속 알림, PARTIAL_WAKE_LOCK을 사용합니다. Manifest에 COARSE/FINE_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION, WAKE_LOCK을 선언했습니다. POST_NOTIFICATIONS는 운동 시작/재개 시 요청하며 일일 알림 설정과 독립적입니다. 알림 거부 자체는 Android foreground 서비스 실행을 막지 않습니다.

화면이 보일 때 시작하는 foreground 위치 서비스이므로 ACCESS_BACKGROUND_LOCATION을 별도로 요청하지 않습니다. 홈/화면 OFF에도 기록하며 루트 뒤로가기에서 **계속 기록**을 선택하면 `moveTaskToBack`으로 Flutter 엔진을 유지합니다. 일반 종료 확인은 없고, 버려지는 미저장 입력에만 확인을 표시합니다. 탭 이동/운동 화면 열기는 오늘 입력을 유지합니다.

최근 앱에서 강제 제거, 설정의 강제 중지, 재부팅, OS/제조사 프로세스 종료 뒤 자동 추적 재시작은 지원하지 않습니다. 이 경우 다음 실행에서 저장된 운동을 일시정지로 복구합니다. iOS 위치 설명/백그라운드 location 설정도 포함했지만 빌드와 실기기 검증은 macOS에서 별도 진행해야 합니다.

참고: [Geolocator](https://pub.dev/packages/geolocator), [Android foreground 위치 서비스](https://developer.android.com/develop/background-work/services/fgs/service-types#location), [시작 제한](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start), [Share Plus](https://pub.dev/packages/share_plus).

## 경로 및 공유

지도 SDK/타일 서버 없이 로컬 좌표를 Canvas 경로 개략도로 표시합니다. 통계와 경로 PNG를 만들어 시스템 공유창을 엽니다. 자동 게시/전송하지 않습니다.

시작·도착 주변 **200m 숨김이 기본 ON**입니다. 중간에 다시 방문한 위치도 제거하고 숨긴 구간을 가로지르는 선도 만들지 않습니다. 공유 미리보기와 이미지에 동일한 필터를 적용합니다. 원본 경로는 기기에 유지되며 PNG에 좌표/EXIF 위치 메타데이터를 넣지 않습니다. 숨김은 장소 추측을 완전히 방지하지 않으므로 미리보기를 확인할 수 있게 안내합니다. 짧은 경로는 모두 숨겨질 수 있습니다.

## 실기기 검증 체크

- Android 13 알림 권한, Android 14+ foreground 위치 권한/서비스 시작, 위치 권한 거부/정확도 변경/위치 OFF 후 재개.
- 실외 보행/달리기, 정지 GPS 흔들림, 터널·실내 수신 공백, 일시정지 중 이동의 거리 제외.
- 홈/뒤로가기의 계속 기록/화면 OFF 상태에서 10분 이상 기록 후 누적 시간과 위치 확인. 제조사 절전 환경 포함.
- 종료 후 서비스/알림/wake lock 해제, 앱 재실행 후 이력/경로 복원, 강제 종료 후 일시정지 복구.
- 공유창 취소 및 설치된 카카오톡/SNS 앱에 이미지 첨부, 시작·도착 숨김 결과 확인.

실제 위치를 가진 기기가 연결되지 않은 환경에서는 위 항목을 자동 테스트나 APK 빌드 성공만으로 검증했다고 간주하지 않습니다.
