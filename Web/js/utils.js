// ── utils.js — Funciones compartidas ────────────────────────

// ── 1. CARGA DE DATOS ────────────────────────────────────────
const cache = {};

async function cargarJSON(archivo) {
    if (cache[archivo]) return cache[archivo];
    try {
        const resp = await fetch(`data/${archivo}`);
        if (!resp.ok) throw new Error(`No se pudo cargar ${archivo}`);
        const datos = await resp.json();
        cache[archivo] = datos;
        return datos;
    } catch (err) {
        console.error(err);
        return null;
    }
}

// ── 2. FORMATO DE NÚMEROS ────────────────────────────────────
function fmtKwh(val) {
    if (val === null || val === undefined) return '—';
    return Number(val).toLocaleString('es-CO', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    }) + ' kWh';
}

function fmtCOP(val) {
    if (val === null || val === undefined) return '—';
    if (val >= 1_000_000)
        return '$ ' + (val / 1_000_000).toLocaleString('es-CO', {
            minimumFractionDigits: 2, maximumFractionDigits: 2
        }) + ' M';
    return '$ ' + Number(val).toLocaleString('es-CO', {
        minimumFractionDigits: 0, maximumFractionDigits: 0
    });
}

function fmtPct(val) {
    if (val === null || val === undefined) return '—';
    return Number(val).toFixed(1) + '%';
}

function fmtLux(val) {
    if (val === null || val === undefined) return '—';
    return Number(val).toLocaleString('es-CO', {
        minimumFractionDigits: 0, maximumFractionDigits: 0
    }) + ' lux';
}

function fmtNum(val, decimales = 0) {
    if (val === null || val === undefined) return '—';
    return Number(val).toLocaleString('es-CO', {
        minimumFractionDigits: decimales,
        maximumFractionDigits: decimales
    });
}

// ── 3. ESCALA DE COLORES (verde → amarillo → rojo) ───────────
function escalaColor(valor, min, max) {
    const pct = Math.max(0, Math.min(1, (valor - min) / (max - min)));
    if (pct < 0.5) {
        const r = Math.round(26  + (244 - 26)  * pct * 2);
        const g = Math.round(122 + (162 - 122) * pct * 2);
        const b = Math.round(74  + (13  - 74)  * pct * 2);
        return `rgb(${r},${g},${b})`;
    } else {
        const p2 = (pct - 0.5) * 2;
        const r = Math.round(244 + (192 - 244) * p2);
        const g = Math.round(162 + (57  - 162) * p2);
        const b = Math.round(13  + (43  - 13)  * p2);
        return `rgb(${r},${g},${b})`;
    }
}

// ── 4. NAVBAR ACTIVO ─────────────────────────────────────────
function marcarNavActivo() {
    const pagina = window.location.pathname.split('/').pop() || 'index.html';
    document.querySelectorAll('.navbar-nav-custom a').forEach(a => {
        if (a.getAttribute('href') === pagina) a.classList.add('activo');
    });
}

// ── 5. NAVBAR HTML ────────────────────────────────────────────
function inyectarNavbar() {
    const nav = `
    <nav class="navbar-iluminacion">
        <a href="index.html" class="navbar-brand-custom">
            💡 Iluminación Bogotá
        </a>
        <ul class="navbar-nav-custom">
            <li><a href="index.html">Inicio</a></li>
            <li><a href="dashboard.html">Dashboard</a></li>
            <li><a href="zonas.html">Zonas</a></li>
            <li><a href="tiempo.html">Temporal</a></li>
            <li><a href="tecnologia.html">Tecnología</a></li>
            <li><a href="politica.html">Política</a></li>
            <li><a href="modelo_ml.html">Modelo ML</a></li>
        </ul>
    </nav>`;
    document.body.insertAdjacentHTML('afterbegin', nav);
    marcarNavActivo();
}

// ── 6. MOSTRAR ERROR EN TARJETA ──────────────────────────────
function mostrarError(elementoId, mensaje = 'Error al cargar datos') {
    const el = document.getElementById(elementoId);
    if (el) el.innerHTML = `
        <div style="padding:2rem;text-align:center;color:var(--rojo)">
            ⚠️ ${mensaje}
        </div>`;
}

// ── 7. MOSTRAR SPINNER ────────────────────────────────────────
function mostrarSpinner(elementoId) {
    const el = document.getElementById(elementoId);
    if (el) el.innerHTML = `
        <div class="loading">
            <div class="spinner"></div> Cargando datos...
        </div>`;
}

// ── 8. BADGE DE CRITICIDAD ────────────────────────────────────
function badgeCriticidad(estado) {
    const map = {
        'NORMAL'  : 'badge-normal',
        'ALERTA'  : 'badge-alerta',
        'CRITICO' : 'badge-critico',
        'INACTIVO': 'badge-inactivo',
    };
    const cls = map[estado] || 'badge-normal';
    return `<span class="${cls}">${estado}</span>`;
}

// ── 9. PALETA DE CHART.JS ─────────────────────────────────────
const PALETA = [
    '#2E5C8A','#1A7A4A','#F4A20D','#C0392B',
    '#5B9BD5','#8E44AD','#1B2A4A','#95A5A6'
];

const OPCIONES_BASE_CHART = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
        legend: { labels: { font: { size: 11 }, color: '#212529' } }
    },
    scales: {
        x: { ticks: { color: '#6C757D', font: { size: 10 } },
             grid:  { color: '#DEE2E6' } },
        y: { ticks: { color: '#6C757D', font: { size: 10 } },
             grid:  { color: '#DEE2E6' } }
    }
};