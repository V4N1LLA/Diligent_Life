# Changelog

## 1.2.0+15 Activity Calendar / Timeline

- Portfolio → 월간 걸음 intensity 캘린더, 운동·탐험·성취 indicator, 날짜별 운동/성장 기록과 20일씩 조회하는 Timeline.
- 월간 걸음/운동 거리·횟수/탐험 합계와 데이터가 있는 이전 달 비교. 빈 날은 중립적이며 미래 활동 제외.
- 위치·경로·체중 없는 4:5 월간 카드 preview·시스템 공유·갤러리 저장.
- 기존 데이터의 읽기 전용 조회로 schema 5 / backup format 3, GPS·만보기·XP·캐릭터 규칙 유지. [날짜 정책과 검증](docs/activity-calendar.md).

## 1.2.0+15 Character / Profile Growth

- Today Lv/Title → 프로필, 로컬 벡터 아바타와 색/배경/프레임/엠블럼, 주요 활동 네 가지, 잠금/해금 타이틀 장착.
- Lv/누적 거리/탐험/업적 기반 cosmetic 해금과 10개씩 확인하는 보상함. 안정적인 ID·중복 방지·확인 상태 보존, 추가 XP와 자동 팝업 없음.
- 위치·체중 없는 1:1 프로필 카드 preview·시스템 공유·갤러리 저장. Light/Dark·작은 화면·큰 글꼴 대응.
- schema 5에 프로필 테이블 하나 추가, backup format 3 및 이전 format 1·2 읽기 지원. GPS/만보기/탐험/XP 규칙과 background 동작 변경 없음. [상세 기록](docs/character-profile.md).

## 1.2.0+15

- 운동 종료 후 신뢰할 수 있는 GPS 이동으로 지도 영역을 해금. 약 244m(서울) 셀, 60m 이동·50m 순변위·20초 이상 확인하며 원본과 기존 분석 결과는 유지.
- All-time Map의 방문 영역 overlay, 이번 운동 새 영역 구분, 누적/월별 발견 수, 선택적 과거 raw GPS 재계산.
- 영역별 10 XP, 일일 3곳 탐험 퀘스트, 1/10/50/100개 업적과 타이틀. 기존 보상 원장으로 중복 지급 방지.
- 위치 없이 개수만 담는 탐험 카드 preview·시스템 공유·갤러리 저장.
- 기존 schema 4 탐험 이벤트와 backup format 2 재사용. 새 테이블은 복원 시 비우는 파생 스캔 캐시뿐이며 사용자 데이터 migration은 필요 없음.
- 가시 영역/확대 수준별 지도 인덱스, polygon 캐시, 운동 종료 후 isolate 계산. GPS/만보기/배터리 정책과 dependency는 변경 없음.
- 실제 GPS 해금 품질·장시간 배터리·화면 OFF 센서·TalkBack 음성 탐색은 S26 실기기 검증 필요.

## 1.1.0+14 main baseline

- v1.1 기능과 UI polish를 main baseline으로 통합. 데이터·서비스·보상·프라이버시 리뷰와 검증 범위는 [baseline 기록](docs/baseline-v1.1.md) 참고.
- 백업 내보내기 전에 native 센서 대기 걸음을 flush해 최근 걸음 누락 방지. flush 실패 시 내보내기 중단, 회귀 테스트 2개 추가. GPS·XP 규칙·schema·백업 형식은 유지.
- 실제 걸음 정확도, 자정/화면 OFF 센서, 장시간 health FGS, 배터리, 야외 GPS, TalkBack 음성 탐색은 S26 최종 검증 항목으로 유지.

## 1.1.0+14 UI polish

