# Android Home Screen Widget

## UI와 action

- 오늘 걸음: 기본 2×2. 날짜·걸음, 목표/퍼센트, progress, 운동 시작.
- 활동과 성장: 기본 4×2. 위 정보에 Level/현재 Title, 오늘 **걸음 퀘스트 한 개**의 달성률을 추가. 퀘스트 목표는 기존 dailyQuests에서 받아 사용자 걸음 목표와 구분한다.
- width 250dp 미만 또는 font scale >1.5에서는 걸음 중심 compact으로 전환. 큰 글꼴에서는 보조 label/progress를 줄이고 숫자와 버튼을 유지. 시스템 Light/Dark 리소스, sage surface/purple accent 사용.
- 걸음 → Today, Level/Title → Profile, Quest → 성장 화면, 운동 시작 → 기존 종류 선택/진행 중 운동 화면. 기록 자동 시작이나 XP 수령 버튼 없음.
- immutable PendingIntent와 목적지별 URI 사용. 녹화 제어 token을 발급하지 않으며 기존 pause/resume session 검증 유지.

## 갱신과 배터리

- 기존 step service의 DB flush(30초 batching) 및 상태/목표 변경에서 갱신 요청. 센서 저장과 widget rendering 분리.
- 동일 WidgetState는 생략. step-only 변경은 최소 30초 간격이며 dirty trailing callback 하나로 마지막 값도 반영; 목표 도달·날짜·목표·Level/Title·권한 상태 변경 및 system resize/update는 즉시 처리.
- 성장 transaction이 완료된 뒤 Level/Title/기존 quest target만 native SharedPreferences로 전달. 값이 같은 cache는 재기록하지 않음.
- foreground 복귀·backup restore·system update·boot/package/timezone 변경에서도 재조회. 모든 인스턴스는 동일 snapshot 사용하며 각각 폭에 맞게 렌더링.
- `updatePeriodMillis=0`, 새 dependency/센서 subscription/GPS/FGS/주기 background timer 없음. native 단일 worker가 읽기 전용으로 **당일 daily_steps 인덱스 한 행**만 조회, busy timeout 500ms. raw GPS/전체 기록을 읽지 않으며 저장 실패나 widget host 오류가 운동/보상을 중단하지 않음.

## 자정 및 lifecycle 제약

자정 갱신과 process death를 함께 지원하기 위해 설치된 위젯이 있을 때만 다음 local midnight에 **비 wakeup RTC 단발 alarm**을 예약한다. exact alarm 권한이나 `*_WAKEUP`, 반복 polling은 사용하지 않으며 마지막 위젯 삭제 시 취소한다. 기존 health service의 date change도 갱신한다.

Android의 inexact alarm/Doze/OEM 정책상 자정 정각 표시 전환을 보장하지 않는다. 기기가 잠들어 있으면 깨운 후 OS가 전달할 때 갱신되며, 마지막 snapshot의 날짜를 표시해 지난 날짜 숫자를 구분한다. 모든 갱신은 그 시점의 local date로 조회하므로 전날 걸음/quest를 오늘 값으로 복사하지 않는다. force-stop은 Android가 alarm/broadcast를 막으므로 앱 재실행 전 자동 갱신을 보장하지 않는다. 일반 process kill과 force-stop을 구분한다.

앱 데이터가 없거나 DB가 migration/restore 중이면 친근한 fallback과 **동일 날짜**의 마지막 snapshot만 사용한다. 새 날짜에는 이전 날짜 cache를 버리고 0부터 표시한다. 지원 센서/권한/enable 상태는 숫자 대신 안내를 덧붙인다. 위젯의 걸음/Level/Title은 홈 화면을 보는 사람에게 보일 수 있으며 위치·체중·raw GPS·내부 ID는 표시하지 않는다.

schema 5와 backup format 3은 그대로다. widget cache/host instance ID는 사용자 원본이 아니므로 export하지 않으며 복원 후 현재 DB/성장 snapshot으로 다시 표시한다.

## 검증

Flutter: 성장 snapshot·장착 타이틀 전달, widget 실패 시 transaction/XP 중복 방지, 네 목적지의 action 처리. 기존 전체 회귀 suite 유지.

Native policy: 중복·30초 throttle·목표 달성·자정 reset·성장/목표 변경·resize·큰 글꼴 fallback·큰 숫자 경계.

Android host instrumentation: compact/wide, Light/Dark, font 1/1.5/2, 숫자/48dp 버튼, 여러 widget instance, cached growth, 자정 fixture, immutable intent, 삭제 정리. Diligent_API36의 launcher 및 lifecycle 검증 결과는 PR에 기록한다.

S26 추가 검증: Samsung One UI 크기/색/잘림, 실제 step flush 반영, 장시간 배터리. 에뮬레이터 결과로 실제 센서/배터리 품질을 대체하지 않는다.

공식 근거: [App widget updates](https://developer.android.com/develop/ui/views/appwidgets/advanced), [AlarmManager RTC/inexact](https://developer.android.com/reference/android/app/AlarmManager).
