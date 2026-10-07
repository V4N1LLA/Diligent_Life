# v1.0.1(13) 배터리 최적화 1차 — 2026-10-01

GPS 분석 품질을 유지하면서 기록 화면과 중복 DB 작업의 비용을 줄였습니다.
실기기 테스트는 S26(SM-S942N)만 사용합니다.

## 유지한 기록·분석 정책

- Android bestForNavigation, 요청 간격 2초, distanceFilter 0 유지.
- 모든 raw GPS를 수신마다 즉시 SQLite에 저장. accepted RoutePoint, 누적 통계와 동일 트랜잭션이며 DB·백업 형식은 유지.
- GPS 필터, 저장 거리 계산, 이동·정지 분석, 최고 100m/500m/1km 및 포트폴리오 계산 코드는 변경하지 않음.
- foreground service, 지속 wake lock, 위치 권한과 일시정지·종료·오류 정리 경로 유지.
- 주기 연장, adaptive sampling, raw batch write, 새 dependency 적용 없음.

## 표시·DB 작업 변화

`RecordingPresentation`이 GPS 수신기와 UI를 분리합니다. 현재 route가 보이고 앱 lifecycle이 resumed일 때만 1초 표시 타이머를 실행하며 상태·오류·버튼 변경은 즉시 반영합니다. 화면 OFF·백그라운드·다른 화면에 가려진 경우 타이머와 GPS에 따른 UI 갱신을 멈춥니다. 복귀 시 저장 중인 운동의 최신 상태를 반영하며 GPS 스트림과 DB 저장은 표시 여부에 의존하지 않습니다.

지도는 별도 notifier와 고정 widget으로 1초 숫자 갱신에서 분리했습니다. 표시 중 최신 좌표·경로를 최대 2초마다 반영하고 실제 변경이 없으면 알리지 않습니다. 경로 snapshot은 accepted point가 추가될 때만 무효화합니다. polyline은 완료된 불변 조각을 유지하고 최대 128개 edge의 열린 꼬리와 새 속도 구간만 구성합니다. segment 사이를 연결하지 않으며 속도 창의 경계와 계산은 기존 표시 정책과 같습니다.

GPS 저장 트랜잭션이 이미 경과 시간과 합계를 저장하므로 별도 5초 저장을 생략합니다. 마지막 저장 이후 5초가 지나도록 GPS 저장이 없으면 one-shot fallback으로 시간을 저장합니다. 저장 성공 시 다음 fallback을 예약하고 pause/finish/error/dispose에서 취소합니다. 정상 2초 수신 기준 시간당 트랜잭션은 약 2,520회에서 1,800회로 약 29% 감소합니다(시작·종료·GPS 공백 제외한 이론값). raw GPS 지연 저장은 도입하지 않았습니다.

## 검증

- 추가 자동 테스트 6개: 연속 GPS의 중복 시간 저장 제거·raw 전량 보존, GPS 공백의 5초 저장과 pause/resume/finish, 저장 실패 정리, 숨김·복귀와 지도 throttle, 실제 화면 lifecycle/route 가림, incremental 경로 조각·기존 속도 구간 일치.
- 추가 개인정보 기반 회귀 1개: S26 백업의 16개 세션과 raw GPS 25,200개로 생성한 전체 분석·포트폴리오 결과를 릴리즈 HEAD `273bcb254ea1b7fc4ff03e300f6e9226b05efcc4`의 계산 결과와 비교. 저장 거리·시간, 모든 분석 구간·좌표·split·100m/500m/1km 최고 구간·신뢰도·포트폴리오 좌표가 동일함. 입력 파일은 불변.
- 전체 `flutter test`: 149개 통과, skip 없음. 개인 입력 없는 CI는 기본 146개 실행, 개인정보 기반 3개 명시적 skip.
- `dart format` 검사·`flutter analyze`: 통과, 문제 없음.
- `flutter build apk --release --no-pub`: 성공. APK 서명 검증 통과, 기존 `CN=Diligent Life Release` 인증서 SHA-256과 일치. Android metadata는 versionName `1.0.1`, versionCode `13`으로 확인. APK SHA-256: `3B2E0BB90A699DD2739A725906B3EDD3529C92E31598510B99D8D71861B709E2`. 이번 단계에서 AAB는 빌드하지 않았으며 기존 1.0.0 AAB와 구분함.
- 분석 기준 파일은 릴리즈 HEAD의 `MovementAnalyzer` 결과와 `PortfolioAnalysis(sampleOverviewRoute(result.route, 600), result.fastest?.speed, movement: result).toMap()`으로 로컬 생성. `S26_BATTERY_DATA`에 테이블 배열 JSON, `S26_BATTERY_BASELINE`에 세션 id별 `{recordedMeters, elapsedSeconds, portfolio}` 기준 JSON을 지정하여 회귀 실행. 기존 2개 개인정보 테스트에는 각각 `LEGACY_BACKUP_DATA`, `S26_REGRESSION_DATA` 제공.
- 개인 백업·전체 좌표·기준값·검증 로그는 Git에서 제외한 `.tools/`에만 보관.

## 실제 측정 범위

2026-10-01 S26(SM-S942N)에 정식 서명 1.0.1(13)을 기존 1.0.0(12) 위에 업데이트 설치했습니다. 설치 전후 운동 16개·경로 9,841개·raw GPS 25,200개·몸무게 2개의 모든 원본 행과 열이 일치했습니다. 설치된 APK는 위 빌드 산출물과 SHA-256이 같고 기존 정식 서명 인증서와 일치합니다.

같은 날 17:28 KST, 배터리 55%·USB 충전 상태에서 앱 UID 10482의 batterystats와 기기 상태 baseline을 로컬에 기록했습니다. 시스템 통계는 초기화하지 않았습니다. USB 분리 후 실제 운동의 방전 측정이 필요하며 장시간 야외/화면 OFF·백그라운드·제조사 절전 기록과 실제 배터리 절감률 비교는 아직 미검증입니다. foreground service와 wake lock을 유지했으므로 GPS 자체 전력은 남아 있습니다. 원격 CI는 커밋 SHA별 GitHub Actions 결과로 확인하며, 1.0.0 CI 이력은 이 1.0.1 변경의 검증 결과와 구분합니다.
