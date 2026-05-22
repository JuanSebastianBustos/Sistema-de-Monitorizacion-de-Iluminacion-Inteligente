# Guía de Implementación — Sistema Web
## Sistema de Monitorización de Iluminación Inteligente · Bogotá D.C.
**Integrante 2 · Backend Flask + Frontend HTML/JS · Conexión local a SQL Server DW**

---

## Índice

1. [Decisiones de arquitectura y justificación](#1-decisiones-de-arquitectura-y-justificación)
2. [Estructura del proyecto](#2-estructura-del-proyecto)
3. [Estrategia crítica con 1 millón de registros](#3-estrategia-crítica-con-1-millón-de-registros)
4. [Vistas SQL que alimentan la web](#4-vistas-sql-que-alimentan-la-web)
5. [API REST — Endpoints por sección](#5-api-rest--endpoints-por-sección)
6. [Páginas del sistema web](#6-páginas-del-sistema-web)
7. [Sistema de filtros y cómo replicar los de Power BI](#7-sistema-de-filtros-y-cómo-replicar-los-de-power-bi)
8. [Sistema de diseño visual — coherencia con el dashboard](#8-sistema-de-diseño-visual--coherencia-con-el-dashboard)
9. [Integración con los JSONs del modelo ML](#9-integración-con-los-jsons-del-modelo-ml)
10. [Plan de ejecución por días](#10-plan-de-ejecución-por-días)
11. [Dependencias críticas con otros integrantes](#11-dependencias-críticas-con-otros-integrantes)

---

## 1. Decisiones de Arquitectura y Justificación

### 1.1 Por qué Flask y no otra opción

Flask es la elección correcta para este proyecto por tres razones concretas:

**Velocidad de desarrollo.** Flask no impone estructura. Puedes tener un endpoint respondiendo datos en 10 líneas de Python. Frameworks más completos como Django requieren configuración de proyecto, ORM, migraciones y una curva de aprendizaje que no tienes tiempo de pagar.

**Conexión directa a SQL Server.** Flask usa Python puro, por lo que `pyodbc` (el driver de Microsoft para SQL Server) funciona sin adaptaciones. La alternativa de un frontend estático con JSONs te obligaría a exportar todos los datos de antemano y perderías cualquier interactividad de filtros real.

**Rol claro.** Flask actúa como intermediario entre el navegador y la base de datos: recibe una petición con parámetros de filtro, ejecuta una consulta SQL pre-agregada, y devuelve el resultado en JSON. El navegador solo renderiza lo que recibe; no accede directamente a la BD.

### 1.2 División de responsabilidades

```
NAVEGADOR (HTML + JS)
    │  Envía parámetros de filtro (zona, clima, período)
    │  Recibe JSON de respuesta
    │  Renderiza con Chart.js y Leaflet.js
    ▼
FLASK (Python — servidor local)
    │  Recibe la petición HTTP
    │  Construye la consulta SQL con los filtros
    │  Ejecuta contra el DW
    │  Devuelve JSON limpio
    ▼
SQL SERVER (DW — IluminacionBogota_DW)
    │  Ejecuta la consulta sobre las VISTAS pre-agregadas
    │  NUNCA devuelve filas crudas de FactConsumoIluminacion
    ▼
VISTAS SQL (creadas una sola vez)
    Agrupan y calculan todo lo necesario
    Reducen 1M de filas a decenas o cientos de filas
```

### 1.3 Librerías del frontend — Justificación

| Librería | Propósito | Por qué esta y no otra |
|---|---|---|
| **Bootstrap 5** (CDN) | Layout responsivo, navbar, tarjetas | No construir CSS desde cero. CDN = sin instalación. |
| **Chart.js** (CDN) | Gráficos de línea, barra, scatter, doughnut | API simple, funciona sin Node.js, compatible con los ejemplos del plan de trabajo |
| **Leaflet.js** (CDN) | Mapa interactivo de Bogotá con GeoJSON | El más liviano para mapas choropleth. No requiere API key (a diferencia de Google Maps) |
| **chartjs-plugin-annotation** (CDN) | Líneas de referencia en gráficos | Para replicar las líneas de referencia del dashboard de Power BI |

Todo via CDN significa: sin `npm`, sin `package.json`, sin proceso de compilación. Los archivos HTML funcionan directamente.

### 1.4 Lo que NO se va a hacer y por qué

- **No WebSockets / datos en tiempo real.** El DW es un snapshot analítico, no una fuente viva. Los datos se refrescan por petición del usuario.
- **No React/Vue.** Exceso de complejidad para el tiempo disponible. JS vanilla es suficiente.
- **No ORM (SQLAlchemy models).** Se usan consultas SQL directas sobre vistas. Más rápido de escribir y de depurar.
- **No autenticación.** Es un sistema académico local. Login haría perder tiempo sin aporte al objetivo.

---

## 2. Estructura del Proyecto

```
/web
├── app.py                        ← Aplicación Flask principal (el servidor)
├── config.py                     ← Cadena de conexión a SQL Server (separada del código)
├── db.py                         ← Función de conexión y utilidades de base de datos
│
├── /routes                       ← Blueprints de Flask, uno por sección analítica
│   ├── __init__.py
│   ├── api_general.py            ← KPIs globales y serie temporal (Página General)
│   ├── api_zonas.py              ← Datos por localidad para mapa y tabla (DimZona)
│   ├── api_tiempo.py             ← Heatmap hora×día y patrones temporales (DimTiempo)
│   ├── api_tecnologia.py         ← Datos por tipo de lámpara (DimLuminaria)
│   ├── api_politica.py           ← Cumplimiento de directrices (DimPolitica)
│   ├── api_clima.py              ← Correlaciones climáticas (DimClima)
│   ├── api_sensor.py             ← Estado del inventario de sensores (DimSensor)
│   └── api_ml.py                 ← Lee los JSONs del modelo ML y los sirve
│
├── /templates                    ← Plantillas HTML (renderizadas por Flask/Jinja2)
│   ├── base.html                 ← Layout base: navbar, CSS comunes, footer
│   ├── index.html                ← Portada del proyecto
│   ├── dashboard.html            ← Vista General (Página 1 del dashboard)
│   ├── zonas.html                ← Análisis por Zona (Página 2)
│   ├── tiempo.html               ← Análisis Temporal (Página 3)
│   ├── tecnologia.html           ← Tecnología e Inventario (Página 4)
│   ├── politica.html             ← Cumplimiento de Políticas (Página 5)
│   ├── clima.html                ← Contexto Climático (Página 6)
│   ├── sensor.html               ← Estado de Sensores (Página 7)
│   └── modelo_ml.html            ← Modelo Machine Learning
│
├── /static
│   ├── /css
│   │   └── styles.css            ← Variables CSS del sistema de diseño visual
│   ├── /js
│   │   ├── utils.js              ← Función fetch reutilizable y helpers comunes
│   │   ├── dashboard.js          ← Lógica de gráficos de la vista general
│   │   ├── zonas.js              ← Lógica del mapa Leaflet y tabla de zonas
│   │   ├── tiempo.js             ← Heatmap y gráficos temporales
│   │   ├── tecnologia.js         ← Scatter y barras de tecnología
│   │   ├── politica.js           ← Gauges y mapa de cumplimiento
│   │   ├── clima.js              ← Scatter de correlación climática
│   │   ├── sensor.js             ← Mapa de burbujas y tabla de sensores
│   │   └── modelo_ml.js          ← Explorador interactivo del modelo
│   └── /data
│       ├── bogota_localidades.geojson  ← GeoJSON compartido con el Integrante 1
│       ├── resumen_zonas.json          ← Del Integrante 4 (día 3)
│       ├── consumo_horario.json        ← Del Integrante 4 (día 3)
│       └── resultados_modelo.json      ← Del Integrante 4 (día 4)
│
└── requirements.txt              ← Flask, pyodbc, flask-cors
```

### Por qué esta estructura

**Blueprints de Flask por sección analítica:** cada archivo en `/routes` agrupa los endpoints de una dimensión del DW. Si hay un error en los datos de tiempo, sabes exactamente a qué archivo ir. Si la página de zonas está lenta, sabes qué vista SQL revisar. La separación también permite desarrollar una página a la vez sin tocar el resto.

**Templates Jinja2:** Flask renderiza el HTML en el servidor. Esto permite que `base.html` defina el layout completo (navbar, links de CSS/JS, footer) una sola vez, y cada página específica solo declare su contenido. Cambiar el navbar en todas las páginas = cambiar un solo archivo.

**`/data` para los JSONs del ML:** el modelo ML no necesita pasar por Flask; el navegador puede cargar esos JSONs directamente con `fetch()`. Flask los sirve como archivos estáticos. Esto simplifica la integración con el Integrante 4: solo copiar los JSONs a esa carpeta.

---

## 3. Estrategia Crítica con 1 Millón de Registros

Este es el punto técnico más importante de toda la implementación. Si se ignora, el sistema web tardará minutos en cargar y será inutilizable.

### 3.1 La regla fundamental

> **Nunca ejecutar una consulta que devuelva filas crudas de `FactConsumoIluminacion` al servidor Flask, y mucho menos al navegador.**

El navegador no puede procesar 1 millón de registros. Flask tampoco debería intentarlo. Toda la agregación ocurre en SQL Server, que está optimizado para eso.

### 3.2 Qué significa en práctica

Cuando el usuario selecciona una zona en el filtro y pide ver el consumo horario, la consulta que ejecuta Flask **no es**:

```
"Dame todas las filas de FactConsumoIluminacion donde zona_id = 7"
→ Resultado: potencialmente 50.000 filas → inutilizable
```

La consulta **sí es**:

```
"Dame el promedio de kWh agrupado por hora del día, para zona_id = 7"
→ Resultado: exactamente 24 filas (una por hora) → instantáneo
```

La diferencia entre un sistema que carga en 200ms y uno que tarda 3 minutos está en esta decisión.

### 3.3 El rol de las vistas SQL

Las vistas SQL (creadas una sola vez en SQL Server) encapsulan la lógica de agregación. Flask solo llama a la vista con los filtros correspondientes. Las vistas se describen en la siguiente sección.

### 3.4 Cómo manejar los filtros sin riesgo de rendimiento

Los filtros del usuario (zona, clima, período) se pasan como parámetros a la consulta SQL, que los aplica en el `WHERE` **antes** de hacer el `GROUP BY`. Esto significa que SQL Server filtra primero (reduciendo el conjunto de datos) y luego agrega (calculando los totales). El orden correcto es filtrar → agregar → devolver, no agregar todo y luego filtrar en Python.

---

## 4. Vistas SQL que Alimentan la Web

Estas vistas se crean una sola vez en `IluminacionBogota_DW`. Son el trabajo de preparación más importante antes de escribir una línea de Flask.

> **Coordinación con Integrante 1:** estas vistas usan las mismas tablas del DW que Power BI. Si el Integrante 1 puede crearlas en SSMS, ahorras tiempo. Si no, las creas tú con acceso a SSMS.

### Vista 1: `vw_kpis_generales`

**Propósito:** Alimentar las 4 tarjetas KPI de la vista general y el inicio.

**Qué calcula:** total de kWh consumidos, costo total en COP, total de anomalías, ahorro estimado en kWh, porcentaje de luminarias encendidas, número de sensores activos, número de zonas monitoreadas.

**Filtros que acepta la consulta:** rango de fechas, zona_id, condicion_clima.

**Resultado:** siempre una sola fila con los totales. No importa cuántos registros haya en la fact table; la vista siempre devuelve exactamente 1 fila.

---

### Vista 2: `vw_consumo_por_zona`

**Propósito:** Alimentar el mapa de Bogotá choropleth y la tabla de resumen de zonas.

**Qué calcula:** agrupado por `zona_id` y `nombre_zona`, calcula kWh total, costo COP total, promedio de lux, total de anomalías, kWh por habitante (dividiendo entre `poblacion` de `DimZona`), kWh por km², lux óptimo promedio (si ya tiene predicciones del ML), porcentaje de cumplimiento horario.

**Resultado:** exactamente 20 filas (una por localidad de Bogotá). El mapa toma estas 20 filas y colorea cada localidad según `kwh_total`.

---

### Vista 3: `vw_consumo_por_hora`

**Propósito:** Alimentar el gráfico de consumo horario (línea) y el heatmap hora×día.

**Qué calcula:** agrupado por `hora` (0–23) y `nombre_dia` (Lunes–Domingo), calcula kWh promedio, lux promedio, lux óptimo promedio, porcentaje de luminarias encendidas, total de anomalías.

**Resultado:** 24 filas para el gráfico de línea (consumo por hora), o 168 filas (24 horas × 7 días) para el heatmap. Ambos son manejables en el navegador.

---

### Vista 4: `vw_consumo_por_tecnologia`

**Propósito:** Alimentar el gráfico comparativo por tipo de lámpara (página DimLuminaria).

**Qué calcula:** agrupado por `tipo_lampara`, calcula kWh total, kWh promedio por luminaria, lux promedio, eficiencia (lux / kWh), total de anomalías, porcentaje del consumo total que representa cada tecnología, número de luminarias de ese tipo.

**Resultado:** tantas filas como tipos de lámpara existan en el DW (probablemente 4–6 filas: LED, sodio, haluro, mercurio, etc.).

---

### Vista 5: `vw_cumplimiento_politicas`

**Propósito:** Alimentar los gauges y el mapa de cumplimiento (página DimPolitica).

**Qué calcula:** agrupado por `zona_id`, calcula porcentaje de cumplimiento horario (registros nocturnos con luminaria encendida / total registros nocturnos), porcentaje de cumplimiento de lux (registros nocturnos donde `nivel_lux >= nivel_lux_umbral` de la política), total de kWh desperdiciados (luminarias encendidas de día), costo del incumplimiento en COP.

**Resultado:** 20 filas (una por zona) más una fila de totales globales para los gauges.

---

### Vista 6: `vw_consumo_por_clima`

**Propósito:** Alimentar el scatter de correlación climática (página DimClima).

**Qué calcula:** agrupado por `condicion_clima` y `cobertura_nubosa_pct` (en rangos de 10%), calcula kWh promedio, lux promedio, radiación solar promedio, temperatura promedio, total de registros para ese grupo climático.

**Resultado:** pocas decenas de filas (combinaciones de condición climática y rangos de nubosidad).

---

### Vista 7: `vw_estado_sensores`

**Propósito:** Alimentar el mapa de burbujas y la tabla de estado de sensores (página DimSensor).

**Qué calcula:** agrupado por `sensor_id`, trae la latitud, longitud, zona, tipo de sensor, fecha del último mantenimiento, días desde el último mantenimiento, total de anomalías generadas por ese sensor, estado actual (activo/inactivo).

**Resultado:** una fila por sensor (máximo 500 filas según el planteamiento del proyecto).

---

### Vista 8: `vw_serie_temporal_mensual`

**Propósito:** Alimentar el gráfico de línea de la serie temporal con comparativo interanual.

**Qué calcula:** agrupado por año y mes, calcula kWh total, costo COP, total de anomalías. La comparación interanual (año actual vs año anterior) se calcula en Python al preparar la respuesta JSON, no en SQL.

**Resultado:** una fila por mes del período cubierto por el dataset (probablemente 24 filas para 2 años de datos).

---

## 5. API REST — Endpoints por Sección

Flask expone estos endpoints. Todos devuelven JSON. Todos aceptan parámetros de filtro opcionales en la query string de la URL.

### Formato general de los endpoints

```
GET /api/<seccion>?zona_id=7&clima=Despejado&periodo=nocturno
    │                  └── Parámetros de filtro opcionales
    └── Prefijo común para todos los endpoints de datos
```

Cuando el parámetro no se envía, la consulta no aplica ese filtro (devuelve todos los datos). Esto permite que la misma función sirva tanto la vista global como la vista filtrada.

---

### Endpoints de la Vista General (Página 1)

**`GET /api/kpis`**
- Qué devuelve: objeto JSON con los 4 KPIs globales (total kWh, costo COP, anomalías, ahorro estimado ML)
- Parámetros aceptados: `zona_id`, `clima`, `fecha_inicio`, `fecha_fin`
- Usa: vista `vw_kpis_generales`
- El frontend lo llama al cargar la página y cada vez que el usuario cambia un filtro

**`GET /api/serie-temporal`**
- Qué devuelve: array JSON con una entrada por mes, incluyendo el valor del año anterior para comparativo
- Parámetros aceptados: `zona_id`, `clima`
- Usa: vista `vw_serie_temporal_mensual`
- El frontend lo usa para el gráfico de línea de la vista general

---

### Endpoints de Zonas (Página DimZona)

**`GET /api/zonas`**
- Qué devuelve: array JSON con una entrada por localidad, incluyendo todos los indicadores necesarios para el mapa y la tabla
- Parámetros aceptados: `clima`, `fecha_inicio`, `fecha_fin`
- Usa: vista `vw_consumo_por_zona`
- El frontend lo usa para colorear el mapa y poblar la tabla ordenable

**`GET /api/zonas/<int:zona_id>`**
- Qué devuelve: objeto JSON con el detalle de una zona específica (para el popup del mapa)
- Sin parámetros adicionales
- Usa: vista `vw_consumo_por_zona` filtrada por zona_id

---

### Endpoints de Tiempo (Página DimTiempo)

**`GET /api/consumo-horario`**
- Qué devuelve: array de 24 objetos (uno por hora), con kWh promedio, lux promedio y lux óptimo
- Parámetros aceptados: `zona_id`, `clima`, `tipo_dia` (laborable/fin de semana)
- Usa: vista `vw_consumo_por_hora` agrupada solo por hora
- El frontend lo usa para el gráfico de línea del consumo horario

**`GET /api/heatmap`**
- Qué devuelve: array de 168 objetos (24 horas × 7 días), con el kWh total para cada celda
- Parámetros aceptados: `zona_id`, `clima`
- Usa: vista `vw_consumo_por_hora` agrupada por hora y día de semana
- El frontend lo usa para construir el heatmap (Página DimTiempo)

---

### Endpoints de Tecnología (Página DimLuminaria)

**`GET /api/tecnologia`**
- Qué devuelve: array con una entrada por tipo de lámpara, incluyendo kWh, lux, eficiencia y anomalías
- Sin parámetros de filtro (el análisis de tecnología es global)
- Usa: vista `vw_consumo_por_tecnologia`

---

### Endpoints de Políticas (Página DimPolitica)

**`GET /api/cumplimiento`**
- Qué devuelve: objeto con los porcentajes globales de cumplimiento (para los gauges) y array por zona (para el mapa)
- Parámetros aceptados: `fecha_inicio`, `fecha_fin`
- Usa: vista `vw_cumplimiento_politicas`

---

### Endpoints de Clima (Página DimClima)

**`GET /api/clima`**
- Qué devuelve: array de puntos para el scatter, cada punto con radiación solar, lux promedio, kWh y condición climática
- Sin parámetros de filtro principales (el análisis climático usa toda la variedad de condiciones)
- Usa: vista `vw_consumo_por_clima`

---

### Endpoints de Sensores (Página DimSensor)

**`GET /api/sensores`**
- Qué devuelve: array con una entrada por sensor, incluyendo latitud, longitud, días sin mantenimiento, anomalías y estado
- Parámetros aceptados: `zona_id`, `estado` (activo/inactivo)
- Usa: vista `vw_estado_sensores`

---

### Endpoint del Modelo ML

**`GET /api/ml/datos`**
- Qué devuelve: el contenido de `resultados_modelo.json` como respuesta JSON
- No consulta SQL Server; lee el archivo JSON directamente
- El frontend podría también cargar este JSON directamente con `fetch('/static/data/resultados_modelo.json')`, pero pasar por Flask es más limpio

---

## 6. Páginas del Sistema Web

El sistema web replica las 8 páginas del dashboard de Power BI más la página de inicio y la página del modelo ML. Cada página web corresponde directamente a una página del dashboard.

---

### Página 0: Portada (`index.html`)

**Equivale a:** la portada del dashboard de Power BI.

**Propósito:** contextualizar el proyecto para cualquier persona que acceda a la URL, no solo el profesor. Establecer el problema, la escala del sistema y los ODS antes de mostrar cualquier dato.

**Qué debe contener, sección por sección:**

**Hero section (ocupa el 50% de la pantalla inicial):**
- Fondo con el color institucional oscuro del proyecto (`#1B2A4A`)
- Nombre del proyecto: "Sistema de Monitorización de Iluminación Inteligente"
- Subtítulo: "Bogotá D.C. · Análisis Big Data para la Sostenibilidad Energética"
- 3 badges de ODS: ODS 7, ODS 11, ODS 13 con sus colores oficiales
- Un botón de llamada a la acción: "Ver el Dashboard" que navega a `dashboard.html`

**Por qué el hero es importante:** el profesor llega a la URL y lo primero que ve decide si el proyecto parece serio o improvisado. Cuatro palabras y los logos de ODS comunican contexto en segundos.

**Sección "El Problema" (sin datos dinámicos, texto estático):**
- Estadística de contexto: 400.000+ puntos de luz, gasto de $180.000 millones anuales en COP, ineficiencia estimada del 25–40%
- Estos datos vienen del planteamiento del proyecto, no de la BD. Son datos de contexto de la ciudad real de Bogotá.

**Sección "Escala del sistema" (4 tarjetas estáticas):**
- Replica las 4 tarjetas de la portada del dashboard: 500 sensores, 1.000.000 lecturas, 20 localidades, 2 años de datos
- Son valores fijos que describen el dataset, no se consultan de la BD

**Por qué estáticas:** estas métricas describen el sistema, no el análisis. No cambian con filtros. Cargarlas de la BD sería complejidad innecesaria.

**Sección "Cómo funciona el sistema" (4 pasos con íconos):**
- Paso 1: Sensores LDR capturan nivel de lux y consumo en cada luminaria
- Paso 2: Datos almacenados en SQL Server OLTP → transformados al Data Warehouse
- Paso 3: Análisis en Power BI y modelo de ML para detectar patrones
- Paso 4: Recomendaciones de política urbana para optimizar el alumbrado de Bogotá

**Sección "Tecnologías utilizadas" (logos/badges):**
- SQL Server, Python, Flask, Power BI, scikit-learn, Chart.js, Leaflet.js
- No hace falta ser exhaustivo; cubre las principales

**Sección "Equipo":**
- 4 tarjetas con nombre e integrante de cada miembro y su rol en el proyecto

**Footer:**
- Proyecto académico · Universidad · ODS 7 · ODS 11 · ODS 13

---

### Página 1: Vista General (`dashboard.html`)

**Equivale a:** Página 1 del dashboard (FactConsumoIluminacion — Vista General del sistema).

**Pregunta que responde:** ¿Cuál es el estado global del alumbrado de Bogotá en el período analizado?

**Estructura de la página:**

**Barra de filtros globales (fija en la parte superior, debajo del navbar):**
- Selector de localidad (dropdown multi-selección con las 20 localidades)
- Selector de condición climática (despejado, nublado, lluvia, etc.)
- Selector de período horario (todos / diurno 06:00–18:00 / nocturno 18:00–06:00)
- Botón "Aplicar filtros" que dispara la recarga de todos los gráficos de la página
- Botón "Limpiar filtros" que resetea los selectores y recarga datos globales

**Por qué botón "Aplicar" en vez de filtrado automático:** con una BD de 1M registros, cada cambio de filtro dispara una consulta SQL. Si el filtrado es automático al mover cualquier selector, un usuario que cambia 3 filtros seguidos genera 3 consultas, de las cuales 2 son innecesarias. El botón "Aplicar" agrupa todos los cambios en una sola consulta.

**4 tarjetas KPI (primera fila):**
- Total kWh: número grande, variación respecto al promedio mensual en porcentaje (▲ rojo si sube, ▼ verde si baja)
- Costo Total COP: formato en millones de pesos para legibilidad
- Total Anomalías: número con badge de color (verde si < 2%, amarillo si 2–5%, rojo si > 5%)
- Ahorro Estimado kWh: proveniente del campo calculado por el modelo ML del Integrante 4

**Por qué estos 4:** son exactamente los 4 KPIs de la tarjeta principal del dashboard de Power BI. La coherencia entre web y dashboard es el criterio central del profesor.

**Gráfico de línea — Serie temporal mensual (segunda fila, mitad izquierda):**
- Eje X: meses del período (Ene 2023 – Dic 2024)
- Línea 1: kWh total por mes (azul institucional)
- Línea 2: kWh mismo período año anterior (línea gris punteada para comparativo)
- Área sombreada bajo la línea 1
- Replicar el comparativo interanual del dashboard

**Gráfico de barras — Top 10 zonas por consumo (segunda fila, mitad derecha):**
- Barras horizontales
- Las 10 localidades con mayor consumo en el período filtrado
- Color degradado del más consumidor (rojo) al décimo (azul claro)
- Tooltips con kWh y costo en COP

---

### Página 2: Análisis por Zona (`zonas.html`)

**Equivale a:** Página 2 del dashboard (DimZona — Análisis Geográfico).

**Pregunta que responde:** ¿Qué zonas concentran el mayor consumo, costo y riesgo de falla?

**Estructura:**

**Mapa choropleth de Bogotá (ocupa 60% del ancho de la pantalla, lado izquierdo):**
- Carga el GeoJSON de localidades de Bogotá
- Colorea cada localidad según `kwh_total` de la vista `vw_consumo_por_zona`
- Escala de color: verde (bajo consumo) → amarillo → rojo (alto consumo)
- Al hacer clic en una localidad, popup con: nombre, kWh total, lux promedio, anomalías, kWh por habitante
- Leyenda de escala de colores en la esquina inferior derecha del mapa

**Segundo mapa de cumplimiento (40% del ancho, lado derecho o debajo):**
- Misma estructura que el mapa de consumo pero coloreado por `pct_cumplimiento_horario`
- Escala invertida: verde = alto cumplimiento, rojo = bajo cumplimiento
- Este layout dual replica el visual más impactante del dashboard: misma geografía, dos ángulos
- Si el tiempo no alcanza para dos mapas, mostrar un selector que permita cambiar la métrica del mapa entre "Consumo" y "Cumplimiento"

**Por qué dos mapas (o el selector):** el insight central de la página DimZona del dashboard es que las zonas con mayor consumo y las zonas con menor cumplimiento son las mismas. Si solo se muestra un mapa, se pierde ese hallazgo.

**Ranking de zonas (gráfico de barras horizontal debajo del mapa):**
- Top 10 zonas por kWh por habitante (normalizado, no absoluto)
- Usar kWh/habitante en lugar de kWh total porque el consumo absoluto favorece a las zonas más grandes por área, no necesariamente por ineficiencia

**Tabla de indicadores (parte inferior):**
- Columnas: Localidad | kWh Total | kWh/Habitante | Lux Promedio | Anomalías | % Cumplimiento
- Ordenable haciendo clic en cada encabezado de columna (JavaScript nativo, sin librerías)
- Formato condicional en la columna "% Cumplimiento": celda roja si < 75%, amarilla si 75–90%, verde si > 90%
- Esta tabla reúne toda la información que en el dashboard está distribuida entre el tooltip y las tablas de Power BI

**Filtros de esta página:**
- Selector de condición climática (para ver cómo el clima afecta el consumo por zona)
- Toggle "Ver por: kWh Total / kWh por Habitante / kWh por km²" que cambia la métrica del mapa y el ranking sin recargar la página

---

### Página 3: Análisis Temporal (`tiempo.html`)

**Equivale a:** Página 3 del dashboard (DimTiempo — Patrones temporales).

**Pregunta que responde:** ¿En qué momentos del día, la semana y el año ocurren los patrones más costosos?

**Estructura:**

**Heatmap hora × día (visual estrella de la página):**
- Cuadrícula de 24 columnas (horas 0–23) × 7 filas (Lunes–Domingo)
- Cada celda muestra el kWh promedio para esa combinación hora–día
- Color de celda: blanco (bajo consumo) → azul claro → azul oscuro–rojo (alto consumo)
- Escala de color basada en Chart.js matrix plugin o implementación con D3.js
- El heatmap es el visual que mejor replica el de la Página DimTiempo del dashboard y que tiene mayor impacto visual

**Por qué el heatmap primero:** en el dashboard, el heatmap es el visual definitorio de la página temporal. Es el más memorable y el que más directamente responde la pregunta "¿cuándo ocurre el desperdicio?". Si el tiempo es limitado y solo se puede implementar un visual de esta página, este es el que hay que hacer.

**Gráfico de línea — Consumo horario (debajo del heatmap):**
- Eje X: horas del día (0–23)
- Línea 1: kWh promedio (azul institucional)
- Línea 2: lux promedio (verde)
- Línea 3: lux óptimo predicho por ML (verde punteado) — si el Integrante 4 entregó los datos
- Dos líneas de referencia verticales en hora 6 y hora 18 (inicio y fin del período diurno) — replicar las líneas de referencia del dashboard

**Gráfico de barras agrupadas — Laborable vs Fin de semana (parte inferior):**
- Una barra por zona (o por día de semana)
- Dos series: consumo promedio en días laborables y en fines de semana
- Replicar directamente el visual del dashboard que compara estos dos períodos

**Filtros de esta página:**
- Selector de zona (para ver los patrones temporales de una localidad específica)
- Selector de año (2023 / 2024 / ambos)

---

### Página 4: Tecnología e Inventario (`tecnologia.html`)

**Equivale a:** Página 4 del dashboard (DimLuminaria — Análisis de tecnología).

**Pregunta que responde:** ¿Cuánto más eficiente es LED respecto a las tecnologías anteriores?

**Estructura:**

**Gráfico de barras agrupadas — Comparativo por tipo de lámpara (parte superior):**
- Eje X: tipos de lámpara (LED, sodio, haluro, mercurio)
- Barra 1: kWh promedio por luminaria (eje Y izquierdo)
- Barra 2: lux promedio (eje Y derecho, escala secundaria)
- Esta comparación directa muestra cuánta luz produce cada tecnología por unidad de energía
- Usar los colores del sistema de diseño por tecnología

**Scatter de eficiencia (centro de la página):**
- Eje X: eficiencia (lux producido / kWh consumido) — mayor es mejor
- Eje Y: consumo total de kWh
- Un punto por zona × tipo de tecnología
- Color del punto: el tipo de tecnología (LED verde, sodio naranja, etc.)
- Tamaño del punto: proporcional al total de anomalías de esa combinación
- Cuadrante ideal marcado con anotación: "alta eficiencia, bajo consumo"
- Replicar directamente el scatter del dashboard de DimLuminaria

**Por qué el scatter:** es el visual que más claramente muestra la relación entre eficiencia y consumo. Un usuario puede ver de un vistazo qué tecnologías están en el cuadrante correcto y cuáles no, sin necesidad de leer tablas.

**Indicador de modernización (gauge donut):**
- Porcentaje de luminarias LED sobre el total
- Implementado con Chart.js tipo `doughnut`
- Replicar el gauge del dashboard

---

### Página 5: Cumplimiento de Políticas (`politica.html`)

**Equivale a:** Página 5 del dashboard (DimPolitica — Cumplimiento de directrices).

**Pregunta que responde:** ¿El sistema opera conforme a las directrices municipales y dónde están las brechas?

**Estructura:**

**2 gauges de cumplimiento (parte superior, lado a lado):**
- Gauge 1: % Cumplimiento Horario (luminarias encendidas de noche / total lecturas nocturnas)
- Gauge 2: % Cumplimiento de Lux (lecturas con lux ≥ umbral de la política / total lecturas nocturnas)
- Implementados con Chart.js tipo `doughnut` configurado como semicírculo
- Arco de color: rojo (0%) → amarillo → verde (100%)
- Línea de objetivo en 95% marcada con una pequeña etiqueta
- Replicar los medidores exactos del dashboard

**Mapa de incumplimiento (lado izquierdo):**
- El mismo mapa choropleth pero coloreado por `pct_cumplimiento_horario`
- Escala invertida: las zonas rojas son las que más incumplen
- Este es el segundo mapa que complementa el de consumo de la página de zonas

**Tabla de análisis de brechas (debajo del mapa):**
- Columnas: Zona | % Cumpl. Horario | % Cumpl. Lux | kWh Desperdiciados (encendido de día) | Costo Estimado del desperdicio en COP
- Formato condicional en las columnas de cumplimiento
- Ordenable por costo del incumplimiento (esto permite identificar las zonas donde más dinero se pierde)

**Gráfico de barras — Incumplimiento por hora del día:**
- En qué horas del día hay más luminarias encendidas cuando no deberían (o apagadas cuando deberían estar encendidas)
- Replicar el visual de incumplimiento por hora del dashboard

---

### Página 6: Contexto Climático (`clima.html`)

**Equivale a:** Página 6 del dashboard (DimClima — Análisis climático).

**Pregunta que responde:** ¿Cómo afecta el clima al comportamiento del sistema de alumbrado?

**Estructura:**

**Scatter de correlación clima–consumo (visual principal):**
- Eje X: radiación solar (W/m²)
- Eje Y: lux promedio
- Color del punto: condición climática (despejado, nublado, lluvia, etc.) — colores del sistema de diseño por condición
- Tamaño del punto: proporcional al kWh total de ese grupo
- El scatter revela si hay correlación entre radiación solar y nivel de lux: a más radiación, ¿el sistema consume menos porque hay más luz natural?
- Replicar directamente el scatter del dashboard de DimClima

**Gráfico de barras — Consumo promedio por condición climática:**
- Una barra por condición (despejado / nublado / lluvia / tormenta)
- Muestra si los días nublados tienen mayor consumo porque las luminarias compensan la falta de luz natural

**Tabla de resumen climático:**
- Columnas: Condición | kWh Promedio | Lux Promedio | Temperatura Promedio | % Anomalías

---

### Página 7: Estado de Sensores (`sensor.html`)

**Equivale a:** Página 7 del dashboard (DimSensor — Confiabilidad del sistema).

**Pregunta que responde:** ¿Los sensores son confiables para tomar decisiones de política pública?

**Estructura:**

**Mapa de burbujas (parte izquierda):**
- A diferencia de los mapas choropleth anteriores, este usa las coordenadas exactas de cada sensor (latitud, longitud de `DimSensor`)
- Cada sensor es una burbuja; el radio es proporcional al total de anomalías que generó
- Color de la burbuja: verde (activo y sin alertas), amarillo (activo con anomalías), rojo (inactivo o con muchas anomalías)
- Esto permite ver si los sensores problemáticos están concentrados geográficamente en las mismas zonas que aparecen en rojo en el mapa de consumo (ese es el hallazgo narrativo de cierre del dashboard)

**KPIs de estado del inventario (tarjetas en la parte superior):**
- Total de sensores activos vs inactivos
- Sensores que superan X días sin mantenimiento (campo `dias_sin_mantenimiento`)
- Sensor con más anomalías (nombre o ID)
- Porcentaje de lecturas válidas (1 − % anomalías del total)

**Tabla de sensores (parte derecha o inferior):**
- Columnas: ID Sensor | Zona | Tipo | Días sin Mant. | Anomalías | Estado
- Ordenable por días sin mantenimiento (permite identificar cuáles necesitan intervención urgente)
- Formato condicional en "Días sin Mant.": verde si < 30, amarillo si 30–90, rojo si > 90

**Por qué esta página es importante para la narrativa:** cierra el argumento del dashboard. Las zonas que aparecen en rojo en el mapa de consumo, en rojo en el mapa de incumplimiento y con burbujas rojas en el mapa de sensores son las mismas. La convergencia de tres evidencias sobre la misma geografía es el argumento para recomendar intervención prioritaria.

---

### Página 8: Modelo ML (`modelo_ml.html`)

**No tiene equivalente directo en el dashboard.** Es la sección adicional requerida.

**Pregunta que responde:** ¿Puede un modelo predecir el nivel de lux óptimo y si una luminaria debería estar encendida?

**Nota técnica:** esta página NO consulta la base de datos. Carga los JSONs del Integrante 4.

**Estructura:**

**Introducción al modelo (texto con diseño de tarjeta):**
- Qué predice cada modelo: el regresor predice el nivel de lux óptimo dados hora, zona y clima; el clasificador predice si la luminaria debería estar encendida
- Por qué Random Forest: maneja bien datos mixtos (numéricos y categóricos), robusto con ruido, interpretable por importancia de features
- Redactado de forma accesible, no para un data scientist sino para un evaluador que entiende el contexto del proyecto

**4 tarjetas de métricas:**
- R² del regresor (qué tan bien predice el lux óptimo; esperable > 0.80)
- MAE del regresor (error promedio en luxes)
- Accuracy del clasificador (% de predicciones de encendido/apagado correctas)
- F1-Score del clasificador (balance entre precisión y recall)

**Gráfico de barras — Importancia de features:**
- Barras horizontales, una por variable de entrada al modelo
- La más importante al tope (se espera que `radiacion_solar_wm2` y `hora` lideren)
- Replicar el visual de importancia de features del dashboard y del análisis del Integrante 4

**Gráfico de línea — Predicciones correctas por hora del día:**
- Eje X: horas 0–23
- Eje Y: porcentaje de predicciones correctas del clasificador en esa hora
- Muestra en qué horas el modelo es más o menos preciso

**Explorador interactivo del modelo:**
- 3 controles: dropdown de hora (0–23), dropdown de zona, dropdown de condición climática
- Al cambiar cualquier control, muestra la predicción de lux óptimo para esa combinación
- Los datos vienen del JSON `tabla_lookup` del archivo `resultados_modelo.json`
- El modelo no corre en el navegador; solo lee una tabla pre-calculada
- Mostrar también si el modelo predice que la luminaria debería estar encendida (clasificador) para esa combinación

---

## 7. Sistema de Filtros y Cómo Replicar los de Power BI

Los segmentadores de Power BI son el elemento de interactividad más valorado por el profesor. Replicarlos en la web requiere entender cómo funcionan.

### 7.1 Qué hace un filtro en el sistema web

Cuando el usuario cambia un filtro:
1. El JavaScript recoge los valores actuales de todos los selectores de la página
2. Construye una URL con parámetros: `/api/zonas?clima=Nublado&periodo=nocturno`
3. Hace un `fetch()` a ese endpoint de Flask
4. Flask ejecuta la consulta SQL con esos parámetros en el `WHERE`
5. La respuesta JSON actualiza los gráficos y tablas de la página
6. Los mapas se recolorean con los nuevos valores

Esto es exactamente lo que hace Power BI cuando se selecciona un segmentador: filtra los datos antes de calcular los visuales.

### 7.2 Filtros presentes en cada página

| Página | Filtros disponibles | Equivale al segmentador de Power BI |
|---|---|---|
| Dashboard General | Zona, Clima, Período horario | Segmentadores globales de la Página General |
| Zonas | Clima, Métrica del mapa | Segmentador de clima + toggle de métrica |
| Tiempo | Zona, Año, Tipo de día | Segmentadores de DimTiempo |
| Tecnología | Ninguno (datos globales) | Sin segmentadores en DimLuminaria |
| Políticas | Rango de fechas | Segmentador de fechas de DimPolitica |
| Clima | Ninguno (toda la variedad) | Sin segmentadores en DimClima |
| Sensores | Zona, Estado del sensor | Segmentadores de DimSensor |
| Modelo ML | Hora, Zona, Clima (explorador) | Los 3 controles del explorador interactivo |

### 7.3 Comportamiento del filtro de zona y su impacto cruzado

En Power BI, seleccionar una zona en un visual filtra todos los demás visuales de la página. En la web, esto se replica así:

- Cuando el usuario selecciona una zona en el dropdown de la página de **Análisis General**, los KPIs, la serie temporal y el gráfico de top 10 se actualizan para mostrar solo esa zona
- El mapa choropleth NO cambia (sigue mostrando todas las zonas) pero resalta la zona seleccionada con un borde más grueso
- Al hacer clic en una localidad en el mapa choropleth, el dropdown de zona se actualiza automáticamente y dispara la recarga de todos los demás visuales

Este comportamiento bidireccional (filtro → mapa y mapa → filtro) es el equivalente web del filtro cruzado de Power BI.

### 7.4 Indicador visual de que hay filtros activos

Cuando hay filtros aplicados, mostrar un banner visible justo debajo de la barra de filtros:

```
"Viendo datos para: [Bosa × Nublado × Nocturno]   ✕ Limpiar filtros"
```

Este banner cumple dos funciones: indica al usuario que está viendo datos filtrados (no el global), y ofrece un acceso rápido para limpiar. En Power BI, el segmentador seleccionado visualmente está destacado; en la web, este banner cumple el mismo rol informativo.

---

## 8. Sistema de Diseño Visual — Coherencia con el Dashboard

El dashboard de Power BI ya define el sistema de diseño. La web debe ser visualmente coherente con él.

### 8.1 Paleta de colores (exactamente la del dashboard)

```css
/* Variables CSS — copiar exactamente en styles.css */

:root {
  /* Paleta institucional */
  --azul-institucional:   #1B2A4A;   /* Fondos oscuros, headers, texto principal */
  --azul-medio:           #2E5C8A;   /* Elementos activos, bordes, íconos */
  --azul-claro:           #5B9BD5;   /* Acentos, líneas secundarias */
  --azul-palido:          #D6E8F7;   /* Fondos de tarjeta, áreas de gráfica */

  /* Paleta semántica — MISMAS reglas que el dashboard */
  --verde-eficiencia:     #1A7A4A;   /* Siempre: tecnología LED, buenos valores */
  --amarillo-alerta:      #F4A20D;   /* Siempre: alertas, transiciones */
  --rojo-critico:         #C0392B;   /* Siempre: anomalías, alto consumo, incumplimiento */
  --blanco:               #FFFFFF;

  /* Colores por tecnología de lámpara */
  --color-led:            #1A7A4A;
  --color-sodio:          #E67E22;
  --color-haluro:         #8E44AD;
  --color-mercurio:       #C0392B;

  /* Colores por condición climática */
  --color-despejado:      #F4A20D;
  --color-nublado:        #7F8C8D;
  --color-lluvia:         #2980B9;
  --color-tormenta:       #1B2A4A;

  /* Espaciado y bordes */
  --radio-card:           8px;
  --sombra-card:          0 2px 8px rgba(27, 42, 74, 0.10);
  --sombra-hover:         0 4px 16px rgba(27, 42, 74, 0.18);
}
```

### 8.2 Tipografía

- Fuente: Segoe UI (la misma del dashboard de Power BI)
- Si no está disponible en el sistema del usuario: `system-ui, -apple-system, sans-serif`
- Títulos de página: 1.5rem, peso 700, color `--azul-institucional`
- Subtítulos de sección: 1.1rem, peso 600
- Texto de tarjetas KPI: 2.2rem para el número, 0.8rem para la etiqueta

### 8.3 Estructura de las tarjetas KPI

Las tarjetas KPI replican exactamente el estilo del visual "Tarjeta (nueva)" de Power BI:
- Fondo blanco
- Borde izquierdo de 4px del color institucional (acento de identificación)
- Número grande con color `--azul-institucional`
- Etiqueta en mayúsculas pequeñas, color gris
- Variación (▲▼) coloreada con verde (baja) o rojo (sube) para kWh y anomalías; invertido para ahorro

### 8.4 Navbar

- Fondo: `--azul-institucional`
- Texto de los links: blanco
- Link activo (página actual): fondo `--azul-medio`, texto blanco
- Logo o ícono del proyecto a la izquierda
- Los 8 links de las páginas analíticas más el inicio
- Bootstrap 5 `navbar` con `navbar-dark bg-dark` reemplazando el color por la variable CSS

### 8.5 Mapeo Power BI → librerías web

| Visual en Power BI | Implementación en la web | Librería |
|---|---|---|
| Mapa de formas (Shape Map) | Mapa choropleth | Leaflet.js + GeoJSON |
| Gráfico de líneas | LineChart con área sombreada | Chart.js `line` + `fill: true` |
| Gráfico de barras horizontal | HorizontalBar | Chart.js `bar` con `indexAxis: 'y'` |
| Gráfico de barras agrupadas | GroupedBar | Chart.js `bar` con múltiples datasets |
| Heatmap (Matriz con formato condicional) | Heatmap | Chart.js matrix plugin |
| Medidor (Gauge) | Semicírculo doughnut | Chart.js `doughnut` con `circumference: 180` |
| Gráfico de dispersión (Scatter) | Scatter | Chart.js `scatter` |
| Tarjeta KPI | Div con CSS | HTML + CSS puro (sin librería) |
| Tabla ordenable | Tabla HTML | JavaScript nativo (sort por columna) |
| Mapa de burbujas | CircleMarker en mapa | Leaflet.js `circleMarker` |
| Segmentador | Select / multi-select | HTML `<select>` + JavaScript |

---

## 9. Integración con los JSONs del Modelo ML

Los JSONs que entrega el Integrante 4 se copian directamente a `/static/data/`. El navegador los carga con `fetch()` al entrar a `modelo_ml.html`.

### 9.1 Estructura esperada de cada JSON

**`resumen_zonas.json`** — para el mapa y la tabla de zonas:
```
Array de objetos, uno por localidad:
  zona_id, zona_nombre, kwh_total, lux_promedio, lux_optimo_promedio,
  ahorro_kwh_estimado, anomalias, costo_cop_total, pct_cumplimiento_horario
```
Si el Integrante 4 entrega este JSON antes del día 3, el mapa puede mostrar la columna `lux_optimo_promedio` adicional.

**`consumo_horario.json`** — para el gráfico de línea de la vista general y el heatmap:
```
Array de 24 objetos (o 168 para heatmap):
  hora, kwh_promedio, lux_promedio, lux_optimo_promedio, pct_encendidas
  (+ nombre_dia si incluye el desglose por día de semana)
```

**`resultados_modelo.json`** — para la página del modelo ML:
```
Objeto raíz con:
  regresor: { R2, MAE, RMSE }
  clasificador: { accuracy, f1_score, precision, recall }
  importancia_features: [ { feature, importancia }, ... ] (ordenado de mayor a menor)
  predicciones_por_hora: [ { hora, pct_correctas }, ... ]
  tabla_lookup: [ { hora, zona_id, clima_id, lux_optimo_predicho, estado_predicho }, ... ]
  resumen_impacto: { kwh_desperdiciados, ahorro_potencial_kwh, ahorro_potencial_cop }
```

### 9.2 Qué hacer si el Integrante 4 no ha entregado los JSONs

Crear datos de ejemplo con exactamente la misma estructura. Los números serán inventados pero la estructura será correcta. Cuando lleguen los JSONs reales, reemplazar los archivos de ejemplo y el sistema web se actualiza automáticamente sin cambiar nada de código.

### 9.3 Coordinación clave con el Integrante 4

Acordar el día 1 (antes de que cualquiera empiece a codear):
- Los nombres exactos de los campos en cada JSON
- El formato de `zona_id` (¿número entero 1–20 o string?)
- El formato de `clima_id` en la tabla lookup (¿número o string del nombre de la condición?)
- El rango de `hora` (¿0–23 o 1–24?)

Si estos acuerdos no se hacen el día 1, el día 4 habrá que reescribir el código de visualización porque los nombres de campos no coinciden.

---

## 10. Plan de Ejecución por Días

Dado el tiempo limitado, el plan prioriza que al final de cada día haya algo funcional que mostrar.

### Día 1 — Base del sistema y página de inicio

**Objetivo del día:** Flask corriendo, conexión a SQL Server probada, `index.html` completamente terminado.

**Tareas en orden:**

Primero: instalar Flask y pyodbc (`pip install flask pyodbc`), crear `app.py` con la configuración mínima y verificar que el servidor Flask arranca. Probar la conexión a SQL Server con una consulta simple de `SELECT COUNT(*) FROM FactConsumoIluminacion`. Si la conexión falla, resolver antes de avanzar porque todo lo demás depende de esto.

Segundo: crear las vistas SQL `vw_kpis_generales` y `vw_consumo_por_zona` en SQL Server. Estas dos vistas son las que más páginas alimentan y son las más urgentes.

Tercero: crear `base.html` con el navbar, los links de CSS y la estructura común. Crear `index.html` completo usando contenido estático (texto del planteamiento, las 4 tarjetas de escala del sistema, las secciones de tecnologías y equipo). Esta página no consulta la BD y puede terminarse completamente en pocas horas.

Cuarto: crear datos de ejemplo en `/static/data/resumen_zonas.json` y `consumo_horario.json` para no bloquear el trabajo del día 2 mientras las vistas SQL están listas.

**Señal de éxito:** `http://localhost:5000` muestra la portada completa y `http://localhost:5000/api/kpis` devuelve un JSON con los KPIs reales desde el DW.

---

### Día 2 — Dashboard general con KPIs y gráficos principales

**Objetivo del día:** `dashboard.html` funcional con filtros, KPIs reales y los dos gráficos principales.

**Tareas en orden:**

Primero: crear las vistas SQL `vw_serie_temporal_mensual` y el endpoint `GET /api/serie-temporal`.

Segundo: construir `dashboard.html` con la barra de filtros en la parte superior (los tres selectores con Bootstrap).

Tercero: implementar las 4 tarjetas KPI que se alimentan de `/api/kpis`. Verificar que al cambiar el filtro de zona, las tarjetas muestran los valores de esa zona.

Cuarto: implementar el gráfico de línea de la serie temporal con Chart.js. Implementar el gráfico de barras horizontal del top 10 de zonas.

**No empezar el mapa todavía.** El mapa requiere el GeoJSON y es más complejo. Los dos gráficos de este día ya hacen la página funcional e interactiva.

**Señal de éxito:** seleccionar "Bosa" en el filtro de zona y los 4 KPIs y ambos gráficos se actualizan mostrando solo datos de Bosa.

---

### Día 3 — Mapa de Bogotá y páginas de zonas y tiempo

**Objetivo del día:** `zonas.html` con el mapa choropleth funcional y `tiempo.html` con el heatmap.

**Tareas en orden:**

Primero: obtener el GeoJSON de localidades de Bogotá (coordinar con el Integrante 1 para compartir el mismo archivo; buscarlo en `datosabiertos.bogota.gov.co` o en GitHub con "bogota localidades geojson"). Guardarlo en `/static/data/bogota_localidades.geojson`.

Segundo: construir el mapa choropleth en `zonas.html` con Leaflet.js. Conectar los datos de coloreado al endpoint `/api/zonas`. Verificar que el popup al hacer clic en cada localidad muestra los datos correctos.

Tercero: crear la vista SQL `vw_consumo_por_hora` con el desglose hora × día de semana. Crear el endpoint `/api/heatmap`.

Cuarto: construir `tiempo.html` con el heatmap como visual principal. El heatmap requiere el plugin Chart.js matrix o una implementación HTML con CSS grid; elegir la opción con la que tengas más familiaridad.

Quinto: si el Integrante 4 ya entregó los JSONs, reemplazar los de ejemplo en `/static/data/`.

**Señal de éxito:** el mapa muestra las 20 localidades coloreadas con escala verde-rojo. Al hacer clic en Chapinero, el popup muestra los KPIs de esa zona. El heatmap muestra los patrones hora × día.

---

### Día 4 — Páginas de tecnología, política y modelo ML

**Objetivo del día:** `tecnologia.html`, `politica.html` y `modelo_ml.html` funcionales.

**Tareas en orden:**

Primero: crear las vistas SQL `vw_cumplimiento_politicas` y `vw_consumo_por_tecnologia`. Crear los endpoints correspondientes.

Segundo: construir `tecnologia.html` con el gráfico de barras comparativo y el scatter de eficiencia. El gauge de modernización LED puede implementarse como una versión simplificada (doughnut chart en Chart.js).

Tercero: construir `politica.html` con los dos gauges de cumplimiento y la tabla de brechas. El mapa de cumplimiento puede reutilizar el componente Leaflet de `zonas.html` cambiando la métrica.

Cuarto: construir `modelo_ml.html` leyendo `resultados_modelo.json`. Si el Integrante 4 aún no entregó el JSON, usar el de ejemplo. Implementar las 4 tarjetas de métricas, el gráfico de importancia de features y el explorador interactivo.

**Señal de éxito:** las tres páginas cargan y muestran datos. Los gauges de cumplimiento muestran valores coherentes con el dashboard de Power BI.

---

### Día 5 — Páginas de clima y sensores, pulido y datos reales

**Objetivo del día:** sistema completo con datos reales, diseño coherente con el dashboard.

**Tareas en orden:**

Primero: construir `clima.html` con el scatter de correlación (es relativamente rápido con los datos de `vw_consumo_por_clima`). Construir `sensor.html` con el mapa de burbujas y la tabla.

Segundo: reemplazar todos los datos de ejemplo por los JSONs reales del Integrante 4. Verificar que los KPIs de la web son coherentes con los del dashboard de Power BI (deben coincidir aproximadamente, no necesariamente al decimal).

Tercero: revisar la consistencia visual: mismo navbar en todas las páginas, misma paleta de colores en todos los gráficos, mismas fuentes. Un dashboard con inconsistencias visuales comunica falta de atención al detalle.

Cuarto: probar la navegación completa: inicio → dashboard → zonas → tiempo → tecnología → política → clima → sensores → modelo ML → inicio. Cada enlace debe funcionar. Todos los filtros de cada página deben responder.

**Señal de éxito:** la URL `http://localhost:5000` muestra un sistema web completo con 9 páginas funcionales, filtros interactivos y datos reales del DW.

---

## 11. Dependencias Críticas con Otros Integrantes

| Día | Qué necesitas | De quién | Qué se bloquea si no llega |
|---|---|---|---|
| **Día 1** | Acceso confirmado al DW en SQL Server | Integrante 1 | La conexión Flask no puede probarse |
| **Día 1** | Estructura acordada de los JSONs | Integrante 4 | Código de visualización incompatible con datos reales |
| **Día 3** | GeoJSON de localidades de Bogotá | Integrante 1 (o conseguirlo tú) | El mapa choropleth no puede construirse |
| **Día 3** | `resumen_zonas.json` y `consumo_horario.json` | Integrante 4 | Datos de ejemplo hasta el día 5 (aceptable) |
| **Día 4** | `resultados_modelo.json` completo | Integrante 4 | El explorador interactivo de ML no puede terminarse |
| **Día 5** | Verificación cruzada de KPIs | Integrante 1 | Los números de la web pueden no coincidir con el dashboard |

### Qué hacer si los JSONs del Integrante 4 no llegan a tiempo

No detener el desarrollo. Crear y usar datos de ejemplo con la estructura acordada. La web funciona con datos de ejemplo y los reemplazos son mecánicos: copiar el JSON real en `/static/data/` y el sistema se actualiza. El código de visualización no cambia.

### Cómo compartir la web con el equipo para revisión

Durante el desarrollo local, compartir la URL `http://[tu-IP-local]:5000` con el equipo en la misma red. En Flask, el servidor por defecto solo acepta conexiones desde `localhost`. Para aceptar desde la red local, cambiar el `app.run()` a `app.run(host='0.0.0.0', port=5000)`.

---

*Sistema de Monitorización de Iluminación Inteligente — Bogotá D.C.*
*Guía de implementación — Integrante 2 · Sistema Web*
*Flask + pyodbc + Bootstrap 5 + Chart.js + Leaflet.js · ODS 7 · ODS 11 · ODS 13*
