(() => {
  'use strict';
  const root = document.getElementById('ps-supervision');
  if (!root) return;
  const $ = id => document.getElementById(id);
  const endpoints = { dashboard: '/data/dashboard', inventory: '/data/inventory', products: '/data/products', branches: '/data/branches', devices: '/data/devices', sales: '/data/sales' };
  const limits = { inventory: 30, products: 30, branches: 30, devices: 30, sales: 15 };
  const preferred = {
    inventory: ['name', 'productName', 'sku', 'stock', 'quantity', 'availableQuantity', 'branchName', 'unit'],
    products: ['name', 'productName', 'sku', 'code', 'barcode', 'priceCents', 'salePriceCents', 'categoryName', 'active'],
    branches: ['name', 'branchName', 'code', 'status', 'active'],
    devices: ['name', 'deviceName', 'branchName', 'status', 'lastSyncAt', 'lastSyncUtc', 'lastSeenAt', 'lastSeenUtc', 'lastHeartbeatAt'],
    sales: ['folio', 'saleDateTime', 'dateTime', 'branchName', 'userName', 'paymentMethod', 'status', 'totalCents', 'total']
  };
  const lab = ['localhost', '127.0.0.1'].includes(location.hostname) && location.port === '18443';
  $('ps-origin').dataset.lab = String(lab);
  $('ps-origin').textContent = lab
    ? 'LAB LOCAL Â· Datos de prueba. No representan ventas ni existencias reales del negocio.'
    : 'ORIGEN NO VERIFICADO Â· No se ha certificado que estos datos correspondan al servidor comercial.';
  let busy = false;
  let count = 0;
  const time = value => {
    if (!value) return 'No disponible';
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? String(value) : d.toLocaleString('es-MX');
  };
  function label(key) { return String(key).replace(/([a-z\d])([A-Z])/g, '$1 $2').replace(/_/g, ' '); }
  function value(key, input) {
    if (input === null || input === undefined || input === '') return 'No disponible';
    if (typeof input === 'boolean') return input ? 'SÃ­' : 'No';
    if (typeof input === 'number' && Number.isFinite(input)) {
      if (/cents$/i.test(key)) return (input / 100).toLocaleString('es-MX', { style: 'currency', currency: 'MXN' });
      return input.toLocaleString('es-MX', { maximumFractionDigits: 4 });
    }
    if (/date|time|sync|seen|heartbeat|updated/i.test(key) && typeof input === 'string') return time(input);
    if (typeof input === 'object') return Array.isArray(input) ? `${input.length} elementos` : 'Ver detalle en reportes';
    return String(input).slice(0, 180);
  }
  function items(response, kind) {
    if (Array.isArray(response)) return response;
    if (!response || typeof response !== 'object') return null;
    const guesses = ['items', 'data', 'results', 'rows', kind, 'list'];
    for (const key of guesses) if (Array.isArray(response[key])) return response[key];
    const matches = Object.entries(response).filter(([, v]) => Array.isArray(v));
    return matches.length === 1 ? matches[0][1] : null;
  }
  function empty(el, text) { el.replaceChildren(); const p = document.createElement('p'); p.className = 'ps-empty'; p.textContent = text; el.append(p); }
  function message(kind, text, error = false) { const el = $(`ps-${kind}-message`); el.textContent = text || ''; el.dataset.error = String(error); }
  function table(kind, response) {
    const host = $(`ps-${kind}`);
    const arr = items(response, kind);
    if (arr === null) { empty(host, 'Formato de respuesta no reconocido. No se presentan datos inventados.'); message(kind, 'Revisar contrato real del endpoint.', true); return; }
    $(`ps-${kind}-meta`).textContent = `${Math.min(arr.length, limits[kind])} mostrados${arr.length > limits[kind] ? ' (muestra)' : ''}`;
    if (!arr.length) { empty(host, 'Sin registros en este alcance autorizado.'); message(kind, ''); return; }
    const objects = arr.filter(x => x && typeof x === 'object' && !Array.isArray(x));
    if (!objects.length) { empty(host, 'Respuesta sin registros tabulares.'); message(kind, '', false); return; }
    const available = [...new Set(objects.slice(0, 12).flatMap(x => Object.keys(x)).filter(key => typeof objects[0][key] !== 'object'))];
    let keys = preferred[kind].filter(k => available.includes(k));
    if (!keys.length) keys = available.slice(0, 5);
    if (!keys.length) { empty(host, 'No hay campos simples para presentar.'); return; }
    const tbl = document.createElement('table'); tbl.className = 'ps-table';
    const caption = document.createElement('caption'); caption.className = 'ps-empty'; caption.textContent = `Muestra de ${kind}; alcance definido por el backend`;
    const thead = document.createElement('thead'), head = document.createElement('tr');
    for (const key of keys) { const th = document.createElement('th'); th.scope = 'col'; th.textContent = label(key); head.append(th); }
    thead.append(head); const tbody = document.createElement('tbody');
    for (const record of objects.slice(0, limits[kind])) {
      const tr = document.createElement('tr');
      for (const key of keys) { const td = document.createElement('td'); td.textContent = value(key, record[key]); tr.append(td); }
      tbody.append(tr);
    }
    tbl.append(caption, thead, tbody); host.replaceChildren(tbl);
    message(kind, kind === 'sales' ? 'La consulta estÃ¡ limitada en origen; no calculamos ventas totales con esta muestra.' : '');
  }
  function dashboard(response) {
    const el = $('ps-dashboard');
    if (!response || typeof response !== 'object' || Array.isArray(response)) { empty(el, 'No hay indicadores interpretables disponibles.'); return; }
    const candidates = [response];
    for (const name of ['summary', 'totals', 'metrics', 'dashboard']) {
      if (response[name] && typeof response[name] === 'object' && !Array.isArray(response[name])) candidates.push(response[name]);
    }
    const fields = candidates.flatMap(o => Object.entries(o)).filter(([, v]) => typeof v === 'number' || typeof v === 'boolean' || typeof v === 'string');
    if (!fields.length) { empty(el, 'La API no entregÃ³ indicadores simples reconocibles.'); return; }
    const unique = new Map(fields); const dl = document.createElement('dl'); dl.className = 'ps-kpis';
    [...unique.entries()].slice(0, 12).forEach(([key, val]) => {
      const item = document.createElement('div'); item.className = 'ps-kpi';
      const dt = document.createElement('dt'); dt.textContent = label(key);
      const dd = document.createElement('dd'); dd.textContent = value(key, val);
      item.append(dt, dd); dl.append(item);
    });
    el.replaceChildren(dl);
  }
  async function request(kind) {
    const ctrl = new AbortController(); const timeout = setTimeout(() => ctrl.abort(), 12000);
    try {
      const response = await fetch(endpoints[kind], { credentials: 'same-origin', cache: 'no-store', headers: { 'Accept': 'application/json' }, signal: ctrl.signal });
      if (response.status === 401) throw new Error('401 Â· SesiÃ³n requerida. Inicia sesiÃ³n nuevamente.');
      if (response.status === 403) throw new Error('403 Â· Sin permisos para estos datos.');
      if (!response.ok) throw new Error(`${response.status} Â· No se pudo obtener informaciÃ³n del servidor.`);
      return await response.json();
    } finally { clearTimeout(timeout); }
  }
  async function refresh() {
    if (busy || document.hidden) return;
    busy = true; count++;
    const button = $('ps-refresh'); button.disabled = true;
    $('ps-status').textContent = count === 1 ? 'Consultando informaciÃ³n autorizadaâ€¦' : 'Actualizando informaciÃ³nâ€¦';
    let failed = 0;
    try {
      await Promise.all(Object.keys(endpoints).map(async kind => {
        try {
          const response = await request(kind);
          if (kind === 'dashboard') { dashboard(response); message(kind, ''); }
          else table(kind, response);
        } catch (err) {
          failed++;
          const text = err.name === 'AbortError' ? 'Tiempo de espera agotado.' : err.message;
          if (kind === 'dashboard') empty($('ps-dashboard'), 'Indicadores no disponibles.');
          else { empty($(`ps-${kind}`), 'Datos no disponibles.'); $(`ps-${kind}-meta`).textContent = ''; }
          message(kind, text, true);
        }
      }));
      $('ps-lastread').textContent = 'Ãšltima lectura del panel: ' + new Date().toLocaleString('es-MX');
      $('ps-status').textContent = failed ? `${Object.keys(endpoints).length - failed} secciones actualizadas; ${failed} con error.` : 'Todas las secciones consultadas correctamente.';
      $('ps-status').dataset.error = String(failed > 0);
    } finally { busy = false; button.disabled = false; }
  }
  $('ps-refresh').addEventListener('click', refresh);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  refresh();
  setInterval(refresh, 30000);
})();