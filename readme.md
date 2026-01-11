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
```
### 4.2 Ejecutar scripts en orden

**Nota:** usar `ON_ERROR_STOP=1` para abortar ante cualquier fallo.

```bash
# 1) Esquema + constraints + índices + vista + función
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/01_schema.sql

# 2) Datos de dimensiones (si aplica)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/02_data.sql

# 3) Calendario (Q1 2025)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/04_seed_calendar.sql

# 4) Seed fact_sales (determinista, escalable)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -v ON_ERROR_STOP=1 -f /sql/05_seed_fact_sales.sql
```
# 5) EDA (core)
docker exec -it sql_mod_postgres psql -U torres -d sql_mod -P pager=off -f /sql/03_eda.sql

## 5. Dataset simulado (reproducible)

El conjunto de datos se genera de forma **determinista y reproducible** mediante scripts SQL, permitiendo repetir los análisis y validar resultados sin variaciones entre ejecuciones.

### Volumen y granularidad

- **500 tickets** generados
- **~1.200–1.600 líneas de venta**  
  (entre **1 y 4 líneas por ticket**)
- **Granularidad:** línea de ticket (producto vendido)

### Distribución temporal

- Ventas repartidas entre **enero y marzo de 2025**
- Calendario generado previamente mediante `seed_calendar`
- Permite análisis por:
  - mes
  - día
  - día de la semana
  - fin de semana vs laborable

### Distribución por tienda

Asignación **round-robin** para evitar sesgos:

- **Bar Costa:** ~167 tickets  
- **Estanco Centro:** ~167 tickets  
- **Tienda Online:** ~166 tickets  

Esta distribución permite comparativas homogéneas entre tiendas.

### Distribución por método de pago

Reparto equilibrado (≈25% cada uno):

- **EFECTIVO**
- **TARJETA**
- **BIZUM**
- **ONLINE**

≈ **125 tickets por método de pago**, facilitando análisis comparativos de comportamiento y canal.

### Precios, costes y descuentos

- Precio y coste capturados como **snapshot** en la tabla de hechos
- Descuentos aplicados de forma controlada:
  - `SIN_DESCUENTO`
  - `DESCUENTO_BAJO`
  - `DESCUENTO_MEDIO`
- Permite análisis realistas de:
  - revenue
  - margen bruto
  - impacto de promociones

### Objetivo del dataset

El dataset está diseñado para:

- Simular un entorno **retail realista**
- Soportar **EDA avanzado**
- Permitir extracción de **KPIs de negocio**
- Servir como base para ampliaciones futuras (más tiendas, clientes, promociones)

El enfoque prioriza **calidad analítica**, **coherencia dimensional** y **facilidad de reproducción**.

## 6. KPIs e insights (EDA)

El análisis exploratorio de datos (EDA) tiene como objetivo convertir los datos de ventas en **información accionable**, identificando patrones, tendencias y palancas clave de negocio.

Los KPIs se calculan sobre la vista `vw_sales_enriched`, lo que garantiza consistencia dimensional y simplifica las consultas analíticas.

---

### 6.1 Tendencia mensual

**KPIs analizados:**
- Revenue mensual
- Número de tickets
- Ticket medio (`revenue / tickets`)

**Insight:**
- Identificación de crecimiento o caída del revenue.
- Detección de cambios en el comportamiento del cliente a través del ticket medio.

**Decisión de negocio:**
- Ajustar mix de productos y promociones.
- Corregir desviaciones tempranas en ventas.

---

### 6.2 Impacto de descuentos

Segmentación por *buckets* de descuento:
- `SIN_DESCUENTO`
- `DESCUENTO_BAJO`
- `DESCUENTO_MEDIO`

**KPIs analizados:**
- Revenue
- Margen bruto
- Porcentaje de margen

**Insight:**
- Evaluar si los descuentos incrementan volumen a costa de margen.
- Identificar el punto óptimo de descuento.

**Decisión de negocio:**
- Definir una política de descuentos orientada a maximizar margen total.
- Eliminar descuentos no rentables.

---

### 6.3 Productos y categorías top

**KPIs analizados:**
- Revenue por producto
- Revenue por categoría
- Margen bruto por producto

**Insight:**
- Identificación de productos y categorías con mayor aportación al negocio.
- Detección de productos de alta rotación y alto margen.

**Decisión de negocio:**
- Priorizar stock y reposición.
- Diseñar estrategias de *cross-sell* y *upsell*.

---

### 6.4 Fin de semana vs días laborables

Comparativa basada en el atributo `is_weekend`.

**KPIs analizados:**
- Revenue
- Número de tickets
- Ticket medio

**Insight:**
- Diferencias claras de comportamiento entre días laborables y fines de semana.

**Decisión de negocio:**
- Activar campañas específicas en fines de semana.
- Ajustar horarios y recursos operativos.

---

### 6.5 Comparativa por tienda y método de pago

**KPIs analizados:**
- Revenue y tickets por tienda
- Revenue y tickets por método de pago
- Ticket medio por canal

**Insight:**
- Identificación de tiendas con mejor rendimiento.
- Análisis de preferencias de pago del cliente.

**Decisión de negocio:**
- Optimizar el canal online.
- Evaluar costes y comisiones de los métodos de pago.
- Adaptar la oferta a los hábitos del cliente.

---

### Conclusión del EDA

El EDA permite:
- Validar la coherencia del modelo dimensional.
- Extraer KPIs clave de negocio.
- Transformar datos en decisiones operativas y estratégicas.

Este análisis constituye la base para futuras ampliaciones analíticas y modelos más avanzados.

## 7. Objetos SQL destacados

El proyecto incorpora distintos objetos SQL diseñados para **facilitar el análisis**, **optimizar el rendimiento** y **reutilizar lógica de negocio**, siguiendo buenas prácticas de modelado dimensional.

---

### 7.1 Vista analítica

**VIEW:** `vw_sales_enriched`

Vista de ventas enriquecidas que integra la tabla de hechos con todas las dimensiones relevantes.

**Características:**
- JOINs predefinidos con:
  - calendario
  - tienda
  - producto
  - cliente (opcional)
  - empleado
  - método de pago
- Campos derivados:
  - `is_weekend`
  - revenue
  - margen bruto
- Simplifica las consultas de EDA y reporting

**Beneficio:**
- Reduce complejidad SQL
- Asegura consistencia analítica
- Acelera el desarrollo de KPIs

---

### 7.2 Función de KPIs por tienda

**FUNCIÓN:** `fn_store_kpis(p_store_id, p_start_date, p_end_date)`

Función SQL que devuelve los principales KPIs de una tienda para un rango temporal dado.

**KPIs devueltos:**
- Revenue total
- Número de tickets
- Ticket medio
- Margen bruto

**Casos de uso:**
- Análisis por tienda
- Comparativas temporales
- Integración con dashboards o BI

**Beneficio:**
- Reutilización de lógica
- Parametrización cla

## 8. Guion de presentación (10 minutos)

### 1. Contexto y objetivo (30 segundos)
- Presentación del problema de negocio
- Necesidad de un modelo de datos que permita análisis fiables de ventas
- Objetivo: transformar datos transaccionales en información accionable

---

### 2. Modelo dimensional y granularidad (2 minutos)
- Elección de un modelo **Star Schema**
- Tabla de hechos con granularidad a **línea de ticket**
- Dimensiones desacopladas para:
  - calendario
  - tienda
  - producto
  - cliente
  - empleado
  - método de pago
- Ventaja: simplicidad analítica y escalabilidad

---

### 3. Integridad y diseño histórico (1 minuto)
- Uso de **PK/FK** y constraints para garantizar

## 9. Mejoras futuras

El modelo ha sido diseñado con un enfoque **escalable y evolutivo**, permitiendo incorporar nuevas dimensiones, métricas y casos de uso sin rehacer la base existente.

### 9.1 Ampliación del alcance

- Añadir nuevas tiendas y provincias
- Extender el calendario a un ejercicio completo o multianual
- Incrementar volumen de datos para pruebas de rendimiento

### 9.2 Analítica de clientes

- Incorporar segmentación **RFM** (Recencia, Frecuencia, Monetary)
- Análisis de cohortes y fidelización
- Identificación de clientes de alto valor

### 9.3 Promociones y devoluciones

- Modelar devoluciones como evento independiente
- Soportar promociones avanzadas:
  - descuentos acumulativos
  - campañas temporales
  - cupones
- Medición del impacto real de promociones sobre margen

### 9.4 Optimización de margen real

- Introducir costes por método de pago (comisiones)
- Cálculo de margen neto real
- Comparativa entre revenue bruto y rentabilidad efectiva

### 9.5 Evolución hacia BI y Data Science

- Integración con herramientas BI (Power BI, Tableau, Metabase)
- Automatización de KPIs
- Base para modelos predictivos:
  - previsión de ventas
  - detección de anomalías
  - optimización de descuentos

---

### Cierre

Estas mejoras permitirían evolucionar el proyecto desde un **modelo analítico sólido** hacia una **plataforma completa de Business Intelligence y Data Analytics**, alineada con necesidades reales de negocio.
