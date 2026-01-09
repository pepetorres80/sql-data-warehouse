/* =========================================================
01_schema.sql
Motor: PostgreSQL
Objetivo: Crear esquema, tablas (1 fact + dimensiones), constraints,
          índices, una VIEW y una FUNCIÓN para KPIs.
========================================================= */

-- Limpieza (ejecutable desde cero)
DROP VIEW IF EXISTS vw_sales_enriched;
DROP FUNCTION IF EXISTS fn_store_kpis(INT, DATE, DATE);

DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_payment_method;
DROP TABLE IF EXISTS dim_employee;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_store;
DROP TABLE IF EXISTS dim_province;
DROP TABLE IF EXISTS dim_calendar;

-- =========================
-- DIM_CALENDAR
-- =========================
/*
Dimensión calendario: 1 fila por fecha.
PK: date_id (formato YYYYMMDD) para joins rápidos y compatible con BI.
*/
CREATE TABLE IF NOT EXISTS dim_calendar (
  date_id      INT PRIMARY KEY,                -- YYYYMMDD
  full_date    DATE NOT NULL UNIQUE,
  day_num      SMALLINT NOT NULL CHECK (day_num BETWEEN 1 AND 31),
  month_num    SMALLINT NOT NULL CHECK (month_num BETWEEN 1 AND 12),
  year_num     SMALLINT NOT NULL CHECK (year_num BETWEEN 2000 AND 2100),
  weekday_num  SMALLINT NOT NULL CHECK (weekday_num BETWEEN 1 AND 7), -- ISO: 1=Lunes
  is_weekend   BOOLEAN NOT NULL DEFAULT FALSE
);

-- =========================
-- DIM_PROVINCE
-- =========================
/*
Provincias: separada para evitar repetir texto en tiendas y permitir agregaciones por provincia.
*/
CREATE TABLE IF NOT EXISTS dim_province (
  province_id   SERIAL PRIMARY KEY,
  province_name VARCHAR(80) NOT NULL UNIQUE,
  region_name   VARCHAR(80) NOT NULL DEFAULT 'Andalucía'
);

-- =========================
-- DIM_STORE
-- =========================
/*
Tiendas / puntos de venta: estanco, bar, online, etc.
FK a provincia para análisis geográfico.
*/
CREATE TABLE IF NOT EXISTS dim_store (
  store_id      SERIAL PRIMARY KEY,
  store_name    VARCHAR(120) NOT NULL,
  store_type    VARCHAR(30) NOT NULL CHECK (store_type IN ('ESTANCO','BAR','ONLINE','KIOSCO')),
  city          VARCHAR(80) NOT NULL,
  province_id   INT NOT NULL REFERENCES dim_province(province_id),
  open_date     DATE NOT NULL DEFAULT CURRENT_DATE,
  CONSTRAINT uq_store UNIQUE (store_name, city)
);

-- =========================
-- DIM_PRODUCT
-- =========================
/*
Productos con categoría para análisis.
CHECKs para asegurar precios positivos.
*/
CREATE TABLE IF NOT EXISTS dim_product (
  product_id     SERIAL PRIMARY KEY,
  sku            VARCHAR(40) NOT NULL UNIQUE,
  product_name   VARCHAR(160) NOT NULL,
  category       VARCHAR(40) NOT NULL CHECK (category IN ('TABACO','VAPER','BEBIDA','SNACK','OTROS')),
  brand          VARCHAR(80) NOT NULL,
  is_age_restricted BOOLEAN NOT NULL DEFAULT FALSE,
  unit_cost      NUMERIC(10,2) NOT NULL CHECK (unit_cost >= 0),
  unit_price     NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
  active         BOOLEAN NOT NULL DEFAULT TRUE
);

-- =========================
-- DIM_CUSTOMER
-- =========================
/*
Clientes opcionales (en retail muchas ventas son "anónimas").
Permitimos customer_id NULL en fact para ventas sin identificar.
Email UNIQUE si existe.
*/
CREATE TABLE IF NOT EXISTS dim_customer (
  customer_id   SERIAL PRIMARY KEY,
  full_name     VARCHAR(120) NOT NULL,
  email         VARCHAR(160) UNIQUE,
  birth_date    DATE,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_birth_date CHECK (birth_date IS NULL OR birth_date <= CURRENT_DATE)
);

-- =========================
-- DIM_EMPLOYEE
-- =========================
/*
Empleados: útil para productividad, ticket medio por vendedor, etc.
*/
CREATE TABLE IF NOT EXISTS dim_employee (
  employee_id   SERIAL PRIMARY KEY,
  full_name     VARCHAR(120) NOT NULL,
  role_name     VARCHAR(50) NOT NULL CHECK (role_name IN ('DEPENDIENTE','ENCARGADO','CAMARERO','ADMIN')),
  store_id      INT NOT NULL REFERENCES dim_store(store_id),
  hire_date     DATE NOT NULL DEFAULT CURRENT_DATE,
  active        BOOLEAN NOT NULL DEFAULT TRUE
);

-- =========================
-- DIM_PAYMENT_METHOD
-- =========================
CREATE TABLE IF NOT EXISTS dim_payment_method (
  payment_method_id SERIAL PRIMARY KEY,
  method_name       VARCHAR(30) NOT NULL UNIQUE CHECK (method_name IN ('EFECTIVO','TARJETA','BIZUM','ONLINE'))
);

