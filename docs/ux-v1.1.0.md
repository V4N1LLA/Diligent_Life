# 1.1.0(14) — 기록과 나의 성장

2026-10-06 구현 및 S26 검증. 서버·로그인·랭킹은 구현하지 않습니다. 실기기 검증 대상은 S26(SM-S942N)이며 변경사항은 feat/portfolio 브랜치로 관리합니다.

## 화면

Today의 운동 시작 CTA를 유지하고 오늘 걸음/목표, 이번 주 GPS 운동 거리, compact Lv/XP/장착 타이틀을 연결합니다. 걸음 또는 나의 성장을 누르면 최근 7일, 주·월 걸음, 목표, 퀘스트, 업적, 타이틀 화면으로 이동합니다. 기록 없는 날을 센서 측정 0걸음으로 채우지 않습니다.

운동 상세는 지도와 scrubber, 기록 거리·시간·평균 페이스를 우선 보여줍니다. 기존 분석 패널의 신뢰도·원본 GPS·제외 이유 등은 접힌 상세 분석에 유지합니다. 기존 분석 결과와 raw GPS를 삭제하거나 다시 쓰지 않습니다.

## 만보기와 배터리

- Android TYPE_STEP_COUNTER + ACTIVITY_RECOGNITION 권한, opt-in health foreground service. 지원하지 않는 기기·권한 거부·서비스 중단 안내와 권한 설정/다시 시작 제공.
- Flutter 엔진이 닫혀도 native 서비스가 기록하며, 명시적 끄기·권한 해제·강제 중지 및 제조사 절전 제한을 존중합니다. BOOT_COMPLETED/MY_PACKAGE_REPLACED와 앱 실행에서 허용된 서비스 복원을 시도합니다.
- 센서 batching 요청 최대 30초. 이벤트 발생 후 최대 30초의 저장 묶음으로 daily_steps와 hardware cursor를 동일 트랜잭션에 저장합니다. 센서 FIFO flush 완료를 기다린 후 화면 데이터를 읽으며 화면 복귀/표시 중 30초 갱신합니다. 실제 센서/OS 반영 지연은 기기와 절전에 따라 더 길 수 있습니다.
- GPS·가속도계 polling·새 wake lock·1초 만보기 타이머·걸음마다 notification 갱신 없음. 기존 GPS 기록 서비스의 2초 bestForNavigation/raw 저장/wake lock/화면 가시성 최적화는 유지.
- boot count, cumulative counter, monotonic sample timestamp, 현지 날짜를 함께 관리합니다. 첫 관측/재부팅/reset은 새 baseline; 같은 sample·역순 sample은 무시합니다. 프로세스 재시작은 저장 cursor 이후 차이만 복구합니다. 사용자가 끄고 다시 켜면 새 baseline으로 미사용 기간을 소급하지 않습니다.
- 자정 전후 이벤트는 센서 timestamp 기준으로 날짜를 나눕니다. 누적값 사이에 자정 수신 공백이 있으면 어느 날의 걸음인지 정확히 분리할 수 없으므로 새 날짜에 관측 차이를 저장하고 boundary 표시와 uncertainSteps를 남깁니다. 이 걸음은 전체 관측 수에는 보존하지만 일일 XP·퀘스트에서는 제외합니다. 첫날/재부팅/reset 또한 하루 전체 측정으로 표시하지 않습니다. 누락 구간의 걸음을 만들어내지 않습니다.
- 일상 걸음에는 운동 중 실제 걸음도 포함됩니다. GPS 운동 거리와 걸음 환산 거리를 합산하지 않습니다. 걸음은 걸음, GPS 거리·시간은 운동으로 구분합니다.

