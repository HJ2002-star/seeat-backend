-- ============================================================
-- 부하 테스트용 대량 더미데이터 시드 스크립트
-- 목적: 스키마가 실제 데이터양(수천~수만 건)에서도 admin_queries.sql의
--       집계 쿼리들이 문제없이 도는지, 응답 속도가 어떻게 변하는지 확인.
--
-- 주의:
--  - 실서비스용 Railway `seeat` 스키마가 아니라 별도 테스트 스키마
--    (예: seafood_dummy_test)에서 실행할 것을 권장.
--  - 기존 데이터를 건드리지 않고 "새로운 코호트"를 추가하는 방식이라
--    여러 번 실행해도 데이터가 계속 누적됨(재실행 가능, 이메일/사업자
--    번호/PG거래ID는 UUID 기반이라 유니크 충돌 없음).
--  - 주문 1건은 반드시 한 판매자의 상품으로만 구성된다고 가정
--    (settlement이 주문 1건당 1행이라 여러 판매자가 섞이면 정산 귀속이
--    모호해지므로, 이 스크립트는 실제 서비스 규칙에 맞춰 단일 판매자로 제한).
--
-- 사용법: 아래 "규모 설정" 값만 바꿔서 그대로 실행.
-- ============================================================

SET SESSION cte_max_recursion_depth = 100000;

-- ------------------------------------------------------------
-- 규모 설정
-- ------------------------------------------------------------
SET @n_new_sellers        = 100;   -- 신규 판매자 수
SET @n_new_buyers         = 2000;  -- 신규 구매자 수
SET @max_products_per_seller = 20; -- 판매자 1명당 최대 상품 수
SET @n_new_orders         = 10000; -- 신규 주문 수
SET @max_items_per_order  = 3;     -- 주문 1건당 최대 상품 종류 수

-- ------------------------------------------------------------
-- 0. 카테고리 시드 (테이블이 비어있을 때만)
-- ------------------------------------------------------------
INSERT INTO category (category_name, parent_category_id)
SELECT * FROM (
  SELECT '고등어' AS category_name, NULL AS parent_category_id UNION ALL
  SELECT '갈치', NULL UNION ALL SELECT '전복', NULL UNION ALL
  SELECT '대게', NULL UNION ALL SELECT '광어', NULL UNION ALL
  SELECT '우럭', NULL UNION ALL SELECT '멍게', NULL UNION ALL
  SELECT '새우', NULL UNION ALL SELECT '오징어', NULL UNION ALL SELECT '문어', NULL
) AS seed_categories
WHERE NOT EXISTS (SELECT 1 FROM category LIMIT 1);

-- ------------------------------------------------------------
-- 1. 신규 판매자 (member + seller_business_info)
--    인증 상태 분포: VERIFIED 70% / PENDING 15% / REJECTED 15%
-- ------------------------------------------------------------
INSERT INTO `member` (email, password_hash, role, nickname, phone_number, created_at)
WITH RECURSIVE seq AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM seq WHERE n < @n_new_sellers
)
SELECT
  CONCAT('loadtest_seller_', UUID_SHORT(), '@seeat.test'),
  '$2a$10$loadTestDummyPasswordHashXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
  'SELLER',
  CONCAT('부하테스트판매자', n),
  CONCAT('010', LPAD(FLOOR(RAND()*100000000), 8, '0')),
  DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*365) DAY)
FROM seq;

SET @seller_start_id = LAST_INSERT_ID();
SET @seller_end_id   = @seller_start_id + @n_new_sellers - 1;

SET @brn_seq_start = COALESCE(
  (SELECT MAX(CAST(business_registration_number AS UNSIGNED))
   FROM seller_business_info WHERE business_registration_number LIKE '9%'),
  9000000000);

INSERT INTO seller_business_info (user_id, business_registration_number, representative_name, opening_date, auth_status, verified_at)
SELECT
  m.user_id,
  LPAD(@brn_seq_start + (m.user_id - @seller_start_id) + 1, 10, '0'),
  CONCAT('대표자', m.user_id),
  DATE_SUB(CURDATE(), INTERVAL FLOOR(RAND()*3000) DAY),
  ELT(FLOOR(1 + RAND()*20),
      'VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED',
      'VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED','VERIFIED',
      'PENDING','PENDING','PENDING',
      'REJECTED','REJECTED','REJECTED'),
  CASE WHEN RAND() < 0.7 THEN DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*300) DAY) ELSE NULL END
