# Guía de Implementación v3 — Sistema Web Estático
## GitHub Pages + JSON · Integrantes 1 y 2 · División de trabajo en paralelo
### Sistema de Monitorización de Iluminación Inteligente · Bogotá D.C.

---

## Índice

1. [Justificación de la arquitectura](#1-justificación-de-la-arquitectura)
2. [Generación de JSONs — Sección crítica con alternativas](#2-generación-de-jsons--sección-crítica-con-alternativas)
3. [Configuración base del repositorio público](#3-configuración-base-del-repositorio-público)
4. [Integrante 1 — Datos + Colaboración](#4-integrante-1--datos--colaboración)
5. [Integrante 2 — Frontend + Deploy](#5-integrante-2--frontend--deploy)
6. [Coordinación y puntos de sincronización](#6-coordinación-y-puntos-de-sincronización)

---

## 1. Justificación de la Arquitectura

### Por qué se abandona Flask con SQL Server en tiempo real

El problema de los 5 minutos no era un problema de Flask ni de las vistas SQL mal escritas. Era un problema de **indexación y volumetría**: SQL Server sin índices compuestos sobre `FactConsumoIluminacion` tiene que hacer un full scan de 1 millón de filas cada vez que se ejecuta cualquier GROUP BY con JOINs a las dimensiones. Eso ocurría tanto desde SSMS como desde Flask, y ocurriría exactamente igual en producción.

La solución no es optimizar la consulta para que tarde 30 segundos en lugar de 5 minutos. La solución es **cortar el vínculo entre el servidor web y SQL Server por completo**. Los datos del DW son un snapshot analítico: no cambian mientras el proyecto existe. No tiene ningún sentido recalcularlos en cada petición del usuario.

### La arquitectura elegida y por qué es sólida

```
SQL Server DW (local)
        │
        │  Script Python — una sola vez
        ▼
   8 archivos JSON
   (resultados pre-calculados)
        │
        │  git push
        ▼
  GitHub (repo público)
        │
        │  GitHub Pages CDN
        ▼
  Navegador del usuario
  HTML + JS + Chart.js + Leaflet.js
  fetch() → JSON → renderiza
```

**Sin servidor en tiempo de ejecución.** El navegador carga el HTML desde GitHub Pages y hace `fetch()` a los archivos JSON en el mismo repositorio. No hay Flask, no hay base de datos, no hay proceso backend que pueda caerse, dormirse ni tardar en responder.

**Por qué esto satisface los requisitos del profesor.** El requisito es "dashboard publicado en sitio web con navegación funcional, acceso a visualizaciones y correcta interacción con filtros". GitHub Pages cumple todo eso: URL pública, permanente, accesible desde cualquier dispositivo. Los filtros interactivos funcionan sobre los datos cargados en memoria del navegador.

**Sobre el Render y el cold start.** Render en plan gratuito pausa las instancias después de 15 minutos sin tráfico y las despierta con 30–60 segundos de espera. En una demo en vivo, ese tiempo de espera frente al profesor es un riesgo real e innecesario. Con la arquitectura estática, Render solo entra como opción para deploy del frontend HTML, no como servidor de datos, lo que hace que el cold start sea irrelevante.

**Por qué un repositorio público separado.** El repositorio privado del proyecto no puede activar GitHub Pages en plan gratuito. En lugar de pagar o comprometer el repositorio principal, se crea un repositorio público nuevo exclusivamente para el sistema web. El código fuente sensible (scripts de ETL, credenciales, notebooks de ML) permanece en el repo privado.

### Qué contienen exactamente los archivos JSON

Los JSON **no contienen los datos crudos de la fact table**. Contienen los resultados ya calculados de las 8 consultas de agregación. Cada archivo es el equivalente a ejecutar una vista SQL completa y guardar su resultado:

| Archivo JSON | Filas | Contenido | Tamaño estimado |
|---|---|---|---|
| `kpis_generales.json` | 1 | KPIs globales del sistema | ~1 KB |
| `consumo_por_zona.json` | 20 | Una fila por localidad de Bogotá | ~8 KB |
| `consumo_por_hora.json` | 168 | 24 horas × 7 días de semana | ~20 KB |
| `consumo_por_tecnologia.json` | 4–6 | Una fila por tipo de lámpara | ~3 KB |
| `cumplimiento_politicas.json` | 21 | 20 zonas + fila de totales globales | ~10 KB |
| `consumo_por_clima.json` | 30–50 | Una fila por condición × rango de nubosidad | ~8 KB |
| `estado_sensores.json` | ~500 | Una fila por sensor | ~50 KB |
| `serie_temporal.json` | 24–48 | Una fila por año × mes | ~12 KB |

**Total: ~112 KB.** Caben en cualquier repositorio, se cargan en el navegador en menos de 200 ms con conexión normal, y GitHub Pages los sirve desde CDN con latencia mínima.

---

## 2. Generación de JSONs — Sección Crítica con Alternativas

Esta es la parte más importante de toda la guía. Si los JSONs no se generan correctamente, el resto del sistema no tiene datos. Se presentan tres métodos en orden de preferencia, con criterios claros para elegir cuál usar según las condiciones del momento.

### Sobre la capacidad de Python para manejar 1 millón de filas

La pregunta es válida. Python **sí puede** manejar este volumen, pero la forma en que se hace importa mucho.

El riesgo real no es Python en sí: es hacer un join mal planteado que cree un producto cartesiano accidental. Si se hace un merge de un DataFrame de 1 millón de filas contra sí mismo o contra una dimensión por una columna que no es única, el resultado puede ser 100 millones de filas y colapsar la RAM. El cuidado necesario es siempre verificar que los merges son muchos-a-uno (fact → dimensión), nunca muchos-a-muchos.

Sin embargo, para este proyecto **el enfoque correcto no es cargar 1 millón de filas en Python y hacer los joins ahí**. El enfoque correcto es dejar que SQL Server haga el join y la agregación (para lo que está optimizado), y que Python solo reciba el resultado pequeño y lo guarde como JSON. La diferencia es:

- **Mal enfoque**: `pd.read_sql("SELECT * FROM FactConsumoIluminacion")` → 1 millón de filas en RAM → merge con dimensiones en pandas → groupby → JSON. Lento, pesado, riesgoso.
- **Enfoque correcto**: `pd.read_sql("SELECT zona_id, SUM(consumo_kwh) FROM Fact GROUP BY zona_id")` → 20 filas en RAM → JSON. El join y la agregación ocurren en SQL Server.

La consulta que Python envía ya hace todo el trabajo analítico en SQL. Python solo recibe 20 filas, no 1 millón. Eso es lo que hace que el script sea seguro y que pandas no tenga riesgo de bucle ni cuello de botella.

---

### Método A — Consultas directas con pyodbc (recomendado si la conexión funciona)

**Cuándo usar:** cuando Python puede conectarse a SQL Server sin problemas de driver y las consultas agregadas simples responden en tiempo razonable (no las vistas complejas, sino GROUP BY directos).

**Cómo funciona:** el script abre una conexión a SQL Server, ejecuta una consulta GROUP BY simple (no llama a las vistas del archivo anterior, sino queries directas más simples sin CTEs ni UNION ALL), recibe el resultado pequeño en un DataFrame de pandas y lo guarda como JSON.

**La clave de rendimiento aquí:** las consultas deben ser más simples que las vistas SQL del archivo anterior. Cada query debe:
- Tener un solo GROUP BY sin subconsultas anidadas
- Usar JOINs solo con las dimensiones estrictamente necesarias para esa consulta
- No usar CTEs para calcular totales globales dentro del mismo query (eso se hace después con una segunda query separada)

**Tiempo estimado de ejecución:** con las consultas simplificadas, entre 3 y 15 minutos por archivo dependiendo del hardware. El Método A tiene el riesgo de que algunas consultas sigan tardando si el DW no tiene los índices correctos.

**Señal de que está funcionando bien:** la primera consulta (kpis generales) devuelve resultado en menos de 3 minutos. Si tarda más, cambiar al Método B.

**Señal de que hay un problema:** el script se congela sin devolver resultado después de 10 minutos en una sola consulta. Pasar directamente al Método B.

---

### Método B — Exportar la fact table primero, agregar con DuckDB (recomendado si Método A es lento)

**Cuándo usar:** cuando las consultas directas a SQL Server siguen tardando demasiado, o cuando la conexión pyodbc tiene problemas de driver, o cuando se quiere independizar completamente el proceso de SQL Server.

**Por qué DuckDB y no pandas para este paso:** DuckDB es un motor de base de datos analítica embebido en Python, diseñado específicamente para hacer GROUP BY y JOINs sobre archivos CSV o Parquet de forma ultrarrápida. No es pandas con un loop: es un motor SQL completo que aprovecha procesamiento vectorizado y multihilo. Sobre un CSV de 1 millón de filas, DuckDB ejecuta un GROUP BY con JOIN en 2–8 segundos. Pandas con groupby tarda 15–30 segundos en el mismo escenario, y si los joins están mal hechos puede explotar en memoria.

**Cómo funciona en dos pasos:**

**Paso B1 — Exportar desde SSMS (sin Python):** desde SSMS, ejecutar manualmente `SELECT * FROM FactConsumoIluminacion` y exportar el resultado como CSV plano usando el asistente de exportación de SSMS (clic derecho en la base de datos → Tasks → Export Data, o desde los resultados de la consulta → Save Results As). Este paso tarda 5–15 minutos pero solo involucra a SSMS, no a Python ni a conexiones programáticas. Hacer lo mismo para cada tabla de dimensión que se necesite (DimZona, DimTiempo, DimClima, DimPolitica, DimLuminaria, DimSensor). Las dimensiones son pequeñas y exportan en segundos.

**Paso B2 — Agregar con DuckDB en Python:** el script Python carga el CSV de la fact table con DuckDB (no con pandas) y ejecuta queries SQL estándar sobre él. DuckDB puede consultar un CSV directamente sin importarlo a ninguna base de datos. Las queries son idénticas a las del archivo de vistas SQL, pero se ejecutan sobre el archivo CSV local en lugar de SQL Server. Para cada una de las 8 agregaciones, DuckDB devuelve un DataFrame que se guarda como JSON.

**Ventaja clave del Método B:** una vez que tienes los CSV exportados desde SSMS, el proceso de generación de JSONs es completamente independiente de SQL Server. No necesitas que el servidor esté corriendo, no necesitas drivers ODBC, no hay problemas de conexión.

**Espacio en disco:** el CSV de 1 millón de filas de la fact table pesa aproximadamente 400–700 MB. Asegúrate de tener al menos 2 GB libres.

---

### Método C — Exportar cada resultado directamente desde SSMS (fallback manual)

**Cuándo usar:** cuando Python no puede conectarse a SQL Server por ningún método, cuando hay restricciones en el entorno que impiden instalar librerías, o cuando el tiempo es crítico y se necesita tener al menos algunos JSONs funcionando cuanto antes.

**Cómo funciona:** desde SSMS, ejecutar manualmente cada una de las 8 consultas de agregación. Cuando el resultado aparece en el panel inferior de SSMS, hacer clic derecho sobre los resultados → Save Results As → guardarlo como CSV. Luego, un script Python mínimo (que solo usa pandas, sin pyodbc) lee cada CSV y lo convierte a JSON con el formato correcto.

**Tiempo estimado:** 10–20 minutos por consulta en SSMS (las mismas consultas lentas), más 5 minutos de conversión Python por archivo. Es el método más lento pero el más seguro porque no depende de ninguna conexión programática.

**Este método es el seguro de vida.** Si los Métodos A y B fallan, el Método C siempre funciona. El resultado final es idéntico: 8 archivos JSON con los datos correctos.

---

### Tabla de decisión para elegir el método

```
¿Python puede conectarse a SQL Server con pyodbc?
│
├── NO → Método C (exportar desde SSMS manualmente)
│         Si hay tiempo después, intentar instalar el driver ODBC correcto
│
└── SÍ → ¿Las consultas GROUP BY simples tardan menos de 5 min?
          │
          ├── SÍ → Método A (script directo con pyodbc)
          │
          └── NO → ¿Puedes exportar el CSV de la fact table desde SSMS?
                    │
                    ├── SÍ → Método B (DuckDB sobre CSV local)
                    │
                    └── NO → Método C (exportar cada resultado desde SSMS)
```

---

### Estructura y formato de cada JSON

El formato de cada JSON debe ser consistente para que el JavaScript del frontend pueda leerlos sin adaptación. Todos usan el formato de array de objetos: cada elemento del array es una fila, y las claves del objeto son los nombres de las columnas.

**`kpis_generales.json`** — objeto único (no array) con los totales globales del sistema. Contiene: total_kwh, costo_total_cop, total_anomalias, ahorro_estimado_kwh, pct_luminarias_encendidas, sensores_activos, zonas_monitoreadas, lux_promedio_global. Es el único JSON que no es un array porque siempre es exactamente un registro.

**`consumo_por_zona.json`** — array de 20 objetos. Cada objeto tiene: zona_id, nombre_zona, latitud, longitud, kwh_total, costo_cop_total, lux_promedio, total_anomalias, kwh_por_habitante, kwh_por_km2, pct_cumplimiento_horario, ahorro_kwh_estimado. La latitud y longitud se incluyen aquí para que el mapa de Leaflet no necesite un archivo separado de coordenadas.

**`consumo_por_hora.json`** — array de 168 objetos con: hora (0–23), dia_semana (1–7), nombre_dia (texto en español), es_horario_nocturno (booleano), kwh_promedio, lux_promedio, pct_encendidas. Los 168 objetos son 24 horas × 7 días. Para el gráfico de línea simple el JavaScript agrupa por hora promediando los 7 días.

**`consumo_por_tecnologia.json`** — array de 4–6 objetos con: tipo_lampara, kwh_total, kwh_promedio_por_luminaria, lux_promedio, eficiencia_lux_kwh, pct_participacion, total_anomalias, total_luminarias.

**`cumplimiento_politicas.json`** — objeto con dos claves: `globales` (un objeto con los totales del sistema: pct_cumplimiento_horario global, pct_cumplimiento_lux global, kwh_desperdiciados total) y `por_zona` (array de 20 objetos con: zona_id, nombre_zona, latitud, longitud, pct_cumplimiento_horario, pct_cumplimiento_lux, kwh_desperdiciados, costo_desperdicio_cop).

**`consumo_por_clima.json`** — array de objetos con: condicion_clima, rango_cobertura_nubosa, radiacion_solar_promedio, temperatura_promedio, kwh_promedio, lux_promedio, pct_encendidas, total_registros. Estos son los puntos del scatter de correlación.

**`estado_sensores.json`** — array de ~500 objetos con: sensor_id, nombre_zona, latitud, longitud, tipo_sensor, modelo, estado_sensor, dias_sin_mantenimiento, total_anomalias, pct_anomalias, estado_criticidad (texto: NORMAL / ALERTA / CRITICO / INACTIVO).

**`serie_temporal.json`** — objeto con una clave por año (ej: `"2023"`, `"2024"`), cada una con un array de 12 objetos mensuales: mes, nombre_mes, kwh_total, costo_cop_total, total_anomalias, ahorro_kwh_estimado. Esta estructura facilita que Chart.js dibuje las dos líneas del comparativo interanual directamente.

---

### Verificación de los JSONs antes de seguir

Antes de subir los archivos a GitHub, verificar tres cosas para cada JSON:

Primero, que el número de objetos en el array es el esperado (20 para zonas, 168 para horas, etc.). Si hay más o menos, hay un problema en la consulta de agrupación.

Segundo, que ningún campo crítico tiene valores `null` en todos los registros. Campos como `kwh_total`, `lux_promedio` y `nombre_zona` deben tener valores en todos los objetos. Si están nulos, la consulta tiene un JOIN que no está encontrando coincidencias.

Tercero, que los totales son coherentes con el dashboard de Power BI. El `total_kwh` del archivo `kpis_generales.json` debe ser aproximadamente igual al KPI "Total kWh" del dashboard (puede diferir en decimales por redondeos, no en el orden de magnitud). Si difieren en más de un 10%, hay un problema en la consulta.

---

## 3. Configuración Base del Repositorio Público

Este paso lo hace cualquiera de los dos integrantes, idealmente el que tiene acceso más rápido a GitHub. Se hace una sola vez antes de que ambos empiecen a trabajar.

### Crear el repositorio

En GitHub → New Repository. Nombre sugerido: `iluminacion-bogota` o `smart-lighting-bogota`. Visibilidad: **Public** (obligatorio). Marcar "Add a README". Hacer clic en Create repository.

### Estructura de carpetas que debe existir desde el inicio

```
iluminacion-bogota/
│
├── index.html                    ← Portada del proyecto
├── dashboard.html                ← Vista general y KPIs
├── zonas.html                    ← Análisis geográfico por localidad
├── tiempo.html                   ← Patrones horarios y heatmap
├── tecnologia.html               ← Comparativo por tipo de lámpara
├── politica.html                 ← Cumplimiento de directrices
├── clima.html                    ← Correlación climática
├── sensores.html                 ← Estado del inventario de sensores
├── modelo_ml.html                ← Resultados del modelo de ML
│
├── css/
│   └── styles.css                ← Sistema de diseño visual
│
├── js/
│   ├── utils.js                  ← Funciones compartidas (fetch, formateo)
│   ├── dashboard.js
│   ├── zonas.js                  ← Lógica del mapa Leaflet
│   ├── tiempo.js                 ← Lógica del heatmap
│   ├── tecnologia.js
│   ├── politica.js
│   ├── clima.js
│   ├── sensores.js
│   └── modelo_ml.js
│
└── data/
    ├── kpis_generales.json       ← Generado por Integrante 1
    ├── consumo_por_zona.json     ← Generado por Integrante 1
    ├── consumo_por_hora.json     ← Generado por Integrante 1
    ├── consumo_por_tecnologia.json
    ├── cumplimiento_politicas.json
    ├── consumo_por_clima.json
    ├── estado_sensores.json
    ├── serie_temporal.json
    ├── bogota_localidades.geojson ← Compartido, coordinado entre ambos
    ├── resumen_zonas.json        ← Del Integrante 4 (ML)
    └── resultados_modelo.json    ← Del Integrante 4 (ML)
```

### Activar GitHub Pages

En el repositorio → Settings → Pages. En Source seleccionar "Deploy from a branch", branch `main`, carpeta `/` (root). Guardar. Esperar 1–2 minutos. La URL pública queda disponible en `https://[usuario].github.io/iluminacion-bogota/`.

### Dar acceso al otro integrante

Settings → Collaborators → Add people → agregar al otro integrante. Ambos deben hacer `git clone` del repositorio y configurar sus credenciales de Git localmente.

### Placeholder para desarrollo

Mientras el Integrante 1 genera los JSONs reales, el Integrante 2 necesita datos con los que trabajar desde el primer momento. El Integrante 1 debe generar y subir un único archivo placeholder en las primeras 2 horas: un `consumo_por_zona.json` de ejemplo con las 20 localidades reales de Bogotá pero con valores de métricas inventados. Esto le permite al Integrante 2 construir el mapa y las visualizaciones con datos que tienen la forma correcta, y reemplazarlos con los reales cuando estén listos.

---

## 4. Integrante 1 — Datos y Colaboración

### Fase 1: Generación y publicación de datos (Horas 1–4)

Esta fase es bloqueante para el proyecto completo. El Integrante 1 debe tener al menos los primeros 3 JSONs subidos antes de que pasen 4 horas, para no bloquear el trabajo del Integrante 2.

---

**Tarea 1.1 — Entorno de trabajo (30 minutos)**

Instalar las librerías necesarias para el método de exportación elegido. Para el Método A: `pyodbc` y `pandas`. Para el Método B: `duckdb` y `pandas` (no necesita pyodbc). Para el Método C: solo `pandas`.

Verificar que la conexión a SQL Server funciona con una consulta de prueba mínima: `SELECT COUNT(*) FROM FactConsumoIluminacion`. Si esto devuelve 1.000.000 (o el número correcto de registros) en menos de 5 segundos, el Método A es viable. Si tarda más de 30 segundos solo para contar, ir directamente al Método B.

---

**Tarea 1.2 — Exportar el GeoJSON de Bogotá (15 minutos, puede hacerse en paralelo)**

Obtener el GeoJSON de localidades de Bogotá. La fuente más confiable es buscar en GitHub con los términos `bogota localidades geojson`. El archivo que se necesita tiene los polígonos de las 20 localidades con sus nombres en un campo `properties.NOMBRE` o similar. Verificar que tiene exactamente 20 features (uno por localidad). Guardarlo como `data/bogota_localidades.geojson` y subirlo al repositorio inmediatamente para que el Integrante 2 pueda empezar con el mapa.

---

**Tarea 1.3 — Generar los primeros 3 JSONs prioritarios (Horas 1–3)**

El orden de prioridad está determinado por qué páginas del Integrante 2 quedan bloqueadas sin datos:

Primero: `consumo_por_zona.json`. Es el que alimenta el mapa choropleth que es el visual más impactante. Incluir la latitud y longitud de cada zona. Verificar que tiene exactamente 20 objetos.

Segundo: `kpis_generales.json`. Es el que alimenta las 4 tarjetas KPI de la vista general. Es una sola fila y la consulta más simple. Debería ser el más rápido de generar.

Tercero: `serie_temporal.json`. Alimenta el gráfico de línea del dashboard general. Estructurarlo con el objeto anidado por año descrito en la sección anterior.

**Subir estos 3 archivos a GitHub inmediatamente** cuando estén listos, sin esperar a tener los 8. Notificar al Integrante 2 por el canal de comunicación del equipo.

---

**Tarea 1.4 — Generar los 5 JSONs restantes (Horas 3–5)**

En orden de prioridad para el trabajo del Integrante 2:

`consumo_por_hora.json` → necesario para heatmap y gráfico temporal.
`cumplimiento_politicas.json` → necesario para gauges y mapa de políticas.
`consumo_por_tecnologia.json` → necesario para scatter de eficiencia.
`consumo_por_clima.json` → necesario para scatter climático.
`estado_sensores.json` → necesario para mapa de burbujas (el más grande, ~500 filas).

Subir cada archivo a GitHub tan pronto como esté listo. No esperar a tener los 5 para hacer el push.

---

**Tarea 1.5 — Verificación cruzada con Power BI (30 minutos)**

Comparar los valores de `kpis_generales.json` con los KPIs del dashboard de Power BI. Específicamente: Total kWh, Costo Total COP, Total Anomalías y Ahorro Estimado. Si hay diferencias superiores al 5%, identificar la causa (diferencia en el filtro de fechas, diferencia en cómo se manejan los NULLs en la consulta) y corregirla. Documentar cualquier diferencia justificada para poder explicarla si el profesor la nota.

---

### Fase 2: Colaboración con el frontend (Hora 5 en adelante)

Una vez que todos los JSONs están subidos y verificados, el Integrante 1 puede contribuir al frontend en las páginas que no estén siendo trabajadas simultáneamente por el Integrante 2.

---

**Tarea 1.6 — Construir `index.html` (portada)**

La portada es completamente estática: no necesita datos de los JSONs. Es el trabajo de frontend más seguro para el Integrante 1 porque no genera conflictos de merge con ninguna de las páginas analíticas que trabaja el Integrante 2.

La portada tiene 5 secciones. La primera es el hero con fondo del color institucional oscuro (`#1B2A4A`), nombre del proyecto en texto grande, subtítulo con Bogotá D.C. y el contexto académico, los 3 badges de ODS con sus colores oficiales (amarillo para ODS 7, naranja para ODS 11, verde para ODS 13) y un botón que navega a `dashboard.html`.

La segunda sección son 4 tarjetas estáticas con la escala del sistema: 500 sensores, 1.000.000 lecturas, 20 localidades, 2 años de datos. Son valores fijos del planteamiento.

La tercera sección describe el flujo del sistema en 4 pasos con íconos: captura de sensores → almacenamiento OLTP → ETL al Data Warehouse → análisis y visualización.

La cuarta sección muestra los logos o badges de las tecnologías usadas: SQL Server, Python, Flask, Power BI, scikit-learn.

La quinta sección muestra las tarjetas del equipo con nombre y rol de cada integrante.

---

**Tarea 1.7 — Construir `clima.html` y `sensores.html`**

Estas son dos páginas analíticas que puede tomar el Integrante 1 para que el Integrante 2 se concentre en las más complejas. Los detalles de qué debe contener cada página están en la sección del Integrante 2, que aplica igual para ambos.

`clima.html` tiene un scatter de correlación, un gráfico de barras por condición climática y una tabla de resumen. Los datos vienen de `consumo_por_clima.json`.

`sensores.html` tiene un mapa de burbujas con Leaflet, tarjetas KPI de inventario y una tabla con ordenamiento. Los datos vienen de `estado_sensores.json`.

---

**Tarea 1.8 — Testing y verificación final**

Antes de la demo, recorrer el sistema completo verificando que los números en la web son coherentes con los del dashboard de Power BI. Documentar en el README del repositorio las fuentes de datos, la fecha de exportación y cualquier diferencia conocida respecto al dashboard.

---

## 5. Integrante 2 — Frontend y Deploy

### Principio de trabajo del Integrante 2

Durante las primeras horas, mientras el Integrante 1 genera los JSONs, el Integrante 2 trabaja con datos placeholder que tienen la estructura correcta pero valores inventados. La regla es: **nunca detener el desarrollo por falta de datos reales**. Cuando lleguen los JSONs reales, reemplazar los placeholders es mecánico: el código no cambia.

---

### Fase 1: Infraestructura y páginas que no necesitan datos reales (Horas 1–3)

**Tarea 2.1 — Configuración del entorno local de Flask (30 minutos)**

Flask se usa únicamente para el desarrollo local. Permite abrir los archivos HTML con URLs normales (`http://localhost:5000/dashboard.html`) en lugar de rutas de archivo (`file:///C:/...`), lo cual es necesario porque el `fetch()` de JavaScript a los archivos JSON falla con rutas de archivo por restricciones de seguridad del navegador.

La configuración de Flask para desarrollo es mínima: un archivo `app.py` que sirve los archivos estáticos de la carpeta raíz del repositorio. Flask aquí actúa como un servidor de archivos estáticos, no como una API. Ninguna ruta de Flask hace lógica de negocio: solo sirve el HTML que el navegador pide.

Esta configuración de Flask no va a producción. En producción, GitHub Pages sirve directamente los archivos. Flask solo existe para que el desarrollo local funcione con `http://localhost:5000`.

---

**Tarea 2.2 — Sistema de diseño visual en `css/styles.css` (30 minutos)**

Antes de construir cualquier página, definir las variables CSS del sistema de diseño. Esto garantiza coherencia visual en todas las páginas sin repetir valores de color en cada archivo.

Las variables CSS deben incluir la paleta institucional del proyecto (que debe coincidir con la de Power BI): el azul oscuro `#1B2A4A` para headers y fondos, el azul medio `#2E5C8A` para elementos activos, el azul claro `#5B9BD5` para acentos. La paleta semántica: verde `#1A7A4A` siempre para eficiencia y tecnología LED, amarillo `#F4A20D` para alertas, rojo `#C0392B` para anomalías y alto consumo. Los colores por tecnología de lámpara y por condición climática también van aquí para que todos los gráficos Chart.js los usen de forma consistente.

También definir las variables de espaciado, radio de borde de tarjetas y sombras. Con esto, cambiar el diseño de todo el sistema es modificar un solo archivo.

---

**Tarea 2.3 — `base.html` o navbar compartido (20 minutos)**

Crear el navbar que se repite en todas las páginas. Dado que no se usa un template engine (el HTML es estático), el navbar se implementa como un componente JavaScript que se inyecta en cada página al cargar. Esto evita copiar y pegar el mismo HTML en 9 archivos y tener que actualizarlo en cada uno si cambia.

El navbar tiene fondo `#1B2A4A`, el nombre del proyecto a la izquierda, y los enlaces a las 9 páginas. El enlace de la página activa tiene fondo `#2E5C8A` para indicar la ubicación actual.

---

**Tarea 2.4 — Construir `index.html` (portada) si Integrante 1 no la toma**

Ver descripción en la tarea 1.6. Si el Integrante 1 ya la está construyendo, el Integrante 2 avanza directamente a la siguiente tarea.

---

**Tarea 2.5 — Construir `utils.js` (30 minutos)**

Antes de construir ninguna página con datos, crear el archivo de utilidades que todos los demás scripts van a importar. Este archivo centraliza tres cosas:

La función de carga de datos: recibe el nombre de un archivo JSON, lo busca en `data/`, lo carga con `fetch()` y devuelve una promesa con el resultado parseado. Incluir manejo de errores para que si un archivo falla, la página muestre un mensaje de error claro en lugar de romperse silenciosamente.

Las funciones de formato de números: formatear kWh con 2 decimales, formatear COP en millones con símbolo de moneda, formatear porcentajes, formatear fechas con nombre de mes en español. Estas funciones se usan en todas las páginas para que los números se vean consistentes.

La función de escala de colores: recibe un valor y un rango (mínimo, máximo) y devuelve el color correspondiente en la escala verde-amarillo-rojo. Se usa en el mapa choropleth y en las tablas con formato condicional.

---

### Fase 2: Páginas analíticas principales (Horas 3–7)

**Tarea 2.6 — `dashboard.html` (Vista General) — 90 minutos**

Esta es la página más importante y la primera que el profesor verá después de la portada.

La estructura de la página tiene tres secciones: la barra de filtros en la parte superior, los KPIs debajo de los filtros, y los gráficos principales en la zona inferior.

La barra de filtros tiene tres controles: un dropdown de localidad con las 20 localidades de Bogotá, un dropdown de condición climática con los valores que existan en los datos, y un selector de período (todos / diurno / nocturno). Un botón "Aplicar" que aplica todos los filtros de una vez. Un botón "Limpiar" que resetea los controles y recarga los datos sin filtro. Un banner visible debajo de los filtros cuando hay filtros activos que muestra qué filtros están aplicados actualmente.

La lógica de filtrado ocurre en JavaScript: al hacer clic en Aplicar, el código filtra el array de datos ya cargado en memoria usando los valores de los selectores. No hay ningún fetch adicional; los datos ya están en el navegador.

Los 4 KPIs se renderizan como tarjetas con el diseño del sistema de diseño: borde izquierdo de color, número grande, etiqueta pequeña en mayúsculas, y la variación respecto al promedio. Para kWh y costo, la variación en rojo si sube (malo) y verde si baja (bueno). Para ahorro, verde si sube (bueno). Los valores vienen de `kpis_generales.json` filtrado.

El gráfico de línea de la serie temporal dibuja dos líneas: año actual (azul institucional con área sombreada) y año anterior (gris punteada). Los datos vienen de `serie_temporal.json`. La lógica de construir las dos series la hace JavaScript tomando el mismo mes de cada año del objeto estructurado por año.

El gráfico de barras del top 10 de zonas usa barras horizontales con Chart.js. Las 10 zonas de mayor consumo, ordenadas de mayor a menor, con el color de la barra variando según el rango de la escala.

---

**Tarea 2.7 — `zonas.html` (Análisis por Zona) — 90 minutos**

Esta página tiene el mapa como visual principal. El mapa toma el 55–60% del ancho de la pantalla.

El mapa choropleth usa Leaflet.js. El proceso de construcción es: cargar el GeoJSON de localidades, luego cargar `consumo_por_zona.json`, luego cruzar ambos por el nombre de la localidad para asignar el color de cada polígono según el `kwh_total`. El color viene de la función de escala de `utils.js`. El popup al hacer clic en una localidad muestra nombre, kWh total, lux promedio, kWh por habitante y total de anomalías, tomados directamente del JSON.

El segundo mapa (o selector de métrica) muestra la misma geografía coloreada por `pct_cumplimiento_horario`. Si el tiempo es ajustado, implementar un toggle sobre el mapa que cambia entre "Consumo" y "Cumplimiento" en lugar de dos mapas separados.

El ranking de barras horizontales debajo del mapa muestra las 10 zonas de mayor kWh por habitante (no kWh total, porque normalizar por población hace la comparación más justa entre zonas grandes y pequeñas).

La tabla de indicadores tiene las columnas: Localidad, kWh Total, kWh/Habitante, Lux Promedio, Anomalías, % Cumplimiento. El ordenamiento al hacer clic en el encabezado se implementa con JavaScript nativo: guardar en una variable el estado actual de ordenamiento (columna + dirección) y al hacer clic re-renderizar la tabla con el array ordenado. El formato condicional de la columna de cumplimiento aplica clases CSS de Bootstrap según el valor.

---

**Tarea 2.8 — `tiempo.html` (Análisis Temporal) — 60 minutos**

El heatmap hora × día es el visual más complejo del sistema. Se construye con el plugin `chartjs-chart-matrix` disponible via CDN. El plugin permite crear una cuadrícula donde cada celda tiene un color basado en su valor. Los 168 puntos del JSON mapean directamente a las 168 celdas (24 horas × 7 días), coloreando de blanco (bajo consumo) a rojo oscuro (alto consumo).

Si el plugin matrix da problemas de compatibilidad, la alternativa es construir el heatmap con HTML puro: una tabla de 7 × 24 celdas donde el color de fondo de cada celda se asigna con el estilo inline calculado por JavaScript. Es menos elegante pero funciona siempre sin dependencias.

Debajo del heatmap: el gráfico de línea horaria con las tres series (kWh promedio, lux promedio, lux óptimo del ML). El plugin de anotaciones de Chart.js dibuja líneas verticales en hora 6 y hora 18.

El comparativo laborable vs fin de semana es un gráfico de barras agrupadas. JavaScript separa los datos del JSON en dos grupos usando el campo `es_fin_semana` y construye las dos series.

---

**Tarea 2.9 — `tecnologia.html` y `politica.html` — 60 minutos en total**

`tecnologia.html` tiene tres visuales: el gráfico de barras agrupadas comparando kWh y lux por tipo de lámpara, el scatter de eficiencia (lux/kWh vs kWh total), y el gauge de modernización LED. El scatter y las barras grupadas son Chart.js estándar. El gauge es un Chart.js `doughnut` configurado como semicírculo con `circumference: Math.PI` y `rotation: -Math.PI / 2`.

`politica.html` tiene dos gauges de cumplimiento (mismo patrón que el gauge de tecnología pero con los valores de `cumplimiento_politicas.json`), el mapa de incumplimiento (reutilizar el componente del mapa de zonas cambiando la métrica de coloreado), y la tabla de brechas ordenable por costo del incumplimiento.

---

### Fase 3: Páginas secundarias y modelo ML (Horas 7–9)

**Tarea 2.10 — `modelo_ml.html` — 45 minutos**

Esta página usa los JSONs del Integrante 4 (del modelo de Machine Learning), no los JSONs generados del DW. Si el Integrante 4 aún no entregó los JSONs reales, usar los datos de ejemplo definidos con la estructura acordada.

Las 4 tarjetas de métricas muestran R², MAE, Accuracy y F1-Score directamente desde el JSON. El gráfico de importancia de features es un gráfico de barras horizontal con Chart.js, ordenado de mayor a menor importancia. El explorador interactivo tiene 3 controles (hora, zona, clima) que buscan en la tabla `lookup_predicciones` del JSON el registro que coincide y muestra el lux óptimo predicho y el estado de encendido recomendado. No corre ningún modelo: solo busca en un array.

---

**Tarea 2.11 — Reemplazar datos placeholder con datos reales — 20 minutos**

Cuando el Integrante 1 confirme que todos los JSONs están en el repositorio, hacer `git pull`, verificar que los archivos están en `data/`, y probar cada página en el navegador. Los datos reales deben verse exactamente igual que los placeholder, solo con valores diferentes. Si alguna visualización se rompe, el problema está en un campo del JSON que tiene un nombre distinto al esperado en el código JavaScript; buscar el campo incorrecto y corregirlo.

---

**Tarea 2.12 — Coherencia visual y testing (30 minutos)**

Recorrer todas las páginas verificando: mismo navbar en todas, misma paleta de colores en todos los gráficos, tooltips con formato de número correcto (kWh con 2 decimales, COP con separador de miles), todos los filtros actualizan todos los visuales de su página.

Verificar que los KPIs de `dashboard.html` coinciden aproximadamente con los KPIs del dashboard de Power BI. Diferencias de decimales son aceptables. Diferencias del 10% o más requieren revisión de la consulta de generación.

---

### Fase 4: Deploy a GitHub Pages y Render (Hora 9–10)

**Tarea 2.13 — Deploy a GitHub Pages (15 minutos)**

Si el repositorio ya tiene GitHub Pages activado (tarea de configuración inicial), el deploy es automático con cada `git push`. Verificar que la URL pública `https://[usuario].github.io/iluminacion-bogota/` carga la portada correctamente. Navegar a cada página desde la URL pública (no desde `localhost`) para confirmar que los `fetch()` a los JSONs funcionan desde el dominio de GitHub.

Un problema frecuente: los paths en el `fetch()` deben ser relativos (`'data/consumo_por_zona.json'`) y no absolutos. Si los paths tienen `/` al inicio (`'/data/...'`), en GitHub Pages irán a la raíz del dominio en lugar de a la carpeta del repositorio.

**Verificar especialmente:** que el mapa de Leaflet carga el GeoJSON correctamente desde la URL pública, que las fuentes y los CDN de Bootstrap, Chart.js y Leaflet se cargan sin errores en la consola, y que la web funciona en Chrome móvil para la demo.

---

**Tarea 2.14 — Deploy opcional a Render (30 minutos)**

Render no es estrictamente necesario para la demo: GitHub Pages ya es la URL pública que el profesor necesita. Render agrega valor principalmente si se quiere un dominio más presentable que `github.io` o si en el futuro se añade un backend.

Para hacer el deploy a Render con el frontend estático: crear cuenta en Render, conectar el repositorio de GitHub, seleccionar "Static Site" como tipo de servicio (no "Web Service", que es para backends). Configurar la carpeta raíz y el comando de build (ninguno, es HTML estático). Render asigna una URL pública con dominio `render.com`.

Con Static Site en Render no hay cold start: el servicio no se pausa porque no tiene ningún proceso corriendo. Solo sirve archivos estáticos desde su CDN, igual que GitHub Pages pero con una URL diferente.

---

## 6. Coordinación y Puntos de Sincronización

### Cómo evitar conflictos de merge

Cada integrante trabaja en archivos distintos. El Integrante 1 trabaja en `data/*.json`, `index.html`, `clima.html` y `sensores.html`. El Integrante 2 trabaja en `dashboard.html`, `zonas.html`, `tiempo.html`, `tecnologia.html`, `politica.html`, `modelo_ml.html`, `css/styles.css` y todos los archivos `js/`. No hay superposición, así que no deben ocurrir conflictos de merge.

La única excepción es `index.html`: si ambos la trabajan simultáneamente, decidir quién la hace (preferiblemente el Integrante 1) y el otro la deja en paz.

### Los tres momentos de sincronización obligatoria

**Sincronización 1 (Hora ~2):** el Integrante 1 sube `consumo_por_zona.json`, `kpis_generales.json` y el GeoJSON. El Integrante 2 hace `git pull` y reemplaza sus datos placeholder de zonas y KPIs. Ambos confirman que los datos se ven en `dashboard.html` y `zonas.html`.

**Sincronización 2 (Hora ~5):** el Integrante 1 confirma que los 8 JSONs están en el repositorio. El Integrante 2 hace `git pull` y reemplaza todos los placeholders restantes. Ambos verifican que ninguna página muestra errores en la consola del navegador.

**Sincronización 3 (Hora ~9):** verificación conjunta del sistema completo desde la URL pública de GitHub Pages. Cada uno navega por las páginas que el otro construyó y reporta cualquier problema visual o de datos.

### Comunicación de cambios en el formato de los JSONs

Si el Integrante 1 descubre durante la generación que un campo del JSON necesita un nombre diferente al que está en esta guía (por ejemplo, que la columna se llama `zona_nombre` en lugar de `nombre_zona`), debe notificarlo inmediatamente al Integrante 2 antes de hacer el push. Un campo con nombre incorrecto no rompe el script de Python, pero sí rompe silenciosamente todas las visualizaciones que lo usan en el navegador.

---

## Resumen ejecutivo — Qué hace quién y cuándo

```
HORA 1    INT.1: Verificar conexión SQL + primer JSON (kpis_generales)
          INT.2: Configurar Flask local + CSS variables + navbar

HORA 2    INT.1: consumo_por_zona.json + GeoJSON → push → NOTIFICAR
          INT.2: utils.js + estructura de dashboard.html con placeholder

HORA 3    INT.1: serie_temporal + consumo_por_hora → push
          INT.2: dashboard.html completo con datos reales de zona y KPIs

HORA 4    INT.1: cumplimiento_politicas + consumo_por_tecnologia → push
          INT.2: zonas.html completo (mapa + tabla)

HORA 5    INT.1: consumo_por_clima + estado_sensores → push → TODOS LOS JSON LISTOS
          INT.2: tiempo.html (heatmap + gráfico horario)

HORA 6    INT.1: Verificación cruzada con Power BI + index.html
          INT.2: tecnologia.html + politica.html

HORA 7    INT.1: clima.html + sensores.html
          INT.2: modelo_ml.html + reemplazo de placeholders

HORA 8    INT.1: Revisar trabajo del INT.2 + fixes de datos si hay discrepancias
          INT.2: Testing completo + coherencia visual

HORA 9    AMBOS: Verificación conjunta desde URL pública de GitHub Pages

HORA 10   INT.2: Deploy a Render (opcional)
          INT.1: README + documentación mínima del repositorio
          AMBOS: Push final y commit de cierre
```

---

*Sistema de Monitorización de Iluminación Inteligente — Bogotá D.C.*
*Guía de Implementación v3 — GitHub Pages + JSON Estático · División Int.1 / Int.2*
*ODS 7 · ODS 11 · ODS 13*