(() => {
  'use strict';
  const form = document.getElementById('purchase-form');
  const supplier = document.getElementById('supplier');
  const product = document.getElementById('product');
  const quantity = document.getElementById('quantity');
  const cost = document.getElementById('cost');
  const tbody = document.getElementById('lines');
  const totalEl = document.getElementById('total');
  const saveButton = document.getElementById('submit');
  const result = document.getElementById('result');
  const addFeedback = document.getElementById('add-feedback');
  const addButton = document.getElementById('add-line');
  const lines = [];
  let operationId = null;
  let busy = false;
  const context = JSON.parse(form.dataset.purchaseContext);

  function newId() {
    if (!window.crypto || typeof window.crypto.randomUUID !== 'function') {
      throw new Error('Se requiere HTTPS o localhost con un navegador compatible para generar identificadores seguros.');
    }
    return window.crypto.randomUUID();
  }
  function money(cents) {
    return new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(cents / 100);
  }
  function notify(message, isError) {
    addFeedback.textContent = message;
    addFeedback.classList.toggle('is-error', Boolean(isError));
    addFeedback.classList.toggle('is-success', !isError);
  }
  function render() {
    tbody.replaceChildren();
    lines.forEach((line, i) => {
      const tr = document.createElement('tr');
      [line.name, String(line.quantity), money(line.unitCostCents), money(line.subtotalCents)].forEach(v => {
        const td = document.createElement('td'); td.textContent = v; tr.appendChild(td);
      });
      const td = document.createElement('td');
      const remove = document.createElement('button');
      remove.type = 'button'; remove.className = 'btn btn-sm btn-outline-danger'; remove.textContent = 'Quitar';
      remove.addEventListener('click', () => { lines.splice(i, 1); render(); notify('Producto quitado.', false); });
      td.appendChild(remove); tr.appendChild(td); tbody.appendChild(tr);
    });
    totalEl.textContent = money(lines.reduce((sum, line) => sum + line.subtotalCents, 0));
  }
  function parseCents(value) {
    const normalized = value.trim().replace(',', '.');
    if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
    const [whole, fraction = ''] = normalized.split('.');
    const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
    return Number.isSafeInteger(cents) ? cents : null;
  }

  addButton.addEventListener('click', () => {
    try {
      if (!supplier.value) { notify('Selecciona primero un proveedor.', true); supplier.focus(); return; }
      if (!product.value) { notify('Selecciona un producto antes de agregarlo.', true); product.focus(); return; }
      const q = Number(quantity.value);
      if (!Number.isSafeInteger(q) || q < 1) { notify('La cantidad debe ser un entero mayor que cero.', true); quantity.focus(); return; }
      const cents = parseCents(cost.value);
      if (cents === null) { notify('Costo inválido. Usa 0,00 o 10,50 (también admite punto).', true); cost.focus(); return; }
      const subtotal = q * cents;
      if (!Number.isSafeInteger(subtotal)) { notify('El subtotal excede el límite permitido.', true); return; }
      if (lines.some(x => x.productGlobalId === product.value)) {
        notify('Ese producto ya se agregó; quítalo antes de volverlo a capturar.', true); product.focus(); return;
      }
      const line = {
        detailGlobalId: newId(), productGlobalId: product.value, lotGlobalId: newId(),
        quantity: q, unitCostCents: cents, subtotalCents: subtotal,
        name: product.selectedOptions[0].text
      };
      lines.push(line);
      render();
      notify('Producto agregado: ' + line.name + ' · ' + q + ' unidad(es) · ' + money(subtotal), false);
      result.textContent = '';
    } catch (error) {
      notify('No se pudo agregar: ' + (error.message || 'error de navegador'), true);
    }
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy) return;
    if (!supplier.value || lines.length === 0) {
      result.textContent = 'Selecciona proveedor y agrega al menos un producto.'; return;
    }
    const total = lines.reduce((sum, line) => sum + line.subtotalCents, 0);
    if (!Number.isSafeInteger(total)) { result.textContent = 'Total fuera de rango.'; return; }
    try { if (!operationId) operationId = newId(); }
    catch (error) { result.textContent = error.message; return; }
    busy = true; saveButton.disabled = true; result.textContent = 'Guardando compra...';
    const payload = {
      globalId: operationId, ...context, supplierGlobalId: supplier.value,
      date: new Date().toISOString(), reference: document.getElementById('reference').value,
      notes: document.getElementById('notes').value, totalCents: total,
      lines: lines.map(({ name, ...data }) => data)
    };
    try {
      const response = await fetch('/purchases', {
        method: 'POST', credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': form.querySelector('input[name="__RequestVerificationToken"]').value
        },
        body: JSON.stringify(payload)
      });
      const data = await response.json();
      if (!response.ok) { result.textContent = data.message || `Error HTTP ${response.status}`; return; }
      result.textContent = 'Compra guardada. Abriendo detalle...';
      location.assign('/purchases/details/' + encodeURIComponent(data.globalId));
    } catch (_) {
      result.textContent = 'No se pudo confirmar la compra. Mantén esta página abierta para reintentar con el mismo identificador.';
    } finally { busy = false; saveButton.disabled = false; }
  });
})();
