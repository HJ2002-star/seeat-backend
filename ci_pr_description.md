## 변경 사항
GitHub Actions 기반 CI(빌드+테스트 자동화) 워크플로 추가

- main 브랜치로 push 되거나 main 대상 PR이 열릴 때마다 자동으로 `./gradlew build` 실행
- 배포(CD)는 포함하지 않음 — 백엔드가 아직 개발 중이라 CI(빌드/테스트 자동화)만 먼저 구축하고, 배포 자동화는 안정화된 뒤 추가 예정

## 확인 필요
- Java 버전을 17로 설정했는데, build.gradle의 sourceCompatibility와 다르면 수정 필요 (위성훈님 확인 부탁드려요)

## 테스트
- 이 PR이 merge되면 Actions 탭에서 자동으로 빌드가 도는지 확인
