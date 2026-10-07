# v1.1.0(14) main baseline

2026-10-07. `feat/portfolio`의 기능 및 PR #1 UI polish를 main에 통합하는 기준 기록입니다. tag/GitHub Release는 만들지 않습니다. 이후 개발은 최신 main에서 별도 feat/fix/perf/docs/chore 브랜치를 생성해 진행합니다.

## 전체 diff 리뷰

초기 main과의 앱 전체 diff를 데이터, 기록 서비스, 분석, 보상, 공유, UI, 플랫폼 설정 및 테스트 경로로 검토했습니다. 생성된 프로젝트 설정·lockfile·아이콘과 문서도 포함 여부를 확인했습니다.

- schema 1→2→3→4 및 직접 업그레이드: 기존 일상·운동·경로를 유지하고 raw GPS 및 성장 테이블을 추가합니다. 자동 migration/reopen/foreign key 테스트를 유지합니다.
- format 1/schema 3 및 format 2/schema 4: staging 검증 후 원자적으로 교체하며 실패 시 롤백합니다. 기기 hardware cursor는 복원하지 않고 이전 백업은 현재 성장 상태를 유지합니다. 개인 S26 백업의 전체 필드 왕복 회귀도 실행합니다.
- GPS bestForNavigation/약 2초, raw 원본 보존, pause/복구 segment 분리, foreground location service 및 wake lock 유지. 화면 가시성에 따른 timer/map throttle과 GPS transaction 체크포인트 통합을 유지합니다.
- 만보기의 opt-in health FGS, boot/reset/중복 sample 정책, 날짜 경계 uncertainSteps와 일일 보상 제외를 확인했습니다. 실제 정확성·전력은 자동 테스트 통과와 구분합니다.
- 날짜/기간/version 기반 UNIQUE reward ledger, transaction, 일별 상한, 반복·동시 refresh 및 활동 삭제/재작성 중복 보상 방지를 확인했습니다.
- scrubber는 실제 저장 sample에 맞추며 segment/공백은 구간 합산에서 제외합니다. 분석 및 100m/500m/1km 결과를 변경하지 않습니다.
- 공유는 preview 후 시스템 선택, 시작·종료점 200m 보호와 숨긴 구간 재연결 방지. 성취 카드는 좌표를 포함하지 않습니다. 갤러리는 pending 쓰기 및 오류 시 정리를 유지합니다.
- Light/Dark, 작은 화면/큰 글꼴, semantic/터치 영역 테스트 및 UI polish 결과를 확인했습니다. 실제 TalkBack 음성 탐색 완료를 주장하지 않습니다.
- tracked diff에 secret, keystore, key.properties, APK/AAB 또는 개인 백업/DB/실사용 로그가 없습니다. 공개 UI 스크린샷은 synthetic 데이터입니다. 앱 소스에서 TODO/FIXME/개발용 print를 발견하지 않았습니다.

## 발견 및 최소 수정

만보기는 이벤트를 최대 30초 묶어 DB에 저장하는데 백업 내보내기는 대기 중인 센서를 flush하지 않았습니다. 실제 SQLite로 내보낸 백업에서 가상의 대기 걸음이 빠지는 회귀 테스트를 먼저 실패시킨 뒤, 내보내기 직전에 기존 StepService.flush를 기다리도록 수정했습니다. flush 저장 실패도 백업 성공으로 표시하지 않습니다. 센서 정책·GPS·보상·DB schema·백업 형식 변경은 없습니다.

## 검증 및 한계

- 로컬 format/analyze, 전체 Flutter 193개(개인 입력 4개 포함), native 정책 9개 검증. 개인 fixture는 ignored `.tools`에만 있으며 CI는 해당 4개를 명시적으로 skip합니다.
- Android release APK/AAB는 GitHub Actions에서 검증하며, CI의 일회용 서명은 정식 배포 서명과 구분합니다. 실제 PR/merge SHA별 최종 CI 결과는 해당 GitHub PR과 Actions에 기록됩니다.
- 기존 S26 정식 서명 업데이트/전체 데이터 보존, 실제 걸음 증가, 짧은 화면 OFF/GPS 동시 기록, 재부팅 자동 복원, 공유/갤러리 결과는 [S26 검증 이력](ux-v1.1.0.md)에 있습니다. 보행 수를 계수한 정확도 검증은 아닙니다.
- 현재 S26 미연결. Diligent_API36(Android 16/API 36)에서 일반 UI/navigation, theme 재시작 복원, 작은 화면 및 font scale 1.0/1.5/2.0, 성장·scrubber·share/gallery·schema 4 및 백업·lifecycle 검증 이력을 확인합니다. 상세 화면 근거는 [UI polish 기록](ui-polish-v1.1.md)에 있습니다.
- 남은 S26 검증: 계수한 실제 걸음 정확도와 누락률, 자정 경계 및 화면 OFF 센서 누적, 제조사 절전 하 장시간 health FGS/background, 충전하지 않은 동일 조건 배터리 비교, 장시간 야외 GPS 이동 품질, TalkBack 음성 탐색. 에뮬레이터 통과로 대체하지 않습니다.
- iOS는 macOS/Xcode/실기기 검증 전 출시 대상에서 제외합니다. 서버·로그인·랭킹과 지역 해금 UI는 구현하지 않습니다.