Android 근거: [step counter](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion), [health foreground service](https://developer.android.com/develop/background-work/services/fgs/service-types). 실제 S26 센서 정확성과 전력 소모는 자동 테스트로 확정할 수 없습니다.

## XP·퀘스트·업적

xpRuleVersion=1. 센서 걸음 1,000당 10 XP(일 100), 완료한 GPS 운동 1km당 15 XP(일 150), 10분당 10 XP(일 60). 기본 활동은 하루 최대 310 XP입니다. 체중·칼로리·수동 입력에는 XP를 주지 않습니다. 기존 완료 GPS 기록도 날짜별로 한 번 반영합니다.

일일 5,000걸음/운동 3km/운동 30분 퀘스트는 각각 30 XP, 월요일 기준 주간 운동 3회는 80 XP입니다. 장기 업적은 첫 운동, 한 번에 5km/10km, 누적 운동 100km, 누적 100,000걸음, 운동 30회이며 각각 50/80/120/200/150/150 XP와 고유 타이틀을 제공합니다. 타이틀 하나만 장착하거나 해제할 수 있습니다.

보상 키는 활동 날짜, 퀘스트 ID+기간, 업적 ID로 고정하며 UNIQUE 제약과 트랜잭션으로 중복 지급을 막습니다. 한 번 적립된 entitlement는 재열기·동시 갱신·삭제 후 같은 활동량 재작성으로 다시 지급하지 않습니다. Lv 1부터 다음 레벨 필요 XP는 200, 250, 300…입니다. 서버가 없는 로컬 성장 기록이며 경쟁용 검증을 주장하지 않습니다.

## 탐색·이미지·테마

Scrubber는 시간 축에서 가장 가까운 실제 accepted sample에 맞추고 marker/거리/시작 후 시간/속도를 동기화합니다. 양쪽 handle로 범위를 고르면 연속 GPS 구간의 저장 거리 차이와 시간, 평균 속도/페이스를 표시합니다. segment 변경/긴 수신 공백은 보간하거나 연결하지 않습니다. 선택 계산은 prefix 합으로 준비하고 haptic은 위치 bucket/최소 간격으로 제한합니다. 기존 분석 수치를 대체하지 않습니다.

운동 카드는 4:5, 성장/퀘스트/업적 카드는 기본 1:1(렌더러 4:5 지원)입니다. 이미지 미리보기 후 시스템 공유 또는 갤러리 저장이 가능합니다. Android 10+ MediaStore의 Pictures/Diligent Life에 pending 상태로 쓰고 완료 후 공개하며 실패 시 미완성 항목을 삭제합니다. Android 9 이하는 갤러리 저장 지원 안내를 제공합니다. 운동 지도는 기존 시작·종료점 200m 숨김을 유지하고 성취 카드에는 좌표가 없습니다.

테마는 시스템/라이트/다크를 로컬 저장하고 cold start에 복원합니다. 신규 화면은 두 테마와 320px/2배 글꼴을 검사합니다. 탐험은 versioned regionId/eventKey/sourceSessionId 모델만 추가하며 영역 해금 UI는 v1.2 후보입니다.

## 데이터와 검증

DB schema 4는 기존 4개 원본 테이블을 변경하지 않고 daily_steps/step_cursor/xp_ledger/growth_profile/exploration_events만 추가합니다. 새 백업 format 2/schema 4는 걸음·성장·탐험을 포함합니다. 기존 format 1/schema 3도 읽으며 이 백업으로 복원할 때 현재 걸음·성장은 유지합니다. hardware cursor와 기기 설정은 백업에 넣지 않습니다. 복원 중 센서 저장을 잠시 중단하고 성공/실패 후 재개합니다.

기존 S26 로컬 백업의 운동 16개, 경로 9,841개, raw GPS 25,200개, 몸무게 2개를 migration 및 백업 왕복에서 전체 필드 비교합니다. 개인정보 파일/기준값/로그는 ignored .tools에만 둡니다. S26_V110_BACKUP 환경 변수로 새 migration 회귀를 실행하며 기존 LEGACY_BACKUP_DATA/S26_REGRESSION_DATA/S26_BATTERY_DATA/S26_BATTERY_BASELINE 회귀도 유지합니다.

최종 로컬 검증: `dart format --output=none --set-exit-if-changed .` 통과, `flutter analyze --no-pub` 문제 없음, 전체 Flutter 테스트 166개 통과(개인 입력 4개 포함, skip 없음), native 센서 정책 9개 통과. 개인 입력 없는 실행은 162개 통과/4개 skip 대상입니다. 기존 1.0.1 기록 표시/저장 최적화 6개와 S26 16개 세션의 분석 기준값 회귀도 포함합니다. GPS 수집·분석·recording presentation·polyline cache 핵심 파일은 이전 HEAD와 동일합니다.

Native 정책 검사는 Android 디렉터리에서 `./gradlew :app:stepPolicyChecks`로 실행합니다. 원격 CI는 feat/portfolio push 후 해당 커밋 SHA의 결과로 확인합니다.

정식 서명 APK 빌드 성공: versionName `1.1.0`, versionCode `14`, 인증서 `CN=Diligent Life Release` SHA-256 `2f79545e9459e09884c61976b6c05876aae9fcb5e9abb2b4fa700dfc0bba3987`로 기존 정식 서명과 일치. APK SHA-256 `403797CD0FCD434D5FCAC768D859CC7D0F0785A23037A4A36CD318A86CC1722F`. 산출물은 ignored `build/app/outputs/flutter-apk/app-release.apk`에 보관합니다. 2026-10-06 S26 정식 서명 업데이트 설치를 완료했습니다.

## S26 실기기 확인 (2026-10-06)

- S26(SM-S942N), Android API 37에서 기존 1.0.1(13)의 전체 백업을 먼저 저장한 뒤 동일 정식 서명의 1.1.0(14)를 `install -r`로 설치했습니다. 운동 17개, 경로 10,844개, raw GPS 32,702개, 일상/몸무게 기록 3개의 모든 원본 행과 열이 즉시 내보낸 새 백업과 동일했습니다. 테스트 종료 백업에서도 기존 행은 모두 동일하며, 검증 중 저장한 짧은 운동 2개만 추가했습니다.
- 실제 보행으로 화면 ON과 홈/화면 OFF·GPS 동시 기록 구간에서 걸음 증가를 확인했습니다. 실제 보행 수를 별도로 계수하지 않아 정확도/누락률 통과를 주장하지 않습니다. 강제 종료 후 앱 재실행에서도 걸음 값이 유지됐습니다. 권한 거부→재요청→허용 UX도 확인했습니다.
- 기기 재부팅 후 앱을 열기 전 BOOT_COMPLETED로 health 서비스가 자동 복원됐습니다. 이후 Today의 걸음, Lv/XP, 장착 타이틀과 시스템 테마 선택이 유지됐습니다. 재부팅 후 백업에서도 원본 4개 테이블과 XP ledger/profile이 재부팅 전과 모든 필드까지 동일했습니다. 재부팅 후 새로운 실제 보행 수를 계수해 정확도를 비교한 것은 아닙니다.
- health FGS `types=0x00000100`, 알림 ID 140/channel daily_steps/importance 2, 신체 활동·알림 권한 허용을 확인했습니다. 위치 FGS와 동시에 유지됐고 GPS 종료 후에는 health FGS만 남았습니다. 만보기 센서 등록은 30초 batching, WakeLockRefCount 0입니다.
- Today Lv/XP와 퀘스트 진행 표시를 확인했습니다. 과거 활동 보상이 들어 있는 XP ledger가 반복 화면 방문·재실행·짧은 테스트 운동 후에도 완전히 동일하며 rewardKey가 고유했습니다. 완료 업적과 해금 타이틀을 확인하고 타이틀을 장착했습니다. 오늘 퀘스트를 새로 완료한 것은 아닙니다.
- 기존 운동 scrubber와 지도 선택 위치·수치 변화, 양쪽 handle의 구간 변경을 확인했습니다. 선택 구간의 거리·연속 GPS 시간이 바뀌며 기존 운동의 총 기록 시간은 그대로 유지했습니다. 개인 세션 수치와 좌표는 공개하지 않습니다.
- 운동/성취 카드 미리보기와 Android 시스템 공유 화면을 확인했습니다(외부 전송 없음). 갤러리 Pictures/Diligent Life에 실제 PNG 저장 및 파일 읽기를 확인했으며 운동 720×900, 성취 720×720입니다. Light/Dark, 시스템 테마 선택과 cold start 유지, 2배 글꼴의 Today/성장/설정/미리보기를 확인했고 기기 글꼴은 원래 1.081로 복구했습니다.
- GPS를 종료한 화면 OFF idle 68초 동안 같은 앱 프로세스의 CPU 누계 증가가 0틱이었습니다(CLK_TCK=100). 새 만보기 wake lock은 없었습니다. 1.0.1 idle과 1.1.0의 batterystats/dumpsys 기준 로그를 저장했지만 USB 충전 중이라 전력 절감/증가율을 비교할 수 없습니다.
- 이번 검증에서 현재 S26 백업을 제공한 migration/growth 및 기존 개인 GPS 분석 회귀 테스트 18개를 다시 실행해 모두 통과했습니다. 개인 백업·로그·스크린샷은 ignored `.tools/v110-device-20261006`에만 보관하며 commit/push하지 않았습니다.

## 남은 실제 검증

실제 보행 수를 계수한 정확도/누락률 비교, 자정 경계, 제조사 절전과 장시간 야외 GPS/화면 OFF 및 1.0.1 대비 충전하지 않은 동일 조건 배터리 비교는 남아 있습니다. 오늘 퀘스트 신규 완료에 따른 보상 지급은 실제로 관측하지 않았으며 중복 지급 방지는 기존 활동 ledger 비교와 자동 테스트로 구분합니다. 장시간 배터리 효과나 정확성을 검증 완료로 주장하지 않습니다.
