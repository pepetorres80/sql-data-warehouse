/* =========================================================
02_data.sql
Carga de datos (demo realista) + ejemplos de UPDATE/DELETE
+ transacciones con ROLLBACK/COMMIT.
========================================================= */

-- ================
-- DIM_CALENDAR (rango controlado)
-- ================
/*
Creamos fechas para 2025-01-01 a 2025-03-31 (suficiente para el EDA).
*/
INSERT INTO dim_calendar (date_id, full_date, day_num, month_num, year_num, weekday_num, is_weekend)
SELECT
  (TO_CHAR(d::date, 'YYYYMMDD'))::int AS date_id,
  d::date AS full_date,
  EXTRACT(DAY FROM d)::int AS day_num,
  EXTRACT(MONTH FROM d)::int AS month_num,
  EXTRACT(YEAR FROM d)::int AS year_num,
  EXTRACT(ISODOW FROM d)::int AS weekday_num,
  CASE WHEN EXTRACT(ISODOW FROM d) IN (6,7) THEN TRUE ELSE FALSE END AS is_weekend
FROM generate_series('2025-01-01'::date, '2025-03-31'::date, interval '1 day') d
ON CONFLICT (date_id) DO NOTHING;

-- ================
-- Provincias
-- ================
INSERT INTO dim_province (province_name, region_name)
VALUES
 ('Granada','Andalucía'),
 ('Málaga','Andalucía'),
 ('Almería','Andalucía'),
 ('Jaén','Andalucía')
ON CONFLICT (province_name) DO NOTHING;

-- ================
-- Stores
-- ================
INSERT INTO dim_store (store_name, store_type, city, province_id, open_date)
SELECT * FROM (
  VALUES
  ('Estanco Centro','ESTANCO','Salobreña', (SELECT province_id FROM dim_province WHERE province_name='Granada'), '2012-06-01'::date),
  ('Bar Costa','BAR','Motril', (SELECT province_id FROM dim_province WHERE province_name='Granada'), '2019-04-15'::date),
  ('Tienda Online','ONLINE','Internet', (SELECT province_id FROM dim_province WHERE province_name='Málaga'), '2024-01-01'::date)
) AS v(store_name, store_type, city, province_id, open_date)
ON CONFLICT (store_name, city) DO NOTHING;

-- ================
-- Payment methods
-- ================
INSERT INTO dim_payment_method (method_name)
VALUES ('EFECTIVO'),('TARJETA'),('BIZUM'),('ONLINE')
ON CONFLICT (method_name) DO NOTHING;

-- ================
-- Products
-- ================
INSERT INTO dim_product (sku, product_name, category, brand, is_age_restricted, unit_cost, unit_price, active)
VALUES
 ('TBN-001','Cigarrillos Rubios 20u','TABACO','MarcaA',TRUE, 4.20, 5.50, TRUE),
 ('TBN-002','Cigarrillos Negros 20u','TABACO','MarcaB',TRUE, 4.00, 5.20, TRUE),
 ('VPR-010','Vaper Desechable 600','VAPER','VapeX',TRUE, 5.00, 7.99, TRUE),
 ('BEB-100','Agua 0.5L','BEBIDA','AguaFit',FALSE, 0.20, 1.20, TRUE),
 ('BEB-110','Cerveza Lata 33cl','BEBIDA','BirraSur',TRUE, 0.45, 1.80, TRUE),
 ('SNK-200','Patatas Bolsa 120g','SNACK','Crunchy',FALSE, 0.35, 1.50, TRUE),
 ('OTR-900','Mechero','OTROS','FireUp',FALSE, 0.25, 1.00, TRUE)
ON CONFLICT (sku) DO NOTHING;

-- ================
-- Customers
-- ================
INSERT INTO dim_customer (full_name, email, birth_date)
VALUES
 ('Ana López','ana.lopez@email.com','1988-05-20'),
 ('Manuel Ruiz','manu.ruiz@email.com','1979-11-03'),
 ('Cliente Anónimo',NULL,NULL)
ON CONFLICT (email) DO NOTHING;

-- ================
-- Employees
-- ================
INSERT INTO dim_employee (full_name, role_name, store_id, hire_date, active)
VALUES
 ('Estela Sánchez','ENCARGADO', (SELECT store_id FROM dim_store WHERE store_name='Estanco Centro' AND city='Salobreña'), '2020-02-01', TRUE),
 ('Juan Pérez','DEPENDIENTE', (SELECT store_id FROM dim_store WHERE store_name='Estanco Centro' AND city='Salobreña'), '2023-06-10', TRUE),
 ('Lucía Martín','CAMARERO', (SELECT store_id FROM dim_store WHERE store_name='Bar Costa' AND city='Motril'), '2022-05-05', TRUE)
;

-- =========================================================
-- TRANSACCIÓN DEMO: probamos un insert malo y hacemos ROLLBACK
-- =========================================================
BEGIN;

-- Insert incorrecto: quantity <=0 debe fallar por CHECK
-- (lo dejamos para demostrar ROLLBACK)
-- OJO: este INSERT dará error y abortará la transacción en PostgreSQL.
-- Por eso lo hacemos con SAVEPOINT.
SAVEPOINT sp_before_bad_insert;

