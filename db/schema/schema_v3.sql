-- ============================================================
-- Seeat 백엔드 DB 스키마 (수산물 거래 플랫폼)
-- 기준 문서: DB_schema_v3.docx (V3, 2026-07)
-- 대상: MySQL 8.0
-- 범위: 18개 테이블 / 26개 관계. 정규화 검토 및 인덱스·제약조건
--       설계는 문서 기준대로 이번 범위에서 제외 (FK로 발생하는
--       기본 인덱스 외 추가 인덱스 없음).
-- 사용법: 로컬 MySQL에서 문법 검증 후, Railway 공유 DB에 반영.
-- ============================================================

CREATE DATABASE IF NOT EXISTS seeat
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE seeat;

-- ------------------------------------------------------------
-- 1. member (회원)
-- ------------------------------------------------------------
CREATE TABLE `member` (
    user_id            BIGINT       NOT NULL AUTO_INCREMENT,
    email              VARCHAR(100) NOT NULL,
    password_hash      VARCHAR(255) NOT NULL,
    role               VARCHAR(20)  NOT NULL COMMENT 'ENUM: BUYER/SELLER/ADMIN',
    nickname           VARCHAR(50)  NOT NULL,
    phone_number       VARCHAR(20)  NOT NULL,
    profile_image_url  VARCHAR(255) NULL,
    otp_secret_key     VARCHAR(255) NULL COMMENT 'role=ADMIN 전용, TOTP 시드값',
    is_withdrawn       BOOLEAN      NOT NULL DEFAULT FALSE,
    withdrawn_at       DATETIME     NULL,
    created_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uk_member_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 2. category (카테고리, 자기참조)
-- ------------------------------------------------------------
CREATE TABLE category (
    category_id         BIGINT      NOT NULL AUTO_INCREMENT,
    category_name       VARCHAR(50) NOT NULL,
    parent_category_id  BIGINT      NULL,
    PRIMARY KEY (category_id),
    CONSTRAINT fk_category_parent
        FOREIGN KEY (parent_category_id) REFERENCES category (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 3. seller_business_info (판매자사업자정보)
-- ------------------------------------------------------------
CREATE TABLE seller_business_info (
    user_id                        BIGINT      NOT NULL,
    business_registration_number   VARCHAR(10) NOT NULL,
    representative_name            VARCHAR(50) NOT NULL,
    opening_date                   DATE        NOT NULL,
    auth_status                    VARCHAR(20) NOT NULL COMMENT 'PENDING/VERIFIED/REJECTED',
    verified_at                    DATETIME    NULL,
    PRIMARY KEY (user_id),
    UNIQUE KEY uk_seller_business_reg_no (business_registration_number),
    CONSTRAINT fk_seller_business_info_member
        FOREIGN KEY (user_id) REFERENCES `member` (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 4. delivery_address (배송지)
-- ------------------------------------------------------------
CREATE TABLE delivery_address (
    address_id      BIGINT       NOT NULL AUTO_INCREMENT,
    user_id         BIGINT       NOT NULL,
    alias           VARCHAR(30)  NOT NULL,
    receiver_name   VARCHAR(50)  NOT NULL,
    receiver_phone  VARCHAR(20)  NOT NULL,
    address         VARCHAR(255) NOT NULL,
    is_default      BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY (address_id),
    CONSTRAINT fk_delivery_address_member
        FOREIGN KEY (user_id) REFERENCES `member` (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 5. cart (장바구니)
-- ------------------------------------------------------------
CREATE TABLE cart (
    cart_id  BIGINT NOT NULL AUTO_INCREMENT,
    user_id  BIGINT NOT NULL,
    PRIMARY KEY (cart_id),
    UNIQUE KEY uk_cart_user_id (user_id),
    CONSTRAINT fk_cart_member
        FOREIGN KEY (user_id) REFERENCES `member` (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 6. product (상품)
-- ------------------------------------------------------------
CREATE TABLE product (
    product_id            BIGINT        NOT NULL AUTO_INCREMENT,
    seller_id             BIGINT        NOT NULL,
    category_id           BIGINT        NOT NULL,
    name                   VARCHAR(100)  NOT NULL,
    origin                 VARCHAR(50)   NOT NULL,
    storage_type           VARCHAR(20)   NOT NULL,
    weight                 DECIMAL(8,2)  NULL,
    weight_unit            VARCHAR(10)   NULL,
    is_mandatory_auction   BOOLEAN       NOT NULL DEFAULT FALSE,
    price                  DECIMAL(10,2) NOT NULL,
    stock_quantity         INT           NOT NULL DEFAULT 0,
    status                 VARCHAR(20)   NOT NULL COMMENT 'PENDING_REVIEW/ON_SALE/SOLD_OUT/HIDDEN',
    created_at             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (product_id),
    CONSTRAINT fk_product_seller
        FOREIGN KEY (seller_id) REFERENCES `member` (user_id),
    CONSTRAINT fk_product_category
        FOREIGN KEY (category_id) REFERENCES category (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 7. product_image (상품이미지)
-- ------------------------------------------------------------
CREATE TABLE product_image (
    image_id    BIGINT       NOT NULL AUTO_INCREMENT,
    product_id  BIGINT       NOT NULL,
    image_url   VARCHAR(255) NOT NULL,
    sort_order  TINYINT      NOT NULL COMMENT '0~4, 최대 5장',
    PRIMARY KEY (image_id),
    CONSTRAINT fk_product_image_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 8. product_tag (상품태그)
-- ------------------------------------------------------------
CREATE TABLE product_tag (
    tag_id      BIGINT      NOT NULL AUTO_INCREMENT,
    product_id  BIGINT      NOT NULL,
    tag_name    VARCHAR(30) NOT NULL,
    PRIMARY KEY (tag_id),
    CONSTRAINT fk_product_tag_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 9. product_faq (상품문의)
-- ------------------------------------------------------------
CREATE TABLE product_faq (
    faq_id      BIGINT       NOT NULL AUTO_INCREMENT,
    product_id  BIGINT       NOT NULL,
    user_id     BIGINT       NOT NULL,
    content     VARCHAR(500) NOT NULL,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (faq_id),
    CONSTRAINT fk_product_faq_product
        FOREIGN KEY (product_id) REFERENCES product (product_id),
    CONSTRAINT fk_product_faq_member
        FOREIGN KEY (user_id) REFERENCES `member` (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 10. cart_item (장바구니상품)
-- ------------------------------------------------------------
CREATE TABLE cart_item (
    cart_product_id  BIGINT NOT NULL AUTO_INCREMENT,
    cart_id          BIGINT NOT NULL,
    product_id       BIGINT NOT NULL,
    quantity         INT    NOT NULL DEFAULT 1,
    PRIMARY KEY (cart_product_id),
    CONSTRAINT fk_cart_item_cart
        FOREIGN KEY (cart_id) REFERENCES cart (cart_id),
    CONSTRAINT fk_cart_item_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 11. order (주문)  -- `order`는 MySQL 예약어라 백틱 필요
-- ------------------------------------------------------------
CREATE TABLE `order` (
    order_id          BIGINT        NOT NULL AUTO_INCREMENT,
    buyer_id          BIGINT        NOT NULL,
    address_id        BIGINT        NOT NULL,
    order_status      VARCHAR(30)   NOT NULL COMMENT 'PAYMENT_PENDING/PAYMENT_COMPLETED/PREPARING/SHIPPING/DELIVERED/PURCHASE_CONFIRMED',
    total_amount      DECIMAL(10,2) NOT NULL,
    request_message   VARCHAR(255)  NULL,
    created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id),
    CONSTRAINT fk_order_buyer
        FOREIGN KEY (buyer_id) REFERENCES `member` (user_id),
    CONSTRAINT fk_order_address
        FOREIGN KEY (address_id) REFERENCES delivery_address (address_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 12. order_item (주문상품)
-- ------------------------------------------------------------
CREATE TABLE order_item (
    order_product_id  BIGINT NOT NULL AUTO_INCREMENT,
    order_id          BIGINT NOT NULL,
    product_id        BIGINT NOT NULL,
    quantity          INT    NOT NULL,
    PRIMARY KEY (order_product_id),
    CONSTRAINT fk_order_item_order
        FOREIGN KEY (order_id) REFERENCES `order` (order_id),
    CONSTRAINT fk_order_item_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 13. payment (결제)
-- ------------------------------------------------------------
CREATE TABLE payment (
    payment_id          BIGINT       NOT NULL AUTO_INCREMENT,
    order_id            BIGINT       NOT NULL,
    payment_method      VARCHAR(20)  NOT NULL COMMENT 'CARD/KAKAO_PAY/TOSS_PAY',
    pg_transaction_id   VARCHAR(100) NOT NULL,
    PRIMARY KEY (payment_id),
    UNIQUE KEY uk_payment_order_id (order_id),
    UNIQUE KEY uk_payment_pg_transaction_id (pg_transaction_id),
    CONSTRAINT fk_payment_order
        FOREIGN KEY (order_id) REFERENCES `order` (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 14. delivery (배송)
-- ------------------------------------------------------------
CREATE TABLE delivery (
    delivery_id       BIGINT      NOT NULL AUTO_INCREMENT,
    order_id          BIGINT      NOT NULL,
    carrier           VARCHAR(50) NULL,
    tracking_number   VARCHAR(50) NULL,
    PRIMARY KEY (delivery_id),
    UNIQUE KEY uk_delivery_order_id (order_id),
    CONSTRAINT fk_delivery_order
        FOREIGN KEY (order_id) REFERENCES `order` (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 15. order_status_history (주문상태이력)
-- ------------------------------------------------------------
CREATE TABLE order_status_history (
    history_id    BIGINT      NOT NULL AUTO_INCREMENT,
    order_id      BIGINT      NOT NULL,
    status_value  VARCHAR(30) NOT NULL,
    changed_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (history_id),
    CONSTRAINT fk_order_status_history_order
        FOREIGN KEY (order_id) REFERENCES `order` (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 16. settlement (정산)
-- ------------------------------------------------------------
CREATE TABLE settlement (
    settlement_id  BIGINT        NOT NULL AUTO_INCREMENT,
    seller_id      BIGINT        NOT NULL,
    order_id       BIGINT        NOT NULL,
    amount         DECIMAL(10,2) NOT NULL DEFAULT 0,
    status         VARCHAR(20)   NOT NULL COMMENT 'PENDING/COMPLETED',
    settled_at     DATETIME      NULL,
    PRIMARY KEY (settlement_id),
    UNIQUE KEY uk_settlement_order_id (order_id),
    CONSTRAINT fk_settlement_seller
        FOREIGN KEY (seller_id) REFERENCES `member` (user_id),
    CONSTRAINT fk_settlement_order
        FOREIGN KEY (order_id) REFERENCES `order` (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 17. notification (알림)
-- ------------------------------------------------------------
CREATE TABLE notification (
    notification_id  BIGINT       NOT NULL AUTO_INCREMENT,
    user_id          BIGINT       NOT NULL,
    order_id         BIGINT       NULL,
    type             VARCHAR(30)  NOT NULL COMMENT 'ORDER_CONFIRMED/SHIPPING_STARTED/DELIVERY_COMPLETED',
    message          VARCHAR(255) NOT NULL,
    is_read          BOOLEAN      NOT NULL DEFAULT FALSE,
    sent_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (notification_id),
    CONSTRAINT fk_notification_member
        FOREIGN KEY (user_id) REFERENCES `member` (user_id),
    CONSTRAINT fk_notification_order
        FOREIGN KEY (order_id) REFERENCES `order` (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 18. report (신고)
-- ------------------------------------------------------------
CREATE TABLE report (
    report_id             BIGINT       NOT NULL AUTO_INCREMENT,
    target_type           VARCHAR(20)  NOT NULL COMMENT 'USER/PRODUCT',
    reported_user_id      BIGINT       NULL,
    reported_product_id   BIGINT       NULL,
    reporter_id           BIGINT       NOT NULL,
    reason                VARCHAR(255) NOT NULL,
    status                VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (report_id),
    CONSTRAINT fk_report_reported_user
        FOREIGN KEY (reported_user_id) REFERENCES `member` (user_id),
    CONSTRAINT fk_report_reported_product
        FOREIGN KEY (reported_product_id) REFERENCES product (product_id),
    CONSTRAINT fk_report_reporter
        FOREIGN KEY (reporter_id) REFERENCES `member` (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
