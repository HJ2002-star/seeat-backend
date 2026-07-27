-- ============================================================
-- DB 스키마 V3 → V4 마이그레이션
-- 근거: DB_Schema_V4_Review.pdf (2026-07-25), v2.1 API 명세서 확정 정책
-- 변경 3건 (전부 컬럼/값 추가만 있고 기존 데이터 변경 없음 → 무중단 적용):
--   1. 주문 취소: order.order_status 허용값에 CANCELLED 추가
--   2. 재고 관리: product.reserved_quantity 컬럼 추가 (결제 대기 중 재고 홀드/해제)
--   3. 비밀번호 재설정/이메일 인증: member에 reset_token / reset_token_expires_at /
--      email_verified 컬럼 추가
--
-- 적용 대상: 이미 V3 스키마가 생성되어 있는 DB (Railway `seeat`,
-- 로컬 `seeat`, `seafood_dummy_test` 등). USE 문으로 대상 스키마를 먼저 선택할 것.
-- ============================================================

-- 1. 주문 취소 — VARCHAR 컬럼이라 값 자체는 이미 저장 가능하지만,
--    허용값 목록을 문서화하는 COMMENT를 갱신해 CANCELLED를 명시한다.
ALTER TABLE `order`
    MODIFY COLUMN order_status VARCHAR(30) NOT NULL
    COMMENT 'PAYMENT_PENDING/PAYMENT_COMPLETED/PREPARING/SHIPPING/DELIVERED/PURCHASE_CONFIRMED/CANCELLED';

-- 2. 재고 관리 — 판매가능수량(stock_quantity)과 별도로 결제 대기 중 홀드된
--    수량을 추적. 실제 판매 가능 수량 = stock_quantity - reserved_quantity.
ALTER TABLE product
    ADD COLUMN reserved_quantity INT NOT NULL DEFAULT 0
        COMMENT '결제 대기 중 예약(홀드)된 수량' AFTER stock_quantity;

-- 3. 비밀번호 재설정 / 이메일 인증
ALTER TABLE `member`
    ADD COLUMN reset_token VARCHAR(255) NULL
        COMMENT '비밀번호 재설정 토큰' AFTER otp_secret_key,
    ADD COLUMN reset_token_expires_at DATETIME NULL
        COMMENT '재설정 토큰 만료일시' AFTER reset_token,
    ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT FALSE
        COMMENT '이메일 인증 여부' AFTER reset_token_expires_at;
