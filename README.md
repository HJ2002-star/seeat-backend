# seeat-backend
Seeat 백엔드 (Spring Boot)

## 폴더 구조

```
├── docker-compose.yml       # 로컬 개발환경 (MySQL 8.0 + Redis 7.2)
├── db/
│   ├── schema/              # DDL (V3, V4, V4 마이그레이션)
│   ├── seed/                # 더미데이터 / 부하테스트 데이터
│   ├── docker/              # Docker 컨테이너 자동 초기화용 스키마·시드데이터
│   └── queries/             # 관리자용 조회 쿼리
├── docs/
│   ├── DOCKER_GUIDE.md       # 로컬 Docker 개발환경 가이드
│   ├── schema/                # DB 설계서 (V3, V4)
│   ├── reports/                # DB/DevOps 업무 보고서
│   └── presentation/           # 발표 준비 자료
└── .github/workflows/ci.yml  # GitHub Actions CI
```