- Theme 제목과 선택 control 분리. 넓은 화면은 full-width segmented control, 좁은 화면·큰 글꼴은 세로 선택. 선택 상태·최소 터치 영역·로컬 저장 유지.
- 공통 spacing/radius/typography/surface/progress token, sage 활동 강조와 purple 성장 강조. Today는 레벨 → 오늘 걸음 → 운동 시작 → 일일 퀘스트 2개 → 주간 요약 순서.
- 성장 화면의 일일/주간 퀘스트·잠금 업적·장착 타이틀 구분, 다음 레벨까지 XP 표시. Portfolio는 핵심 거리/시간·활동 trend·선택 기간의 일상 걸음·체중·경로·기록·리포트 순서. 집계 설명은 접어서 표시.
- 운동 상세는 지도 → 핵심 통계 → 위치/시간/페이스 scrubber → 선택 구간 → 속도 흐름 → 상세 분석. 공유 preview와 Settings section 정리.
- GPS/만보기/XP 규칙·schema 4·backup format 2·native service·배터리 최적화 변경 없음. 검증 범위·실기기 제한은 [UI polish 기록](docs/ui-polish-v1.1.md) 참고.


## 1.1.0+14

- GPS와 분리된 Android step counter 만보기, 오늘 목표·최근 7일·주/월 걸음 통계, health foreground service 및 재시작/재부팅/reset/중복 처리. 자정 수신 공백은 구분해 표시.
- Today의 운동 CTA를 유지하면서 compact Lv/XP/타이틀과 주간 요약 추가. 기술 정보는 접힌 상세 분석으로 이동.
- 실제 sample에 맞추는 지도/그래프 scrubber와 양쪽 구간 handle, 평균 속도/페이스, 제한된 haptic. 기존 분석 결과 유지.
- 날짜별 상한과 versioned UNIQUE 보상 원장의 XP, 일일/주간 Quest, 6개 Achievement와 1개 장착 Title. 체중·칼로리·수동 입력 XP 없음.
- 운동 4:5 및 성취 1:1 이미지 preview 후 공유/갤러리 저장, 시작·종료점 위치 보호 유지. 시스템/라이트/다크 로컬 저장.
- DB schema 4에 새 테이블만 추가, backup format 2 및 이전 format 1 호환, 기기 sensor cursor 제외. 탐험은 확장 가능한 모델만 추가.
- S26 정식 서명 업데이트와 기존 전체 데이터 보존, 실제 걸음 증가·화면 OFF/GPS 동시 기록·재부팅 복원·테마·scrubber·공유·갤러리 저장 확인. 실제 보행 대비 정확도·자정·장시간 배터리 비교는 남음. 범위와 제한은 [1.1.0 UX 기록](docs/ux-v1.1.0.md) 참고.

## 1.0.1+13

- GPS bestForNavigation·약 2초 수집, raw 원본 저장, 필터·거리·100m/500m/1km 분석 정책, foreground service와 wake lock 유지. 새 dependency·DB·백업 형식 변경 없음.
- 기록 화면이 현재 화면이며 앱이 resumed일 때만 1초 표시 타이머 실행. GPS 수신은 화면 렌더링과 분리하며 화면 OFF·백그라운드·다른 화면에 가려진 상태에서는 기록 UI 갱신 중단, 복귀 시 즉시 최신 상태 반영.
- 지도 데이터는 표시 중 최대 2초마다 갱신. 불변 경로 snapshot 재사용, 완료 polyline 조각·속도 구간 캐시와 새 점의 incremental 처리로 전체 경로 재생성 제거.
- GPS 저장 트랜잭션의 시간·누적 통계 체크포인트를 재사용. 5초간 저장이 없을 때만 시간 저장을 실행하며 일시정지·종료·오류 시 기존 정리 동작 유지. raw GPS를 메모리에 모아 지연 저장하지 않음.
- 실제 S26 16개 세션의 전체 분석·포트폴리오 결과를 1.0.0 릴리즈 HEAD와 비교해 동일함을 검증. 기본 146개 + 개인정보 기반 3개, 총 149개 테스트 통과. 자세한 범위는 [배터리 최적화 1차 검증](docs/battery-v1.0.1.md) 참고.