-- =========================
-- FACT_SALES
-- =========================
/*
Tabla de HECHOS: líneas de venta.
Grano: 1 fila = 1 línea (ticket_id + producto).
PK: sales_line_id (surrogate).
FKs: fecha, tienda, producto, cliente (nullable), empleado, pago, provincia (derivable, pero aquí se mantiene vía store->province).
Constraints:
- quantity > 0
- discount_pct entre 0 y 0.80 (por ejemplo)
- unit_price_snapshot y unit_cost_snapshot guardan "foto" del momento de venta (evita que cambios en dim_product alteren histórico).
*/
CREATE TABLE IF NOT EXISTS fact_sales (
  sales_line_id     BIGSERIAL PRIMARY KEY,
  ticket_id         BIGINT NOT NULL,
  sale_date_id      INT NOT NULL REFERENCES dim_calendar(date_id),
  store_id          INT NOT NULL REFERENCES dim_store(store_id),
  product_id        INT NOT NULL REFERENCES dim_product(product_id),
  customer_id       INT REFERENCES dim_customer(customer_id),
  employee_id       INT NOT NULL REFERENCES dim_employee(employee_id),
  payment_method_id INT NOT NULL REFERENCES dim_payment_method(payment_method_id),

  quantity          INT NOT NULL CHECK (quantity > 0),
  unit_price_snapshot NUMERIC(10,2) NOT NULL CHECK (unit_price_snapshot > 0),
  unit_cost_snapshot  NUMERIC(10,2) NOT NULL CHECK (unit_cost_snapshot >= 0),
  discount_pct      NUMERIC(5,4) NOT NULL DEFAULT 0 CHECK (discount_pct >= 0 AND discount_pct <= 0.80),

  -- Total calculado (importe neto)
  net_amount        NUMERIC(12,2) GENERATED ALWAYS AS
                   (ROUND(quantity * unit_price_snapshot * (1 - discount_pct), 2)) STORED,

  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  -- Evita duplicar la misma línea exacta dentro de un ticket (simple guardrail)
  CONSTRAINT uq_ticket_product UNIQUE (ticket_id, product_id)
);

-- =========================
-- ÍNDICES
-- =========================
/*
Índice compuesto típico para queries por fecha y tienda (dashboards).
*/
CREATE INDEX IF NOT EXISTS idx_fact_sales_date_store
ON fact_sales (sale_date_id, store_id);

CREATE INDEX IF NOT EXISTS idx_fact_sales_product
ON fact_sales (product_id);

-- =========================
-- VIEW (tabla/vista resumen “enriquecida”)
-- =========================
CREATE OR REPLACE VIEW vw_sales_enriched AS
SELECT
  fs.sales_line_id,
  fs.ticket_id,
  dc.full_date,
  dc.month_num,
  dc.year_num,
  st.store_name,
  st.store_type,
  st.city,
  pv.province_name,
  pr.sku,
  pr.product_name,
  pr.category,
  pr.brand,
  fs.quantity,
  fs.unit_price_snapshot,
  fs.discount_pct,
  fs.net_amount,
  pm.method_name AS payment_method,
  emp.full_name AS employee_name,
  cust.full_name AS customer_name
FROM fact_sales fs
JOIN dim_calendar dc ON dc.date_id = fs.sale_date_id
JOIN dim_store st ON st.store_id = fs.store_id
JOIN dim_province pv ON pv.province_id = st.province_id
JOIN dim_product pr ON pr.product_id = fs.product_id
JOIN dim_payment_method pm ON pm.payment_method_id = fs.payment_method_id
JOIN dim_employee emp ON emp.employee_id = fs.employee_id
LEFT JOIN dim_customer cust ON cust.customer_id = fs.customer_id;

-- =========================
-- FUNCIÓN: KPIs por tienda y rango de fechas
-- =========================
/*
Devuelve KPIs: ingresos, margen, tickets, líneas, ticket medio, %descuento.
Ejemplo uso:
SELECT * FROM fn_store_kpis(1, '2025-01-01', '2025-12-31');
*/
CREATE OR REPLACE FUNCTION fn_store_kpis(
  p_store_id INT,
  p_start DATE,
  p_end   DATE
)
RETURNS TABLE (
  store_id INT,
  start_date DATE,
  end_date DATE,
  tickets BIGINT,
  sales_lines BIGINT,
  revenue NUMERIC(14,2),
  gross_margin NUMERIC(14,2),
  avg_ticket NUMERIC(14,2),
  avg_discount_pct NUMERIC(8,4)
)
LANGUAGE sql
AS $$
  WITH base AS (
    SELECT
      fs.ticket_id,
      fs.net_amount,
      (fs.net_amount - (fs.quantity * fs.unit_cost_snapshot)) AS line_margin,
      fs.discount_pct
    FROM fact_sales fs
    JOIN dim_calendar dc ON dc.date_id = fs.sale_date_id
    WHERE fs.store_id = p_store_id
      AND dc.full_date BETWEEN p_start AND p_end
  ),
  agg AS (
    SELECT
      COUNT(DISTINCT ticket_id) AS tickets,
      COUNT(*) AS sales_lines,
      COALESCE(SUM(net_amount),0) AS revenue,
      COALESCE(SUM(line_margin),0) AS gross_margin,
      COALESCE(AVG(discount_pct),0) AS avg_discount_pct
    FROM base
  )
  SELECT
    p_store_id,
    p_start,
    p_end,
    agg.tickets,
    agg.sales_lines,
    agg.revenue,
    agg.gross_margin,
    CASE WHEN agg.tickets = 0 THEN 0 ELSE ROUND(agg.revenue / agg.tickets, 2) END AS avg_ticket,
    agg.avg_discount_pct
  FROM agg;
$$;
