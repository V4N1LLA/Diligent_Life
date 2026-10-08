# Activity Notification UX · 1.2.0(15)

## 표시와 동작

- 만보기: `7,324 걸음`, `목표 10,000 · 73%`. 목표 도달 시 제목에 `오늘 목표 달성`을 표시합니다. 오늘 보기와 운동 시작은 화면을 열며 기록을 자동 시작하거나 XP를 별도로 지급하지 않습니다.
- 운동: 종류, 기록/일시정지 상태, 거리·누적 시간·평균 페이스를 표시합니다. 일시정지/재개는 기존 recorder의 직렬화된 제어를 사용합니다. 운동 열기에서 기존 종료 확인을 사용합니다.
- 세션·시작 시각·상태가 바뀌거나 프로세스가 복원되면 제어 토큰을 새로 발급합니다. 이전 토큰과 중복 탭은 다른 세션이나 다음 상태를 제어하지 못합니다. 알림 intent는 immutable이며 앱의 명시적 Activity만 엽니다.

## 서비스와 갱신 비용

- health FGS(ID 140)와 기존 geolocator location FGS(ID 75415)는 분리합니다. 운동 중에는 같은 그룹 안에서 운동을 먼저 표시하고 만보기에는 운동 중임을 표시합니다. 종료 후 운동 알림을 정리합니다.
- 걸음 알림은 기존 센서 저장 batch 이후 오늘 합계를 읽고 30초 간격으로 최신 값을 합칩니다. 목표·날짜·달성 여부 전환은 즉시 반영합니다. 대기 변경이 없으면 반복 알림 timer가 없습니다.
- 운동 snapshot은 최대 15초 간격으로 합치고 상태 전환은 즉시 반영합니다. 시간 표시는 시스템 chronometer도 사용합니다. GPS 수신마다 알림을 만들지 않습니다.
- geolocator의 비동기 foreground 전환이 기본 알림으로 덮어쓰는 경합을 방지하기 위해 상태 전환 후 0.5/1.5/3.5초에만 시스템 게시 상태를 확인합니다. 덮어쓰거나 제거된 경우에만 복구하며, 종료·다음 상태에서 이전 확인 작업은 취소합니다. 상시 polling은 없습니다.
- GPS bestForNavigation/약 2초, wake lock, 저장 batching, XP/탐험 규칙, schema 5, backup format 3은 유지합니다. dependency 추가가 없습니다.

## Android 호환과 권한

- 기존 `daily_steps` 채널 ID와 사용자 설정은 유지하며 이름/설명만 이해하기 쉽게 바꿉니다.
- geolocator 기본 채널은 IMPORTANCE_NONE으로 생성되어 활동 표시에 적합하지 않습니다. `exercise_activity` LOW 채널 하나를 사용하되, 기존 geolocator 채널의 명시적 사용자 importance 선택이 있으면 이어받습니다. 기존 채널을 삭제하거나 초기화하지 않습니다.
- Android 8·9는 명시적 사용자 importance 선택을 구분하는 API가 없어 기존 importance를 그대로 이어받습니다. 기존 채널이 NONE이면 운동 알림이 서랍에 보이지 않을 수 있으며 채널 설정에서 허용해야 합니다.
- POST_NOTIFICATIONS 거부와 알림 표시 실패는 운동 저장을 중단하지 않습니다. Android가 서랍에서 FGS 알림을 숨길 수 있으므로 알림 허용 여부와 기록 가능 여부는 구분합니다.
- 현재 compile/target SDK 36은 공개 promotion 요청 API(36.1)를 제공하지 않습니다. 이번 변경은 모든 버전에서 시스템 표준 ongoing/BigText 알림을 사용합니다. SDK 상향·reflection·custom RemoteViews는 추가하지 않습니다. 향후 공식 API를 사용할 때도 사용자 승인·OEM 표시 조건을 별도 확인해야 합니다. [Live Update 공식 문서](https://developer.android.com/develop/ui/views/notifications/live-update), [Notification API](https://developer.android.com/reference/android/app/Notification).

## 검증 범위

- 결과: format/analyze 통과, 전체 Flutter 271개(로컬 비공개 입력 포함), native 정책 19개, Diligent_API36(Android 16) 합성 알림 instrumentation 21개 통과.
- 에뮬레이터 앱에서 운동 화면 deep link(자동 시작 없음), 실제 알림의 일시정지/재개 버튼, location FGS ID/채널 유지, 기본 알림 덮어쓰기 보완 후 재개, 종료 확인/알림 제거, 재시작, POST_NOTIFICATIONS 거부 상태의 운동 기록/종료를 확인했습니다.
- 에뮬레이터는 step counter가 없어 실제 health FGS·걸음 수신은 검증하지 않았습니다. 걸음 알림 표시는 합성 fixture 검증으로만 기록합니다.

- Flutter 회귀: 시간/평균 페이스, GPS snapshot coalescing, 일시정지/재개/종료, 세션·프로세스 복원 후 stale 토큰, 중복 액션, 권한 오류, 알림에서 화면 진입 시 자동 기록 금지.
- native 정책 검사: 기존 센서 cursor 9개와 알림 숫자·목표·날짜·monotonic throttle 10개. CI에서도 실행합니다.
- framework instrumentation은 합성 알림 fixture만 사용합니다. 센서/DB를 변경하지 않으며 health FGS나 실제 걸음 검증을 대신하지 않습니다.
- 실행 경로: `:app:stepPolicyChecks`, `:app:assembleDebugAndroidTest`, 에뮬레이터에서 `adb -s emulator-5554 shell am instrument -w com.v4n1lla.diligent_life.test/com.v4n1lla.diligent_life.NotificationChecks`. instrumentation 전에 debug APK/test APK 설치와 POST_NOTIFICATIONS 허용이 필요합니다.
- S26에서 실제 걸음 정확도, 장시간 화면 OFF/background 서비스, 배터리, OEM 알림 표시는 별도 검증이 필요합니다.