FROM `member` m
WHERE m.user_id BETWEEN @seller_start_id AND @seller_end_id;

-- ------------------------------------------------------------
-- 2. 신규 구매자 (member + delivery_address + cart)
-- ------------------------------------------------------------
INSERT INTO `member` (email, password_hash, role, nickname, phone_number, created_at)
WITH RECURSIVE seq AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM seq WHERE n < @n_new_buyers
)
SELECT
  CONCAT('loadtest_buyer_', UUID_SHORT(), '@seeat.test'),
  '$2a$10$loadTestDummyPasswordHashXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
  'BUYER',
  CONCAT('부하테스트구매자', n),
  CONCAT('010', LPAD(FLOOR(RAND()*100000000), 8, '0')),
  DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*365) DAY)
FROM seq;

SET @buyer_start_id = LAST_INSERT_ID();
SET @buyer_end_id   = @buyer_start_id + @n_new_buyers - 1;

INSERT INTO delivery_address (user_id, alias, receiver_name, receiver_phone, address, is_default)
SELECT m.user_id, '집', CONCAT('수령인', m.user_id), m.phone_number,
       CONCAT('테스트시 테스트구 테스트로 ', FLOOR(RAND()*999), '번지'), TRUE
FROM `member` m
WHERE m.user_id BETWEEN @buyer_start_id AND @buyer_end_id;

INSERT INTO cart (user_id)
SELECT m.user_id FROM `member` m
WHERE m.user_id BETWEEN @buyer_start_id AND @buyer_end_id;

-- ------------------------------------------------------------
-- 3. 신규 상품 (VERIFIED 판매자만 상품 보유 — 가드레일 준수)
-- ------------------------------------------------------------
INSERT INTO product (seller_id, category_id, name, origin, storage_type, weight, weight_unit,
                      is_mandatory_auction, price, stock_quantity, status, created_at)
WITH RECURSIVE per_seller AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM per_seller WHERE n < @max_products_per_seller
)
SELECT
  sbi.user_id,
  (SELECT category_id FROM category ORDER BY RAND() LIMIT 1),
  CONCAT('부하테스트상품_', sbi.user_id, '_', ps.n),
  ELT(FLOOR(1 + RAND()*5), '부산','목포','여수','통영','완도'),
  ELT(FLOOR(1 + RAND()*2), '냉장','냉동'),
  ROUND(0.5 + RAND()*10, 2),
  'kg',
  FALSE,
  ROUND(5000 + RAND()*95000, 2),
  FLOOR(RAND()*200),
  ELT(FLOOR(1 + RAND()*20),
      'ON_SALE','ON_SALE','ON_SALE','ON_SALE','ON_SALE','ON_SALE','ON_SALE','ON_SALE',
      'ON_SALE','ON_SALE','ON_SALE','ON_SALE','ON_SALE','ON_SALE',
      'SOLD_OUT','SOLD_OUT','SOLD_OUT',
      'HIDDEN','HIDDEN',
      'PENDING_REVIEW'),
  DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*180) DAY)
FROM seller_business_info sbi
CROSS JOIN per_seller ps
WHERE sbi.auth_status = 'VERIFIED'
  AND sbi.user_id BETWEEN @seller_start_id AND @seller_end_id
  AND (ps.n = 1 OR ps.n <= FLOOR(1 + RAND()*(@max_products_per_seller - 1)));

-- ------------------------------------------------------------
-- 4. 신규 주문 메타 (구매자 + 판매자를 먼저 확정 — 주문 1건=단일 판매자)
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_eligible_sellers;
CREATE TEMPORARY TABLE tmp_eligible_sellers (
  rn INT PRIMARY KEY AUTO_INCREMENT,
  seller_id BIGINT
);
INSERT INTO tmp_eligible_sellers (seller_id)
SELECT DISTINCT seller_id FROM product WHERE seller_id BETWEEN @seller_start_id AND @seller_end_id;
SET @eligible_seller_count = (SELECT COUNT(*) FROM tmp_eligible_sellers);

DROP TEMPORARY TABLE IF EXISTS tmp_order_meta;
CREATE TEMPORARY TABLE tmp_order_meta (
  n INT PRIMARY KEY AUTO_INCREMENT,
  buyer_id BIGINT,
  seller_id BIGINT,
  order_status VARCHAR(30),
  created_at DATETIME
);

