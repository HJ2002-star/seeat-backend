# SEEAT 로컬 개발환경 (Docker) 가이드

팀원 전체가 개별 설치 없이 명령어 한 줄로 동일한 로컬 실행 환경(MySQL + Redis, 스키마 및 더미데이터 자동 반영)을 띄우기 위한 Docker 구성입니다.

## 빠른 시작

```bash
git clone -b claude/database-setup-hw6lfy https://github.com/HJ2002-star/seeat-backend.git
cd seeat-backend
docker compose up
```

최초 실행 시 MySQL 컨테이너가 뜨면서 아래가 **전부 자동으로** 처리됩니다.
- 스키마 생성 (18개 테이블, DB 스키마 V4 기준)
- 더미데이터 삽입 (회원 21명, 상품 30개, 주문 30건 등)

## 접속 정보

| 서비스 | Host | Port | DB / 기타 | User | Password |
|---|---|---|---|---|---|
| MySQL | `localhost` | `3307` | `seafood_dummy_test` | `root` | `1234` |
| Redis | `localhost` | `6379` | - | - | - |

⚠️ **MySQL 포트가 기본값(3306)이 아니라 3307입니다.** 로컬에 MySQL을 이미 설치한 팀원과의 포트 충돌을 피하기 위해 호스트 쪽 포트만 변경했습니다 (컨테이너 내부는 3306 그대로).

`application-local.yml`의 datasource는 아래와 같이 설정하면 됩니다.
```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3307/seafood_dummy_test
    username: root
    password: 1234
```

## 구성 파일

| 파일 | 역할 |
|---|---|
| `docker-compose.yml` | MySQL 8.0 + Redis 7.2 컨테이너 정의 |
| `db/docker_schema_v4.sql` | 최초 기동 시 자동 실행되는 스키마 DDL (18개 테이블) |
| `db/docker_seed_data.sql` | 스키마 생성 직후 자동 실행되는 더미데이터 INSERT |

## 재초기화가 필요할 때

`docker-compose.yml`이나 스키마/시드 파일이 바뀌었는데 이미 한 번 컨테이너를 띄워본 적이 있다면, **볼륨에 예전 데이터가 남아있어 초기화 스크립트가 재실행되지 않습니다.** 아래처럼 완전히 지우고 다시 띄워야 합니다.

```bash
docker compose down -v   # 컨테이너 + 볼륨(데이터) 전부 삭제
docker compose up        # 처음부터 다시 초기화
```

## 아키텍처

```
GitHub (소스 코드, db/*.sql)
   │  git clone / pull
   ▼
로컬 개발 머신
   │  docker compose up
   ▼
Docker Engine
   ├─ 컨테이너: seeat-mysql (MySQL 8.0, host:3307 → 내부:3306)
   │     └─ 최초 기동 시 db/docker_schema_v4.sql, db/docker_seed_data.sql 자동 실행
   └─ 컨테이너: seeat-redis (Redis 7.2, host:6379 → 내부:6379)
        │
        ▼
   Spring Boot 백엔드 (컨테이너 밖, 로컬에서 실행)
   application-local.yml → localhost:3307 / localhost:6379로 연결
```

## 트러블슈팅

**증상**: `docker compose up` 실행 시 `Virtualization support not detected` 에러
- Windows에서 WSL2 미설치/미재부팅이 원인. `wsl --install` 실행 후 재부팅, Docker Desktop 재시도.

**증상**: MySQL 컨테이너가 `exited with code 1 (restarting)` 반복, 로그에 `Table 'seafood_dummy_test.member' doesn't exist`
- 스키마 파일이 `CREATE DATABASE ...; USE ...;`로 자기 자신만의 DB를 새로 만들어버려서, `MYSQL_DATABASE` 환경변수로 지정한 DB(`seafood_dummy_test`)가 아닌 엉뚱한 곳에 테이블이 생성되어 발생. `docker_schema_v4.sql`(CREATE DATABASE/USE 없는 버전)을 사용하면 해결됨 — 현재 반영되어 있음.

**증상**: MySQL 컨테이너는 정상인데 Workbench 접속이 안 됨 / 다른 DB가 보임
- Port를 `3306`이 아니라 **`3307`**로 입력했는지 확인 (로컬에 설치된 다른 MySQL로 잘못 접속되는 경우가 흔함).

---
작성: 박덕현 (DB/DevOps 담당) · 2026-07-30
