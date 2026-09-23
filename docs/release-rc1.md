# 1.0.0-rc1 검증 기록

2026-09-22 자동 검증 / 2026-09-22–23 실기기 검증, Windows / Flutter 3.47.2 / Dart 3.13.2. v0.9.0+10에서 1.0.0-rc1+11로 변경하며 DB schema 3과 backup format 1을 유지합니다.

## 완료

- `dart format .`, `flutter analyze`: 통과, 경고 없음.
- `flutter test`: 개인 로컬 회귀 입력을 포함해 142개 통과. CI에는 개인 파일을 제공하지 않으므로 140개 실행, 해당 2개는 명시적으로 skip.
- SQLite 파일 생성·닫기·다시 열기: 1→3, 2→3, 1→2→3, 3→3. 일일 기록·기존 운동·경로 보존, FK 검사, 기록 중 세션의 체크포인트 재시작 후 일시정지 복구.
- 기존 실제 `.diligent` export → 임시 DB import → export의 모든 원본 행 일치. 원본 파일 불변. 손상·잘림·중복·잘못된 UTF-8·미지원 버전·orphan·잘못된 수치·완료 행 오류 거부. 교체 실패 롤백과 진행 중 운동 차단.
- Light/Dark 자동 접근성 검사: 오늘·운동·설정·빈 리포트의 Android 터치 영역, 접근성 이름, 텍스트 대비. 기존 320px/2배 글꼴·포트폴리오·상세·공유·리포트 위젯 회귀 유지.
- 권한 거부, GPS OFF, 재개, 지도 타일 오류와 재시도, 빈 상태, 저장 실패, 종료 확인, 공유 미리보기 회귀 통과.
- 기존 12,005/24,001 표본 검사 유지. 추가 48,024 raw GPS / 24개 세션의 Portfolio·report·All-time Map 데이터 준비 검사 통과, 표시 좌표 12,000개. 최초 포트폴리오 1.7초(개별 실행)~11.8초(release 빌드 동시 실행), 모든 단계 30초 이내. 이 수치는 PC 테스트이며 실기기 프레임 성능 측정이 아님.
- 실제 S26 로컬 사본 분석은 v0.9와 동일: 저장 2584.6326m / 분석 2414.2759m / 최고 5.9715km/h / 미분류 530.605초. 실기기 S26은 접근·조작하지 않음.
- release APK 58.6MB / AAB 56.6MB 빌드 성공. APK signature 검증 성공, 개발용 키임. 앱 이름 Diligent Life, 패키지 com.v4n1lla.diligent_life, versionName 1.0.0-rc1, versionCode 11 확인.
- SM-G988N에 release APK 업데이트 설치·실행 요청 성공. 설치 전 운동 8개 / 경로 2,546개 / raw 4,972개 / 일일 기록 1개를 별도 로컬 사본으로 보존. 기존 DB 삭제·초기화 없음.
- production 코드 TODO/FIXME/debug print 없음. pubspec.lock 변경 및 새 dependency 없음.

## 출시 전 미완료

- 정식 서명키와 배포 채널 확정. 현재 APK/AAB는 개발용 서명의 검증용 산출물.
- 실제 TalkBack 음성 탐색: 서비스 활성화까지 확인했으나 Samsung TalkBack 최초 설정이 전화 권한을 요구하여 완료하지 못함. 해당 권한은 허용하지 않았으며 접근성 설정은 원상 복구. 자동 semantic 검사 통과와 구분함.
- RC 변경사항의 원격 GitHub Actions 실행. workflow에는 format/analyze/test/release APK/AAB 검사를 구성했으나 현재 작업은 아직 커밋·push하지 않았으므로 RC 원격 성공 상태는 없음.
- iOS는 이번 Android RC 출시 대상 밖이며 macOS/Xcode·실기기 검증 전 배포하지 않음.

## SM-G988N release 실기기 후속 결과 (9월 22–23일)

- 오늘 → 운동 시작 → GPS 연결 → 짧은 화면 OFF → 강제 종료 → 재실행: 마지막 50초 체크포인트를 일시정지로 복원. 잠금 해제 대기 시간은 추가되지 않았고 명시적 재개 후 최종 85초로 종료.
- 상세 → 운동 이미지 미리보기 → Android 공유창 진입·취소 확인. 외부 전송 없음.
- 포트폴리오와 월간 리포트가 동일하게 9회 / 04:53:09 / 13.34km로 반영. 리포트 이미지 생성·접근성 이름 확인.
- 실기기 Light + font_scale 2.0 공유 화면에서 잘림 없이 버튼 접근. Dark All-time Map 8개 운동의 타일·분리 경로 표시 확인. 앱 정보 1.0.0-rc1 (11) 확인. 글꼴 1.0 / Dark / 접근성 비활성 원상 복구.
- 실제 Android 파일 저장기로 백업 export 성공. 설치 전 SQLite 사본과 원본 네 테이블의 모든 열 일치: daily 1 / session 8 / route 2546 / raw 4972.
- 검증용 session 12만 앱의 삭제 확인을 거쳐 제거. 삭제 후 다시 export하여 위 네 테이블 전체가 설치 전과 완전히 동일함을 확인. 테스트 원본 12개와 경로 3개만 제거됨. 사용자 원본은 불변.
- 검증용 운동은 정지 상태에서 0m이며 raw 12개, segment 1/2/4. segment 내부 최대 수신 간격 약 10초. 짧은 화면 OFF 후 수신 지속은 확인했지만 이 표본으로 장시간 백그라운드 무공백을 보장하지 않음.

장시간 야외·제조사 절전 환경의 연속 기록과 실제 TalkBack 음성 탐색은 미검증입니다. 이번 후속 작업에는 앱 코드 변경이 없어 기존 142개 테스트와 APK/AAB 빌드 결과를 유지하며 검증 기록만 갱신했습니다.

## 남은 blocker 재확인 (2026-09-23)

Samsung TalkBack 13.5.02.8 활성화 후 `com.samsung.android.accessibility.talkback.permission.PermissionRequestActivity`의 “휴대전화 액세스를 허용하시겠습니까?” 안내가 다시 전면에 표시됨을 확인했습니다. `READ_PHONE_STATE`는 허용되지 않은 상태입니다. Diligent Life의 화면·권한 요청이 아닌 TalkBack 자체 초기 설정 단계이므로 앱 코드 수정 대상이 아닙니다. 앱 내부의 실제 음성 탐색은 미완료로 유지하며 전화 권한은 허용하지 않았습니다. 접근성 서비스 목록(빈 값)과 accessibility_enabled=0을 복원했습니다. 정식 서명키는 생성하지 않았습니다.