- S26에 기존 정식 서명 1.0.0(12) 위로 업데이트 설치 완료. 운동 16개·경로 9,841개·raw GPS 25,200개·몸무게 2개의 모든 원본 행과 열 보존, 동일 정식 서명과 설치 APK 일치 확인. 배터리 측정 baseline 기록 완료; 실제 절감률 측정은 남아 있음.

## 1.0.0+12

- Android 정식 서명 APK/AAB 빌드 및 서명 검증 완료. release 서명 설정이 없거나 불완전하면 빌드 실패; CI는 일회용 검증키 사용.
- Android 버전과 앱 표시를 1.0.0(12)로 동기화. 새 기능·dependency·DB schema 3·backup format 1 변경 없음.
- S26(SM-S942N)에 정식 서명 앱 설치 및 기존 기록 복원 완료. 일일 기록 2개·운동 11개·경로 3,366개·raw GPS 8,458개의 모든 원본 행과 열이 복원 전후 일치.
- 기본 테스트 140개 통과 및 개인정보 기반 후속 테스트 2개 통과. CI에는 개인 입력을 제공하지 않아 해당 2개는 명시적으로 skip.
- 앞으로 실기기 테스트는 S26만 사용하며 S20은 사용하지 않음. 과거 S20 검증 결과는 이력으로 보존.
- 1.0.0 릴리즈 커밋 `273bcb2`의 [GitHub Actions 실행 35820608488](https://github.com/V4N1LLA/Diligent_Life/actions/runs/35820608488) 성공: format/analyze/test/release APK/AAB 모두 통과(2026-10-01 확인). 이후 1.0.1 변경은 해당 실행 범위 밖.
- 남은 검증: S26 실제 TalkBack 음성 탐색, 장시간 야외·화면 OFF·백그라운드·제조사 절전 환경 GPS 기록. 배포 준비: 서명키·자격 증명 외부 백업, 배포 채널/Play 설정. 현재 HEAD 원격 CI 결과는 [최종 릴리즈 검증 기록](docs/release-v1-final.md#remote-github-actions) 참고.

## 1.0.0-rc1+11

새 기능·dependency·DB 버전 변경 없이 v0.9.0의 첫 안정 릴리즈 후보를 준비했습니다. 아래는 RC1 당시 변경 이력이며 현재 상태는 1.0.0+12 항목을 참고하세요.

- SQLite v2 생성 시 v3 열이 선행 생성되어 2→3 업그레이드가 실패하던 경로 수정; 기존 행 보존·재시작 복구 검증.
- 초기 복구 실패 시 DB·recorder 자원 정리, 지도 오류와 빈 상태 중복 표시 수정.
- 버전 표시 일원화, 기존 잎 모양의 앱 아이콘 및 Light/Dark Android 스플래시 적용.
- 사용하지 않는 이전 분석기를 테스트 지원 코드로 이동하고 synthetic 대량 데이터 검증 유지.
- 손상 백업·접근성·대량 데이터 회귀 검사 보강. GitHub Actions에서 release APK/AAB 컴파일.
- RC1 당시 정식 서명 설정 지원 및 키가 없는 경우 개발용 서명으로 검증. 1.0.0+12에서는 서명 설정이 없으면 release 빌드가 실패하도록 변경.

## 0.9.0+10

- 저장 거리와 분석 거리 구분, 이동·정지·미분류 및 최고속도 신뢰도 개선.
- GPS 오차와 최소 개선 임계값을 반영한 개인 기록 판정.
- split, 전후반 속도/페이스, 속도 분포, 정지 통계, 최고 구간 지도 및 GPS 품질 요약.
- raw GPS와 기존 운동 합계 보존, 재분석 및 개인 실사용 데이터 회귀 검증.

## 0.1.0–0.8.0

오늘 기록·GPS 운동·포트폴리오·리포트·지도·공유·백업 기능과 minimal/calm UI를 구축했습니다. 자세한 내용과 당시 검증 범위는 [개발 이력](docs/development-history.md)을 참고하세요.
