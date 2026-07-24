-- ============================================================
-- 수산물 거래 중개 플랫폼 - 관리자 집계 쿼리 설계 (V3 스키마 기준)
-- 근거: 요구사항서 1.4.3(관리자 환경), 2.1.3(비정상거래 모니터링),
--       기능명세서 F-01-03(판매자 인증), F-05-04(매출/정산), F-02-02(의무위판)
-- 대상 DB: seafood_dummy_test (더미데이터로 실제 검증됨)
-- ============================================================

-- ----------------------------------------------------------------
-- 1. 거래 현황 대시보드
-- ----------------------------------------------------------------

-- 1-1. 오늘 신규 주문 건수 / 거래액
SELECT
  COUNT(*) AS today_order_cnt,
  COALESCE(SUM(total_amount), 0) AS today_sales
FROM `order`
WHERE DATE(created_at) = CURDATE();

-- 1-2. 최근 7일 일별 주문 추이 (오늘 포함)
SELECT
  DATE(created_at) AS order_date,
  COUNT(*) AS order_cnt,
  SUM(total_amount) AS daily_sales
FROM `order`
WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
GROUP BY DATE(created_at)
ORDER BY order_date;

-- 1-3. 주문 상태별 분포 (결제완료→배송준비→배송중→배송완료→구매확정 파이프라인 모니터링)
SELECT
  order_status,
  COUNT(*) AS cnt,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM `order`
GROUP BY order_status
ORDER BY FIELD(order_status,
  'PAYMENT_PENDING','PAYMENT_COMPLETED','PREPARING','SHIPPING','DELIVERED','PURCHASE_CONFIRMED');

-- 1-4. 결제수단별 비중 (CARD/KAKAO_PAY/TOSS_PAY)
SELECT
  p.payment_method,
  COUNT(*) AS cnt,
  SUM(o.total_amount) AS amount
FROM payment p
JOIN `order` o ON o.order_id = p.order_id
GROUP BY p.payment_method
ORDER BY amount DESC;

-- ----------------------------------------------------------------
-- 2. 회원 / 판매자 인증 관리 (요구사항서 1.4.3 "사업자등록 인증 상태 확인")
-- ----------------------------------------------------------------

-- 2-1. 역할별 회원수 및 탈퇴 회원 비율
SELECT
  role,
  COUNT(*) AS total_cnt,
  SUM(is_withdrawn) AS withdrawn_cnt,
  ROUND(SUM(is_withdrawn) * 100.0 / COUNT(*), 1) AS withdrawn_pct
FROM member
GROUP BY role;

-- 2-2. 판매자 인증 상태별 현황 (F-01-03) — 승인/대기/반려 각각 몇 명, 상품은 몇 개 갖고 있는지
SELECT
  sbi.auth_status,
  COUNT(DISTINCT sbi.user_id) AS seller_cnt,
  COUNT(p.product_id) AS product_cnt
FROM seller_business_info sbi
LEFT JOIN product p ON p.seller_id = sbi.user_id
GROUP BY sbi.auth_status;

-- 2-3. [가드레일 점검] 미인증(VERIFIED 아님) 판매자가 상품을 보유한 경우
--      -- 정상이면 반드시 0건이어야 함. F-01-03 "판매자 자격 인증 전 상품 등록 차단" 위반 탐지용.
SELECT sbi.user_id, m.nickname, sbi.auth_status, COUNT(p.product_id) AS product_cnt
FROM seller_business_info sbi
JOIN member m ON m.user_id = sbi.user_id
JOIN product p ON p.seller_id = sbi.user_id
WHERE sbi.auth_status <> 'VERIFIED'
GROUP BY sbi.user_id, m.nickname, sbi.auth_status;

-- 2-4. 최근 30일 일별 신규 가입자 추이 (역할별)
SELECT
  DATE(created_at) AS signup_date,
  role,
  COUNT(*) AS cnt
FROM member
WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY DATE(created_at), role
ORDER BY signup_date;

-- ----------------------------------------------------------------
-- 3. 상품 현황 및 컴플라이언스 가드레일
-- ----------------------------------------------------------------

-- 3-1. 상품 상태별 현황 (ON_SALE / SOLD_OUT / HIDDEN / PENDING_REVIEW)
SELECT status, COUNT(*) AS cnt
FROM product
GROUP BY status;

