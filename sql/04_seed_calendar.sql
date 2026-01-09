-- 04_seed_calendar.sql
-- Rellena dim_calendar para Q1 2025 (ajustable). Reproducible y sin NULLs.

BEGIN;

-- Puedes ampliar el rango aquí (Q1, año entero, etc.)
WITH params AS (
  SELECT '2025-01-01'::date AS start_date,
         '2025-03-31'::date AS end_date
)
INSERT INTO dim_calendar (date_id, full_date, day_num, month_num, year_num, weekday_num, is_weekend)
SELECT
  (to_char(d,'YYYYMMDD'))::int AS date_id,
  d::date AS full_date,
  EXTRACT(DAY FROM d)::int AS day_num,
  EXTRACT(MONTH FROM d)::int AS month_num,
  EXTRACT(YEAR FROM d)::int AS year_num,
  EXTRACT(ISODOW FROM d)::int AS weekday_num,
  (EXTRACT(ISODOW FROM d) IN (6,7)) AS is_weekend
FROM params,
     generate_series(params.start_date, params.end_date, interval '1 day') AS d
ON CONFLICT (date_id) DO NOTHING;

COMMIT;
