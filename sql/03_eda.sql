/* =========================================================
03_eda.sql
EDA en SQL (JOINs, LEFT JOIN, CASE, CTEs encadenadas, ventanas,
subqueries, agregaciones, funciones fecha, CAST).
Incluye comentarios de insights de negocio.
========================================================= */

-- 0) Chequeo rápido de calidad / integridad
-- ----------------------------------------
-- OBJETIVO: validar que el modelo está cargado y el volumen es suficiente.
-- INSIGHT: si la fact table tiene cientos/miles de líneas, el EDA será estable
--          (evitas conclusiones “ruidosas” por falta de datos).
SELECT 'dim_calendar' AS table_name, COUNT(*) AS rows FROM dim_calendar
UNION ALL SELECT 'dim_store', COUNT(*) FROM dim_store
UNION ALL SELECT 'dim_product', COUNT(*) FROM dim_product
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_employee', COUNT(*) FROM dim_employee
UNION ALL SELECT 'dim_payment_method', COUNT(*) FROM dim_payment_method
UNION ALL SELECT 'fact_sales', COUNT(*) FROM fact_sales;

-- 1) JOIN (INNER) básico: ingresos por provincia y mes
-- ----------------------------------------------------
-- OBJETIVO: medir revenue, tickets y ticket medio por mes.
-- INSIGHT: identifica estacionalidad y evolución del negocio (subidas/caídas).
-- DECISIÓN: ajustar surtido / pricing / campañas si un mes cae o cambia el ticket medio.
SELECT
  pv.province_name,
  dc.year_num,
  dc.month_num,
  SUM(fs.net_amount) AS revenue,
  COUNT(DISTINCT fs.ticket_id) AS tickets,
  ROUND(SUM(fs.net_amount) / NULLIF(COUNT(DISTINCT fs.ticket_id),0), 2) AS avg_ticket
FROM fact_sales fs
JOIN dim_calendar dc ON dc.date_id = fs.sale_date_id
JOIN dim_store st ON st.store_id = fs.store_id
JOIN dim_province pv ON pv.province_id = st.province_id
GROUP BY pv.province_name, dc.year_num, dc.month_num
ORDER BY dc.year_num, dc.month_num, revenue DESC;

-- 2) LEFT JOIN: clientes sin compras (o sin compras en un periodo)
-- ---------------------------------------------------------------
-- OBJETIVO: detectar clientes “durmientes” (sin actividad).
-- INSIGHT: base accionable para reactivación (email/SMS/cupones).
-- NOTA: en retail es normal que existan tickets anónimos (customer_id puede ser NULL).
SELECT
  c.customer_id,
  c.full_name,
  c.email
FROM dim_customer c
LEFT JOIN fact_sales fs ON fs.customer_id = c.customer_id
WHERE fs.customer_id IS NULL
  AND c.email IS NOT NULL;

-- 3) CASE: segmentación por nivel de descuento
-- --------------------------------------------
-- OBJETIVO: entender cómo se reparte el revenue por política de descuentos.
-- INSIGHT: si el margen cae fuerte en descuentos medios/altos, hay riesgo de “comprar ventas”.
-- DECISIÓN: limitar descuentos medios/altos a productos con margen suficiente o campañas puntuales.
SELECT
  CASE
    WHEN fs.discount_pct = 0 THEN 'SIN_DESCUENTO'
    WHEN fs.discount_pct <= 0.05 THEN 'DESCUENTO_BAJO'
    WHEN fs.discount_pct <= 0.15 THEN 'DESCUENTO_MEDIO'
    ELSE 'DESCUENTO_ALTO'
  END AS discount_bucket,
  COUNT(*) AS lines,
  SUM(fs.net_amount) AS revenue,
  SUM(fs.net_amount - (fs.quantity * fs.unit_cost_snapshot)) AS gross_margin
FROM fact_sales fs
GROUP BY 1
ORDER BY revenue DESC;

-- 4) Subquery: Top productos por ingresos (global)
-- -----------------------------------------------
-- OBJETIVO: ranking de productos por revenue total.
-- INSIGHT: identifica “drivers” (productos que tiran del negocio).
-- DECISIÓN: priorizar stock/visibilidad, y diseñar cross-sell alrededor de estos tops.
SELECT *
FROM (
  SELECT
    p.category,
    p.product_name,
    SUM(fs.net_amount) AS revenue
  FROM fact_sales fs
  JOIN dim_product p ON p.product_id = fs.product_id
  GROUP BY p.category, p.product_name
) t
ORDER BY t.revenue DESC
LIMIT 5;

-- 5) CTE encadenadas + ventana: Top categoría por provincia
-- ---------------------------------------------------------
-- OBJETIVO: detectar el mix dominante por territorio.
-- INSIGHT: cada provincia/canal puede tener un mix distinto (preferencias de compra).
-- DECISIÓN: ajustar surtido y pricing local (especialmente útil si crece a varias provincias).
WITH revenue_by_prov_cat AS (
  SELECT
    pv.province_name,
    p.category,
    SUM(fs.net_amount) AS revenue
  FROM fact_sales fs
  JOIN dim_store st ON st.store_id = fs.store_id
  JOIN dim_province pv ON pv.province_id = st.province_id
  JOIN dim_product p ON p.product_id = fs.product_id
  GROUP BY pv.province_name, p.category
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY province_name ORDER BY revenue DESC) AS rn
  FROM revenue_by_prov_cat
)
SELECT
  province_name,
  category,
  revenue