-- 주의: RAND()로 계산한 컬럼을 CTE로 만들어서 바로 JOIN 조건에 쓰면,
-- 옵티마이저가 CTE를 외부 쿼리에 병합(merge)하면서 JOIN 시점에 RAND()를
-- 다시 평가해버려 의도한 것과 다른 값으로 매칭되는 문제가 생길 수 있다
-- (실측 확인됨). 그래서 반드시 실제 임시테이블로 한 번 확정(materialize)한
-- 뒤에 그 값으로 조인한다.
DROP TEMPORARY TABLE IF EXISTS tmp_order_draws;
CREATE TEMPORARY TABLE tmp_order_draws
WITH RECURSIVE seq AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM seq WHERE n < @n_new_orders
)
SELECT
  n,
  @buyer_start_id + FLOOR(RAND() * @n_new_buyers) AS buyer_id,
  FLOOR(1 + RAND() * @eligible_seller_count) AS seller_rn,
  ELT(FLOOR(1 + RAND()*6),
      'PAYMENT_PENDING','PAYMENT_COMPLETED','PREPARING','SHIPPING','DELIVERED','PURCHASE_CONFIRMED') AS order_status,
  DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*60) DAY) AS created_at
FROM seq;

INSERT INTO tmp_order_meta (buyer_id, seller_id, order_status, created_at)
SELECT d.buyer_id, es.seller_id, d.order_status, d.created_at
FROM tmp_order_draws d
JOIN tmp_eligible_sellers es ON es.rn = d.seller_rn;

-- ------------------------------------------------------------
-- 4-1. 주문(order) 본체 삽입
-- ------------------------------------------------------------
INSERT INTO `order` (buyer_id, address_id, order_status, total_amount, created_at)
SELECT
  tom.buyer_id,
  da.address_id,
  tom.order_status,
  0,
  tom.created_at
FROM tmp_order_meta tom
JOIN delivery_address da ON da.user_id = tom.buyer_id;

SET @order_start_id = LAST_INSERT_ID();
SET @order_end_id   = @order_start_id + @n_new_orders - 1;

-- tmp_order_meta.n 순서와 order_id 순서가 1:1 대응(둘 다 같은 순서로 seq 삽입)한다고 가정하고 매핑 테이블 생성
DROP TEMPORARY TABLE IF EXISTS tmp_order_map;
CREATE TEMPORARY TABLE tmp_order_map (
  order_id BIGINT PRIMARY KEY,
  seller_id BIGINT
);
INSERT INTO tmp_order_map (order_id, seller_id)
SELECT @order_start_id + (tom.n - 1), tom.seller_id
FROM tmp_order_meta tom;

-- ------------------------------------------------------------
-- 4-2. 주문상품(order_item) — 각 주문의 판매자 상품 중에서만 선택
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_seller_products;
CREATE TEMPORARY TABLE tmp_seller_products (
  rn INT,
  seller_id BIGINT,
  product_id BIGINT,
  PRIMARY KEY (seller_id, rn)
);
INSERT INTO tmp_seller_products (rn, seller_id, product_id)
SELECT
  ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY product_id),
  seller_id, product_id
FROM product
WHERE seller_id BETWEEN @seller_start_id AND @seller_end_id;

DROP TEMPORARY TABLE IF EXISTS tmp_seller_product_count;
CREATE TEMPORARY TABLE tmp_seller_product_count (
  seller_id BIGINT PRIMARY KEY,
  cnt INT
);
INSERT INTO tmp_seller_product_count (seller_id, cnt)
SELECT seller_id, COUNT(*) FROM tmp_seller_products GROUP BY seller_id;

-- (위와 동일한 이유로) product_rn/quantity/포함여부를 먼저 실제 임시테이블로 확정한 뒤 조인
DROP TEMPORARY TABLE IF EXISTS tmp_item_draws;
CREATE TEMPORARY TABLE tmp_item_draws
WITH RECURSIVE item_seq AS (
  SELECT 1 AS k
  UNION ALL
  SELECT k + 1 FROM item_seq WHERE k < @max_items_per_order
)
SELECT
  om.order_id,
  om.seller_id,
  isq.k,
  1 + FLOOR(RAND() * spc.cnt) AS product_rn,
  FLOOR(1 + RAND()*5) AS quantity,
  (isq.k = 1 OR isq.k <= FLOOR(1 + RAND()*@max_items_per_order)) AS include_flag
