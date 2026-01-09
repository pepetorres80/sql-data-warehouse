-- 05_seed_fact_sales.sql
-- Seed escalable para fact_sales:
-- - num_tickets configurable
-- - 1..4 líneas por ticket
-- - NO repite product_id dentro del mismo ticket (respeta uq_ticket_product)
-- - fechas asignadas de forma determinista y distribuida (evita “todo en un mes”)

BEGIN;

-- Limpieza controlada (si quieres conservar histórico, comenta TRUNCATE)
TRUNCATE fact_sales RESTART IDENTITY;

WITH params AS (
  SELECT
    500::int AS num_tickets,      -- <-- CAMBIA AQUÍ (180, 500, 2000...)
    3000::int AS ticket_start,    -- base para ticket_id
    '2025-01-01'::date AS start_date,
    '2025-03-31'::date AS end_date
),
calendar_range AS (
  SELECT
    p.*,
    (p.end_date - p.start_date + 1)::int AS n_days
  FROM params p
),
tickets AS (
  SELECT
    (cr.ticket_start + i) AS ticket_id,

    -- Fecha distribuida: start_date + (i % n_days)
    (to_char(cr.start_date + (i % cr.n_days), 'YYYYMMDD'))::int AS sale_date_id,

    -- Store distribuido de forma determinista (round-robin)
(SELECT s.store_id
 FROM (SELECT store_id, ROW_NUMBER() OVER (ORDER BY store_id) - 1 AS rn
       FROM dim_store) s
 WHERE s.rn = (i % (SELECT COUNT(*) FROM dim_store))
) AS store_id,

-- Método de pago distribuido determinísticamente
(SELECT pm.payment_method_id
 FROM (SELECT payment_method_id, ROW_NUMBER() OVER (ORDER BY payment_method_id) - 1 AS rn
       FROM dim_payment_method) pm
 WHERE pm.rn = (i % (SELECT COUNT(*) FROM dim_payment_method))
) AS payment_method_id,


    CASE
      WHEN random() < 0.7 THEN (SELECT customer_id FROM dim_customer ORDER BY random() LIMIT 1)
      ELSE NULL
    END AS customer_id,

    (floor(random() * 4) + 1)::int AS n_lines
  FROM calendar_range cr
  CROSS JOIN generate_series(0, (SELECT num_tickets-1 FROM params)) AS i
),
ticket_products AS (
  -- Elegimos productos únicos por ticket con ROW_NUMBER aleatorio
  SELECT
    tk.ticket_id,
    p.product_id,
    ROW_NUMBER() OVER (PARTITION BY tk.ticket_id ORDER BY random()) AS rn
  FROM tickets tk
  CROSS JOIN dim_product p
),
lines AS (
  SELECT
    tk.ticket_id,
    tk.sale_date_id,
    tk.store_id,
    tk.payment_method_id,
    tk.customer_id,
    tp.product_id,
    (SELECT employee_id FROM dim_employee ORDER BY random() LIMIT 1) AS employee_id,
    (floor(random() * 3) + 1)::int AS quantity,
    CASE
      WHEN random() < 0.60 THEN 0
      WHEN random() < 0.85 THEN 0.05
      ELSE 0.15
    END AS discount_pct
  FROM tickets tk
  JOIN ticket_products tp
    ON tp.ticket_id = tk.ticket_id
  WHERE tp.rn <= tk.n_lines
)
INSERT INTO fact_sales (
  ticket_id, sale_date_id, store_id, product_id, customer_id, employee_id, payment_method_id,
  quantity, unit_price_snapshot, unit_cost_snapshot, discount_pct
)
SELECT
  l.ticket_id,
  l.sale_date_id,
  l.store_id,
  l.product_id,
  l.customer_id,
  l.employee_id,
  l.payment_method_id,
  l.quantity,
  p.unit_price,
  p.unit_cost,
  l.discount_pct
FROM lines l
JOIN dim_product p ON p.product_id = l.product_id;

COMMIT;
