# SQL Module Project — Star Schema + EDA (PostgreSQL + Docker)

## 1. Objetivo
Diseñar, implementar y analizar una base de datos relacional con un enfoque dimensional (Star Schema) para un dominio de ventas retail (3 tiendas + varios métodos de pago), garantizando integridad referencial y extrayendo insights de negocio mediante SQL avanzado.

**Motor:** PostgreSQL (Docker)  
**IDE recomendado:** VS Code / DBeaver / pgAdmin

---

## 2. Modelo de datos (Star Schema)

### Tabla de hechos (Fact)
**`fact_sales`** — *Granularidad: línea de ticket*  
Cada fila representa una línea de venta (producto) dentro de un ticket y guarda “snapshots” de precio/coste para preservar histórico.

Campos clave:
- `ticket_id` (nº de ticket)
- `sale_date_id` (FK a calendario)
- `store_id` (FK a tienda)
- `product_id` (FK a producto)
- `customer_id` (FK a cliente, opcional)
- `employee_id` (FK a empleado)
- `payment_method_id` (FK a método de pago)
- `quantity`, `unit_price_snapshot`, `unit_cost_snapshot`, `discount_pct`
- Métricas calculadas/derivadas: `gross_amount`, `net_amount`, `gross_margin` (según implementación)

**Constraint importante**
- `UNIQUE(ticket_id, product_id)` para evitar duplicar el mismo producto dentro del mismo ticket.

### Tablas de dimensiones (Dims)
- **`dim_calendar`** — Q1 2025; incluye `weekday_num` e `is_weekend` para análisis temporal.
- **`dim_store`** — 3 tiendas (Bar Costa, Estanco Centro, Tienda Online) + tipo + provincia.
- **`dim_product`** — catálogo con categoría (TABACO, VAPER, BEBIDA, SNACK, OTROS) y coste/precio.
- **`dim_customer`** — clientes (con email único) para segmentación.
- **`dim_employee`** — empleados para análisis por atención/turno.
- **`dim_payment_method`** — EFECTIVO, TARJETA, BIZUM, ONLINE.
- **`dim_province`** — provincia asociada a tienda.

---

## 3. Alcance y decisiones de diseño
**Dentro del alcance**
- Modelo dimensional orientado a análisis (reporting/BI).
- Integridad de datos (PK/FK/UNIQUE/CHECK/NOT NULL).
- EDA con SQL avanzado: JOINs, CTEs, ventanas, views, función.

**Fuera del alcance**
- Gestión de inventario/stock, devoluciones, promociones complejas multi-producto.
- Modelado de sesiones online o comportamiento de navegación.

**Normalización**
- Las entidades maestras (producto, tienda, cliente, método de pago, calendario) están normalizadas en dimensiones.
- La tabla de hechos mantiene snapshots de precio/coste para consistencia histórica (no depende de cambios en dim_product).

---

## 4. Cómo ejecutar (desde cero)

### 4.1 Levantar PostgreSQL con Docker
```bash
docker compose up -d

###4.2 Ejecutar scripts en orden

Nota: usar ON_ERROR_STOP=1 para abortar ante cualquier fallo.

# 1) Esquema + constraints + índices + vista + función
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/01_schema.sql

# 2) Datos de dimensiones (si aplica)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/02_data.sql

# 3) Calendario (Q1 2025)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/04_seed_calendar.sql

# 4) Seed fact_sales (determinista, escalable)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/05_seed_fact_sales.sql

# 5) EDA (core)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -P pager=off -f /sql/03_eda.sql

##5. Dataset simulado (reproducible)

El seed genera:

500 tickets

~1.200–1.600 líneas de venta (1–4 líneas por ticket)

Ventas repartidas en enero–marzo 2025

Reparto por tienda (round-robin) y por método de pago (25% cada uno)

Ejemplo de reparto observado:

Bar Costa: ~167 tickets

Estanco Centro: ~167 tickets

Tienda Online: ~166 tickets

Métodos de pago:

EFECTIVO / TARJETA / BIZUM / ONLINE ≈ 125 tickets cada uno

## 6. KPIs e insights (EDA)
### 6.1 Tendencia mensual

Revenue y nº tickets por mes

Ticket medio (revenue / tickets)

Decisión: detectar caída de revenue o cambios de ticket medio y ajustar mix/promos.

6.2 Impacto de descuentos

Segmentación por buckets (SIN_DESCUENTO, BAJO, MEDIO) comparando:

revenue

margen bruto

Decisión: definir política de descuentos maximizando margen.

6.3 Productos top

Ranking de productos y categorías por revenue.

Decisión: priorizar stock/rotación y cross-sell.

6.4 Finde vs laborable

Comparativa usando is_weekend.

Decisión: activar campañas de upsell en fines de semana.

6.5 Comparativa por tienda y método de pago

Revenue/tickets por tienda

Revenue/tickets por método de pago

Decisión: optimizar canal online, analizar comisiones, preferencias de pago.

7. Objetos SQL destacados

VIEW: vw_sales_enriched (ventas enriquecidas con dimensiones).

FUNCIÓN: fn_store_kpis(p_store_id, p_start_date, p_end_date) devuelve KPIs por tienda y rango.

ÍNDICES: sobre claves frecuentes para JOIN/filtrado (ej. fecha/tienda/ticket).

8. Guion de presentación (10 min)

Contexto y objetivo (30s)

Modelo dimensional y granularidad (2 min)

Integridad (PK/FK/constraints) + decisión de snapshots (1 min)

Seed reproducible + volumen (1 min)

EDA (4 min): tendencia mensual, descuentos vs margen, top productos, finde vs laborable, comparativa por tienda/pago

Decisiones de negocio (1.5 min)

Cierre + mejoras futuras (30s)

9. Mejoras futuras

Añadir más tiendas/provincias y ampliar calendario a año completo.

Segmentar clientes (RFM), cohortes, fidelización.

Modelar devoluciones y promociones avanzadas.

Introducir costes de pago (comisiones) y medir margen neto real.