FROM ranked
WHERE rn = 1
ORDER BY revenue DESC;

-- 6) Ventana: acumulado mensual (running total) por tienda
-- --------------------------------------------------------
-- OBJETIVO: visualizar crecimiento/caída acumulada por canal/tienda.
-- INSIGHT: el running total permite detectar puntos de inflexión temporal de forma clara.
-- DECISIÓN: si un canal se estanca, activar acciones comerciales específicas (online vs físico).
WITH by_month AS (
  SELECT
    st.store_name,
    dc.year_num,
    dc.month_num,
    SUM(fs.net_amount) AS revenue
  FROM fact_sales fs
  JOIN dim_calendar dc ON dc.date_id = fs.sale_date_id
  JOIN dim_store st ON st.store_id = fs.store_id
  GROUP BY st.store_name, dc.year_num, dc.month_num
)
SELECT
  store_name,
  year_num,
  month_num,
  revenue,
  SUM(revenue) OVER (PARTITION BY store_name ORDER BY year_num, month_num) AS running_revenue
FROM by_month
ORDER BY store_name, year_num, month_num;

-- 7) Funciones de fecha + CAST: ventas fin de semana vs laborable
-- ---------------------------------------------------------------
-- OBJETIVO: comparar comportamiento de compra en fin de semana vs laborables.
-- INSIGHT: útil para dimensionar personal, stock y horarios.
-- DECISIÓN: si el finde sube el importe medio, aplicar upsell (bebidas/snacks) o packs.
SELECT
  dc.is_weekend,
  COUNT(DISTINCT fs.ticket_id) AS tickets,
  SUM(fs.net_amount) AS revenue,
  ROUND(AVG(fs.net_amount::numeric), 2) AS avg_line_amount
FROM fact_sales fs
JOIN dim_calendar dc ON dc.date_id = fs.sale_date_id
GROUP BY dc.is_weekend
ORDER BY revenue DESC;

-- 8) 3 JOINs usando la VIEW: ingresos por método de pago y tipo de tienda
-- -----------------------------------------------------------------------
-- OBJETIVO: analizar mix de pago por canal (bar/estanco/online).
-- INSIGHT: preferencias de pago impactan comisiones, flujo de caja y UX.
-- DECISIÓN: promover métodos más rentables o más cómodos según el canal.
SELECT
  store_type,
  payment_method,
  SUM(net_amount) AS revenue,
  COUNT(DISTINCT ticket_id) AS tickets
FROM vw_sales_enriched
GROUP BY store_type, payment_method
ORDER BY revenue DESC;

-- 9) Consulta a la FUNCIÓN (KPIs)
-- -------------------------------
-- OBJETIVO: encapsular KPIs por tienda y rango temporal (reutilizable en reporting).
-- INSIGHT: simplifica cuadros de mando y consultas repetitivas.
-- DECISIÓN: comparar rendimiento entre tiendas y periodos sin reescribir SQL.
SELECT * FROM fn_store_kpis(
  (SELECT store_id FROM dim_store WHERE store_name='Estanco Centro' AND city='Salobreña'),
  '2025-01-01',
  '2025-03-31'
);

-- 10) Resultado final: “tabla resumen” (ideal para entrega / reporting)
-- --------------------------------------------------------------------
-- OBJETIVO: salida agregada lista para decisiones (provincia, mes, categoría).
-- MÉTRICAS: tickets, revenue, margen bruto, ticket medio.
-- DECISIONES:
--   - Ajustar surtido por provincia/mes (mix por categoría)
--   - Revisar descuentos si el margen cae
--   - Planificar personal/stock en picos (fines de semana / meses fuertes)
WITH base AS (
  SELECT
    pv.province_name,
    dc.year_num,
    dc.month_num,
    p.category,
    fs.ticket_id,
    fs.net_amount,
    (fs.net_amount - (fs.quantity * fs.unit_cost_snapshot)) AS line_margin
  FROM fact_sales fs
  JOIN dim_calendar dc ON dc.date_id = fs.sale_date_id
  JOIN dim_store st ON st.store_id = fs.store_id
  JOIN dim_province pv ON pv.province_id = st.province_id
  JOIN dim_product p ON p.product_id = fs.product_id
),
agg AS (
  SELECT
    province_name,
    year_num,
    month_num,
    category,
    COUNT(DISTINCT ticket_id) AS tickets,
    SUM(net_amount) AS revenue,
    SUM(line_margin) AS gross_margin
  FROM base
  GROUP BY province_name, year_num, month_num, category
)
SELECT
  province_name,
  year_num,
  month_num,
  category,
  tickets,
  revenue,
  gross_margin,
  ROUND(revenue / NULLIF(tickets,0), 2) AS avg_ticket
FROM agg
ORDER BY year_num, month_num, revenue DESC;