FROM tmp_order_map om
JOIN tmp_seller_product_count spc ON spc.seller_id = om.seller_id
CROSS JOIN item_seq isq;

INSERT INTO order_item (order_id, product_id, quantity)
SELECT d.order_id, tsp.product_id, d.quantity
FROM tmp_item_draws d
JOIN tmp_seller_products tsp ON tsp.seller_id = d.seller_id AND tsp.rn = d.product_rn
WHERE d.include_flag = 1;

-- ------------------------------------------------------------
-- 4-3. total_amount 재계산
-- ------------------------------------------------------------
UPDATE `order` o
JOIN (
  SELECT oi.order_id, SUM(oi.quantity * p.price) AS total
  FROM order_item oi
  JOIN product p ON p.product_id = oi.product_id
  WHERE oi.order_id BETWEEN @order_start_id AND @order_end_id
  GROUP BY oi.order_id
) t ON t.order_id = o.order_id
SET o.total_amount = t.total
WHERE o.order_id BETWEEN @order_start_id AND @order_end_id;

-- ------------------------------------------------------------
-- 5. 결제 (order_status가 PAYMENT_PENDING이 아닌 주문만)
-- ------------------------------------------------------------
INSERT INTO payment (order_id, payment_method, pg_transaction_id)
SELECT order_id,
       ELT(FLOOR(1 + RAND()*3), 'CARD','KAKAO_PAY','TOSS_PAY'),
       CONCAT('LOADTEST-', UUID())
FROM `order`
WHERE order_id BETWEEN @order_start_id AND @order_end_id
  AND order_status <> 'PAYMENT_PENDING';

-- ------------------------------------------------------------
-- 6. 배송 (SHIPPING / DELIVERED / PURCHASE_CONFIRMED 주문만)
-- ------------------------------------------------------------
INSERT INTO delivery (order_id, carrier, tracking_number)
SELECT order_id,
       ELT(FLOOR(1 + RAND()*3), 'CJ대한통운','한진택배','롯데택배'),
       CONCAT('TRK', LPAD(FLOOR(RAND()*1000000000), 9, '0'))
FROM `order`
WHERE order_id BETWEEN @order_start_id AND @order_end_id
  AND order_status IN ('SHIPPING','DELIVERED','PURCHASE_CONFIRMED');

-- ------------------------------------------------------------
-- 7. 주문상태이력 (현재 상태를 1건씩 기록 — 간이 버전)
-- ------------------------------------------------------------
INSERT INTO order_status_history (order_id, status_value, changed_at)
SELECT order_id, order_status, created_at
FROM `order`
WHERE order_id BETWEEN @order_start_id AND @order_end_id;

-- ------------------------------------------------------------
-- 8. 정산 (PURCHASE_CONFIRMED 주문만 — 주문:정산 1:1)
-- ------------------------------------------------------------
INSERT INTO settlement (seller_id, order_id, amount, status, settled_at)
SELECT om.seller_id, o.order_id, o.total_amount,
       CASE WHEN RAND() < 0.6 THEN 'COMPLETED' ELSE 'PENDING' END,
       CASE WHEN RAND() < 0.6 THEN o.created_at ELSE NULL END
FROM `order` o
JOIN tmp_order_map om ON om.order_id = o.order_id
WHERE o.order_id BETWEEN @order_start_id AND @order_end_id
  AND o.order_status = 'PURCHASE_CONFIRMED';

-- ------------------------------------------------------------
-- 정리
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_eligible_sellers;
DROP TEMPORARY TABLE IF EXISTS tmp_order_draws;
DROP TEMPORARY TABLE IF EXISTS tmp_order_meta;
DROP TEMPORARY TABLE IF EXISTS tmp_order_map;
DROP TEMPORARY TABLE IF EXISTS tmp_seller_products;
DROP TEMPORARY TABLE IF EXISTS tmp_seller_product_count;
DROP TEMPORARY TABLE IF EXISTS tmp_item_draws;

-- ------------------------------------------------------------
-- 결과 요약
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `member`)   AS total_members,
  (SELECT COUNT(*) FROM product)    AS total_products,
  (SELECT COUNT(*) FROM `order`)    AS total_orders,
  (SELECT COUNT(*) FROM order_item) AS total_order_items,
  (SELECT COUNT(*) FROM settlement) AS total_settlements;
