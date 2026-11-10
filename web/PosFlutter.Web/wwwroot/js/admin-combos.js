'use strict';
(() => {
  const root = document.getElementById('combosAdmin');
  if (!root) return;
  const $ = (id) => document.getElementById(id);
  const writable = root.dataset.canWrite === 'true';
  const dom = {
    select: $('comboSelect'), code: $('comboCode'), name: $('comboName'), price: $('comboPrice'),
    active: $('comboActive'), components: $('comboComponents'), load: $('loadStatus'),
    save: $('saveStatus'), add: $('addComponentButton'), submit: $('saveComboButton'),
    summary: $('priceSummary')
  };
  const state = { combos: [], products: [], selected: null };
  const cents = (s) => {
    if (typeof s !== 'string' || !/^\d{1,11}(\.\d{1,2})?$/.test(s.trim())) return null;
    const parts = s.trim().split('.');
    const value = Number(parts[0]) * 100 + Number((parts[1] || '').padEnd(2, '0'));
    return Number.isSafeInteger(value) ? value : null;
  };
  const money = (value) => `${(Number(value || 0) / 100).toFixed(2)}`;
  function productOptions(selected) {
    return state.products.map(p => `<option value="${p.globalId}" ${p.globalId === selected ? 'selected' : ''} ${!p.active && p.globalId !== selected ? 'disabled' : ''}></option>`);
  }
  function addComponent(item = null) {
    const box = document.createElement('div');
    box.className = 'combos-component';
    const pLabel = document.createElement('label');
    pLabel.textContent = 'Producto';
    const select = document.createElement('select');
    select.className = 'component-product';
    for (const p of state.products) {
      const o = document.createElement('option');
      o.value = p.globalId;
      o.textContent = `${p.code} — ${p.name} ($${money(p.salePriceCents)})${p.active ? '' : ' [Inactivo]'}`;
      o.disabled = !p.active && p.globalId !== item?.productGlobalId;
      select.appendChild(o);
    }
    if (item?.productGlobalId) select.value = item.productGlobalId;
    pLabel.appendChild(select);
    const qtyLabel = document.createElement('label'); qtyLabel.textContent = 'Cantidad';
    const qty = document.createElement('input'); qty.className = 'component-qty'; qty.type = 'number'; qty.min = 1; qty.max = 999; qty.step = 1; qty.value = item?.quantity || 1; qtyLabel.appendChild(qty);
    const fixedLabel = document.createElement('label'); fixedLabel.textContent = 'Precio fijo unitario ($)';
    const fixed = document.createElement('input'); fixed.className = 'component-fixed'; fixed.inputMode = 'decimal'; fixed.placeholder = 'Proporcional';
    if (item?.fixedUnitPriceCents != null) fixed.value = money(item.fixedUnitPriceCents);
    fixedLabel.appendChild(fixed);
    const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = 'Quitar';
    remove.addEventListener('click', () => {box.remove(); summarize();});
    box.append(pLabel, qtyLabel, fixedLabel, remove); dom.components.appendChild(box);
    box.querySelectorAll('input,select,button').forEach(el => {
      if (!writable) el.disabled = true;
      el.addEventListener('change', summarize);
    });
    summarize();
  }
  function rows() { return [...dom.components.querySelectorAll('.combos-component')]; }
  function summarize() {
    const r = rows(); let total = 0, fixedCount = 0, valid = true;
    for (const row of r) {
      const qty = Number(row.querySelector('.component-qty').value);
      const raw = row.querySelector('.component-fixed').value.trim();
      const unit = raw ? cents(raw) : null;
      if (!Number.isInteger(qty) || qty < 1 || qty > 999 || (raw && (!unit || unit <= 0))) valid = false;
      if (unit != null) { fixedCount++; total += unit * qty; }
    }
    if (fixedCount && fixedCount !== r.length) valid = false;
    const price = cents(dom.price.value.trim());
    if (fixedCount && total !== price) valid = false;
    dom.summary.textContent = fixedCount ? `Suma de precios fijos: $${money(total)}. ${valid ? 'Cuadra con el total.' : 'Revisar importes.'}` : 'Distribución proporcional (compatibilidad anterior).';
    dom.submit.disabled = !writable || !valid || r.length === 0 || !price || !dom.code.value.trim() || !dom.name.value.trim();
  }
  function choose(combo) {
    state.selected = combo || null;
    dom.code.value = combo?.code || ''; dom.name.value = combo?.name || '';
    dom.price.value = combo ? money(combo.comboPriceCents) : '';
    dom.active.checked = combo?.active ?? true;
    dom.components.replaceChildren();
    (combo?.components || []).forEach(addComponent);
    dom.save.textContent = ''; summarize();
  }
  function render() {
    dom.select.replaceChildren(new Option('Nuevo combo', ''));
    for (const c of state.combos) dom.select.appendChild(new Option(`${c.code} — ${c.name}${c.active ? '' : ' [Inactivo]'}`, c.globalId));
  }
  async function load() {
    dom.load.textContent = 'Cargando...';
    const resp = await fetch('/admin/combos/data', { credentials: 'same-origin', cache: 'no-store' });
    if (!resp.ok) throw new Error(`No se pudo consultar el catálogo administrativo (HTTP ${resp.status}).`);
    const data = await resp.json();
    state.products = data.products || []; state.combos = data.combos || [];
    render(); dom.load.textContent = `${state.combos.length} combo(s) disponibles.`;
    if (state.selected) {
      const selected = state.combos.find(c => c.globalId === state.selected.globalId);
      choose(selected || null); dom.select.value = selected?.globalId || '';
    } else choose(null);
  }
  dom.select.addEventListener('change', () => choose(state.combos.find(c => c.globalId === dom.select.value)));
  $('newComboButton').addEventListener('click', () => {dom.select.value = ''; choose(null);});
  dom.add.addEventListener('click', () => addComponent());
  [dom.code,dom.name,dom.price,dom.active].forEach(el => el.addEventListener('input', summarize));
  dom.form = $('comboForm');
  dom.form.addEventListener('submit', async (ev) => {
    ev.preventDefault(); if (!writable || dom.submit.disabled) return;
    const components = rows().map(r => {
      const fixed = r.querySelector('.component-fixed').value.trim();
      return { productGlobalId: r.querySelector('.component-product').value,
        quantity: Number(r.querySelector('.component-qty').value), fixedUnitPriceCents: fixed ? cents(fixed) : null };
    });
    const dto = { globalId: state.selected?.globalId || null,
      expectedServerVersion: state.selected?.serverVersion ?? null,
      code: dom.code.value.trim(), name: dom.name.value.trim(), comboPriceCents: cents(dom.price.value.trim()),
      active: dom.active.checked, components };
    if (!Number.isSafeInteger(dto.comboPriceCents) || dto.comboPriceCents <= 0 ||
      components.length < 1 || components.length > 20 ||
      new Set(components.map(x => x.productGlobalId)).size !== components.length ||
      components.some(x => !Number.isInteger(x.quantity) || x.quantity < 1 || x.quantity > 999)) {
      dom.save.textContent = 'Revisa productos, cantidades e importes.'; return;
    }
    dom.submit.disabled = true; dom.save.textContent = 'Guardando...';
    try {
      const token = dom.form.querySelector('input[name="__RequestVerificationToken"]')?.value;
      if (!token) throw new Error('Falta token de seguridad.');
      const resp = await fetch('/admin/combos/save', { method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': token }, body: JSON.stringify(dto) });
      const body = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(`${body.code || 'Error al guardar'} (HTTP ${resp.status})`);
      state.selected = { globalId: body.globalId };
      await load(); dom.save.textContent = 'Combo guardado correctamente.';
    } catch (err) { dom.save.textContent = err.message || 'No se pudo guardar.'; }
    finally { summarize(); }
  });
  if (!writable) [dom.code,dom.name,dom.price,dom.active,dom.select,dom.add].forEach(el => { if (el !== dom.select) el.disabled = true; });
  load().catch(err => { dom.load.textContent = err.message || 'Error al cargar'; });
})();