-- 3-2. 관리자 검수 대기열 — PENDING_REVIEW 상태 상품 목록 (오래된 순)
SELECT p.product_id, p.name, m.nickname AS seller, p.origin, p.created_at
FROM product p
JOIN member m ON m.user_id = p.seller_id
WHERE p.status = 'PENDING_REVIEW'
ORDER BY p.created_at;

-- 3-3. [가드레일 점검] 의무위판(is_mandatory_auction=1) 상품이 판매중(ON_SALE)인 경우
--      -- 정상이면 반드시 0건. 요구사항서 "의무 위판 어종은 카테고리에서 사전 제외" 위반 탐지용.
SELECT product_id, name, status, is_mandatory_auction, seller_id
FROM product
WHERE is_mandatory_auction = 1 AND status = 'ON_SALE';

-- 3-4. 카테고리별 판매량 / 매출 Top N
SELECT
  c.category_name,
  SUM(oi.quantity) AS total_qty,
  SUM(oi.quantity * p.price) AS total_amount
FROM order_item oi
JOIN product p ON p.product_id = oi.product_id
JOIN category c ON c.category_id = p.category_id
GROUP BY c.category_name
ORDER BY total_amount DESC;

-- 3-5. 원산지(선적항)별 거래 비중 — 판매자=개인 어업인 모델이라 원산지=선적항 고정
SELECT
  p.origin,
  COUNT(DISTINCT o.order_id) AS order_cnt,
  SUM(oi.quantity * p.price) AS total_amount
FROM order_item oi
JOIN `order` o ON o.order_id = oi.order_id
JOIN product p ON p.product_id = oi.product_id
GROUP BY p.origin
ORDER BY total_amount DESC;

-- ----------------------------------------------------------------
-- 4. 매출 / 정산 (F-05-04 "판매자 매출 통계 및 정산 예정 금액 조회")
-- ----------------------------------------------------------------

-- 4-1. 판매자별 매출 순위 (정산 확정액 vs 정산 예정액 구분)
SELECT
  m.user_id, m.nickname,
  COUNT(s.settlement_id) AS settlement_cnt,
  SUM(CASE WHEN s.status = 'COMPLETED' THEN s.amount ELSE 0 END) AS confirmed_revenue,
  SUM(CASE WHEN s.status = 'PENDING'   THEN s.amount ELSE 0 END) AS pending_revenue
FROM member m
JOIN settlement s ON s.seller_id = m.user_id
GROUP BY m.user_id, m.nickname
ORDER BY confirmed_revenue DESC;

-- 4-2. 정산 상태 전체 요약 (플랫폼 전체 정산 대기 총액 파악)
SELECT
  status,
  COUNT(*) AS cnt,
  SUM(amount) AS total_amount
FROM settlement
GROUP BY status;

-- ----------------------------------------------------------------
-- 5. 신고 / 비정상 거래 모니터링 (요구사항서 2.1.3 "비정상 거래 모니터링")
-- ----------------------------------------------------------------

-- 5-1. 신고 처리 현황 (대상유형 x 처리상태)
SELECT target_type, status, COUNT(*) AS cnt
FROM report
GROUP BY target_type, status
ORDER BY target_type, status;

-- 5-2. 반복 신고 판매자 탐지 (동일 판매자가 2건 이상 신고당한 경우)
SELECT r.reported_user_id, m.nickname, COUNT(*) AS report_cnt
FROM report r
JOIN member m ON m.user_id = r.reported_user_id
WHERE r.target_type = 'USER'
GROUP BY r.reported_user_id, m.nickname
HAVING COUNT(*) >= 2
ORDER BY report_cnt DESC;

-- 5-3. 결제완료 후 24시간 이상 배송 준비가 시작되지 않은 주문 (신선식품 SLA 이상 탐지)
--      참고: order.created_at(주문 생성 시각) 기준 근사치. 결제완료 시각을 정확히 추적하려면
--      order_status_history에서 status_value='PAYMENT_COMPLETED'인 행의 changed_at을 조인할 것.
SELECT
  o.order_id, m.nickname AS buyer, o.order_status, o.created_at,
  TIMESTAMPDIFF(HOUR, o.created_at, NOW()) AS hours_since_order
FROM `order` o
JOIN member m ON m.user_id = o.buyer_id
WHERE o.order_status = 'PAYMENT_COMPLETED'
  AND o.created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR);
