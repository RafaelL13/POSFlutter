(() => {
  'use strict';
  const root = document.getElementById('ap-root');
  if (!root) return;
  const $ = id => document.getElementById(id);
  const canWrite = root.dataset.labWrites === 'true';
  const state = { products: [], categories: [], editing: null, busy: false };
  const status = (text, error = false) => { const node = $('ap-status'); node.textContent = text; node.style.color = error ? '#9a2727' : '#244451'; };
  const money = cents => new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(Number(cents || 0) / 100);
  const make = (tag, value) => { const node = document.createElement(tag); node.textContent = String(value ?? ''); return node; };
  const get = async path => {
    const response = await fetch(path, { credentials: 'same-origin', cache: 'no-store', headers: { Accept: 'application/json' } });
    if (response.status === 401) throw new Error('Tu sesiÃ³n expirÃ³; inicia sesiÃ³n nuevamente.');
    if (response.status === 403) throw new Error('Tu usuario no tiene permiso para consultar este catÃ¡logo.');
    if (!response.ok) throw new Error(`No se pudo cargar ${path}: HTTP ${response.status}`);
    const data = await response.json();
        const rows = Array.isArray(data) ? data :
      (data && !Array.isArray(data) && Array.isArray(data.items) ? data.items : null);
    if (!rows) throw new Error(`Respuesta de ${path} no contiene una lista vÃ¡lida.`);
    return rows;
  };
  const render = () => {
    const filter = ($('ap-filter').value || '').trim().toLocaleLowerCase('es-MX');
    const list = state.products.filter(p => [p.code, p.name, p.barcode].some(v => String(v || '').toLocaleLowerCase('es-MX').includes(filter)));
    const body = $('ap-rows'); body.replaceChildren();
    for (const p of list) {
      const card = document.createElement('article'); card.className = 'ap-product-card';
      const identity = document.createElement('div'); identity.className = 'ap-product-identity';
      const title = make('strong', p.name); const details = make('span', `${p.code} · ${p.presentation || 'Pieza'} · Existencia: ${p.availableQuantity ?? '—'}`); identity.append(title, details);
      const value = document.createElement('div'); value.className = 'ap-product-value'; value.append(make('strong', money(p.salePriceCents)), make('span', p.active ? 'Activo' : 'Inactivo'));
      const actions = document.createElement('div'); actions.className = 'ap-product-actions';
      if (canWrite) {
        const btn = make('button', 'Editar'); btn.type = 'button';
        btn.addEventListener('click', () => edit(p)); actions.append(btn);
      } else { actions.append(make('span', 'Solo lectura')); }
      card.append(identity, value, actions); body.append(card);
    }
    if (!list.length) { const empty = make('p', 'No hay productos para este filtro.'); empty.className = 'ap-empty'; body.append(empty); }
  };
  const edit = p => {
    const form = $('ap-form'); if (!form) return;
    state.editing = p;
    for (const field of ['code','barcode','name','presentation','minimumStock']) form.elements[field].value = p[field] ?? '';
    form.elements.price.value = (Number(p.salePriceCents || 0) / 100).toFixed(2);
    form.elements.categoryGlobalId.value = p.categoryGlobalId || '';
    form.elements.active.checked = !!p.active;
    $('ap-editor-title').textContent = `Editar ${p.name}`;
    $('ap-form').scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  const clear = () => {
    const form = $('ap-form'); if (!form) return;
    form.reset(); state.editing = null; $('ap-editor-title').textContent = 'Alta de producto (LAB)';
  };
  const load = async () => {
    status('Consultando catÃ¡logo y categorÃ­asâ€¦');
    try {
      const [products, categories] = await Promise.all([get('/admin/products/catalog'), get('/data/categories')]);
      state.products = products; state.categories = categories;
      if (canWrite) {
        const select = $('ap-form').elements.categoryGlobalId;
        const selected = select.value;
        select.replaceChildren(new Option('Sin categorÃ­a', ''));
        categories.filter(c => c.active).forEach(c => select.add(new Option(c.name, c.globalId)));
        select.value = selected;
      }
      render(); status(`${products.length} productos visibles desde la sesiÃ³n autorizada. ${canWrite ? 'Escritura LAB habilitada.' : 'Solo lectura.'}`);
    } catch (err) { status(err.message || 'Error consultando catÃ¡logo.', true); }
  };
  const submit = async event => {
    event.preventDefault();
    if (!canWrite || state.busy) return;
    const form = $('ap-form');
    const priceText = String(form.elements.price.value || '');
    if (!/^\d+(?:\.\d{1,2})?$/.test(priceText)) { status('El precio debe tener como mÃ¡ximo 2 decimales.', true); return; }
    const [whole, fraction = ''] = priceText.split('.');
    const priceCents = Number(whole) * 100 + Number(fraction.padEnd(2,'0'));
    if (!Number.isSafeInteger(priceCents)) { status('Importe fuera de rango.', true); return; }
    const body = {
      globalId: state.editing?.globalId || null,
      expectedServerVersion: state.editing?.serverVersion ?? null,
      categoryGlobalId: form.elements.categoryGlobalId.value || null,
      code: form.elements.code.value.trim(), barcode: form.elements.barcode.value.trim() || null,
      name: form.elements.name.value.trim(), presentation: form.elements.presentation.value.trim(),
      salePriceCents: priceCents, minimumStock: Number(form.elements.minimumStock.value),
      active: form.elements.active.checked
    };
    const token = document.querySelector('input[name="__RequestVerificationToken"]')?.value;
    if (!token) { status('Falta la protecciÃ³n antifalsificaciÃ³n del formulario.', true); return; }
    state.busy = true; $('ap-save').disabled = true;
    try {
      const response = await fetch('/admin/products/save', {
        method: 'POST', credentials: 'same-origin', headers: { 'Content-Type':'application/json', 'Accept':'application/json', 'X-CSRF-TOKEN': token },
        body: JSON.stringify(body)
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        if (response.status === 409) throw new Error('Conflicto de versiÃ³n o cÃ³digo repetido. Actualiza el catÃ¡logo antes de editar de nuevo.');
        if (response.status === 423) throw new Error('Las escrituras LAB estÃ¡n deshabilitadas por seguridad.');
        throw new Error(`No se pudo guardar (${response.status}): ${result.code || 'error'}`);
      }
      clear(); await load(); status(`Producto guardado en LAB. VersiÃ³n del servidor: ${result.serverVersion}.`);
    } catch(err) { status(err.message || 'Error guardando producto.', true); }
    finally { state.busy = false; $('ap-save').disabled = false; }
  };
  $('ap-filter').addEventListener('input', render);
  $('ap-reload').addEventListener('click', load);
  if (canWrite) { $('ap-clear').addEventListener('click', clear); $('ap-form').addEventListener('submit', submit); }
  load();
})();