-- Intento de inserción inválida (se espera error)
-- Si tu IDE detiene ejecución al error, ejecuta solo hasta ROLLBACK TO SAVEPOINT.
INSERT INTO fact_sales (
  ticket_id, sale_date_id, store_id, product_id, customer_id, employee_id, payment_method_id,
  quantity, unit_price_snapshot, unit_cost_snapshot, discount_pct
)
VALUES (
  9000001,
  20250105,
  (SELECT store_id FROM dim_store WHERE store_name='Estanco Centro' AND city='Salobreña'),
  (SELECT product_id FROM dim_product WHERE sku='TBN-001'),
  (SELECT customer_id FROM dim_customer WHERE email='ana.lopez@email.com'),
  (SELECT employee_id FROM dim_employee WHERE full_name='Juan Pérez'),
  (SELECT payment_method_id FROM dim_payment_method WHERE method_name='TARJETA'),
  0, 5.50, 4.20, 0.05
);

-- Si el IDE permite continuar: revertimos al savepoint
ROLLBACK TO SAVEPOINT sp_before_bad_insert;

-- Ahora sí: inserts válidos (dataset pequeño pero suficiente)
-- =========================================================
-- Ventas (líneas) - enero a marzo
-- ticket_id compartido por varias líneas para simular cesta
INSERT INTO fact_sales (
  ticket_id, sale_date_id, store_id, product_id, customer_id, employee_id, payment_method_id,
  quantity, unit_price_snapshot, unit_cost_snapshot, discount_pct
)
SELECT * FROM (
  VALUES
  -- Ticket 1001 (Estanco)
  (1001, 20250105, st1, p1, c1, e2, pay_card, 1, 5.50, 4.20, 0.00),
  (1001, 20250105, st1, p7, c1, e2, pay_card, 1, 1.00, 0.25, 0.00),

  -- Ticket 1002 (Bar)
  (1002, 20250106, st2, p4, c2, e3, pay_cash, 2, 1.20, 0.20, 0.00),
  (1002, 20250106, st2, p6, c2, e3, pay_cash, 1, 1.50, 0.35, 0.10),

  -- Ticket 1003 (Online)
  (1003, 20250110, st3, p3, NULL, e1, pay_online, 1, 7.99, 5.00, 0.05),

  -- Febrero (sube descuento y mix)
  (1101, 20250202, st1, p2, NULL, e1, pay_cash, 1, 5.20, 4.00, 0.00),
  (1102, 20250210, st2, p5, NULL, e3, pay_card, 3, 1.80, 0.45, 0.00),
  (1102, 20250210, st2, p6, NULL, e3, pay_card, 2, 1.50, 0.35, 0.15),
  (1103, 20250215, st1, p1, c2, e2, pay_bizum, 2, 5.50, 4.20, 0.03),

  -- Marzo (más volumen)
  (1201, 20250301, st1, p7, c1, e1, pay_cash, 3, 1.00, 0.25, 0.00),
  (1202, 20250305, st2, p4, NULL, e3, pay_cash, 6, 1.20, 0.20, 0.00),
  (1202, 20250305, st2, p6, NULL, e3, pay_cash, 2, 1.50, 0.35, 0.00),
  (1203, 20250320, st3, p3, c2, e1, pay_online, 2, 7.99, 5.00, 0.10)
) AS v(ticket_id, sale_date_id, store_id, product_id, customer_id, employee_id, payment_method_id,
       quantity, unit_price_snapshot, unit_cost_snapshot, discount_pct)
CROSS JOIN LATERAL (
  SELECT
    (SELECT store_id FROM dim_store WHERE store_name='Estanco Centro' AND city='Salobreña') AS st1,
    (SELECT store_id FROM dim_store WHERE store_name='Bar Costa' AND city='Motril') AS st2,
    (SELECT store_id FROM dim_store WHERE store_name='Tienda Online' AND city='Internet') AS st3,

    (SELECT product_id FROM dim_product WHERE sku='TBN-001') AS p1,
    (SELECT product_id FROM dim_product WHERE sku='TBN-002') AS p2,
    (SELECT product_id FROM dim_product WHERE sku='VPR-010') AS p3,
    (SELECT product_id FROM dim_product WHERE sku='BEB-100') AS p4,
    (SELECT product_id FROM dim_product WHERE sku='BEB-110') AS p5,
    (SELECT product_id FROM dim_product WHERE sku='SNK-200') AS p6,
    (SELECT product_id FROM dim_product WHERE sku='OTR-900') AS p7,

    (SELECT customer_id FROM dim_customer WHERE email='ana.lopez@email.com') AS c1,
    (SELECT customer_id FROM dim_customer WHERE email='manu.ruiz@email.com') AS c2,

    (SELECT employee_id FROM dim_employee WHERE full_name='Estela Sánchez') AS e1,
    (SELECT employee_id FROM dim_employee WHERE full_name='Juan Pérez') AS e2,
    (SELECT employee_id FROM dim_employee WHERE full_name='Lucía Martín') AS e3,

    (SELECT payment_method_id FROM dim_payment_method WHERE method_name='EFECTIVO') AS pay_cash,
    (SELECT payment_method_id FROM dim_payment_method WHERE method_name='TARJETA') AS pay_card,
    (SELECT payment_method_id FROM dim_payment_method WHERE method_name='BIZUM') AS pay_bizum,
    (SELECT payment_method_id FROM dim_payment_method WHERE method_name='ONLINE') AS pay_online
) x;

COMMIT;

-- =========================
-- UPDATE (ejemplo): ajustamos precio de un producto (cambio comercial)
-- =========================
UPDATE dim_product
SET unit_price = unit_price + 0.20
WHERE sku = 'SNK-200';

-- =========================
-- DELETE (ejemplo): borramos cliente "demo" si existiera
-- =========================
DELETE FROM dim_customer
WHERE full_name = 'Cliente Demo Borrar';

-- =========================
-- CAST (ejemplo): forzamos un tipo para comprobar
-- =========================
SELECT sku, unit_price::NUMERIC(10,2) AS unit_price_cast
FROM dim_product;
