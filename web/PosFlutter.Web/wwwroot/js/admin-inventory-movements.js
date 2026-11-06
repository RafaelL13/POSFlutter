(() => {
  'use strict';
  const rows = document.getElementById('movementRows');
  const status = document.getElementById('movementStatus');
  const more = document.getElementById('moreMovements');
  const button = document.getElementById('loadMovements');
  const product = document.getElementById('productId');
  const adjustmentForm = document.getElementById('inventoryAdjustmentForm');
  const adjustmentProduct = document.getElementById('adjustmentProduct');
  const adjustmentType = document.getElementById('adjustmentType');
  const adjustmentQuantity = document.getElementById('adjustmentQuantity');
  const adjustmentCost = document.getElementById('adjustmentCost');
  const adjustmentCostGroup = document.getElementById('adjustmentCostGroup');
  const adjustmentReason = document.getElementById('adjustmentReason');
  const previewAdjustment = document.getElementById('previewAdjustment');
  const commitAdjustment = document.getElementById('commitAdjustment');
  const adjustmentStatus = document.getElementById('adjustmentStatus');
  const csrf = document.querySelector('input[name="__RequestVerificationToken"]')?.value || '';
  let page = 1;
  let busy = false;
  let adjustmentKey = null;
  let approvedPayload = null;
  const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const td = (tr, value) => {
    const cell = document.createElement('td');
    cell.textContent = value == null ? '' : String(value);
    tr.appendChild(cell);
  };
  async function load(reset) {
    if (busy) return;
    const id = product.value.trim();
    if (id && !guid.test(id)) { status.textContent = 'El identificador de producto no es válido.'; return; }
    busy = true;
    button.disabled = true;
    more.disabled = true;
    status.textContent = 'Consultando movimientos…';
    const nextPage = reset ? 1 : page;
    const query = new URLSearchParams({ page: String(nextPage), pageSize: '50' });
    if (id) query.set('productGlobalId', id);
    try {
      const response = await fetch(`/admin/inventory/movements/data?${query}`, {
        credentials: 'same-origin', headers: { Accept: 'application/json' }
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!Array.isArray(data.items)) throw new Error('Respuesta inválida');
      if (reset) rows.replaceChildren();
      for (const item of data.items) {
        const tr = document.createElement('tr');
        td(tr, item.movementDate ? new Date(item.movementDate).toLocaleString('es-MX') : '');
        td(tr, item.type);
        td(tr, item.productGlobalId);
        td(tr, item.quantityDelta);
        td(tr, item.previousStock);
        td(tr, item.newStock);
        td(tr, item.referenceGlobalId);
        rows.appendChild(tr);
      }
      page = nextPage + 1;
      more.hidden = !data.hasMore;
      status.textContent = `${rows.children.length} movimientos cargados.`;
    } catch (error) {
      status.textContent = `No se pudo consultar el historial: ${error.message}`;
      if (reset) more.hidden = true;
    } finally { busy = false; button.disabled = false; more.disabled = false; }
  }
  button.addEventListener('click', () => load(true));
  more.addEventListener('click', () => load(false));

  const makeId = () => window.crypto?.randomUUID ? window.crypto.randomUUID() :
    'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
      const n = window.crypto?.getRandomValues ? window.crypto.getRandomValues(new Uint8Array(1))[0] : Math.floor(Math.random() * 256);
      return (c === 'x' ? n & 15 : (n & 3) | 8).toString(16);
    });
  const adjustmentPayload = () => {
    const quantity = Number(adjustmentQuantity.value);
    const isIn = adjustmentType.value === 'in';
    const cost = adjustmentCost.value.trim();
    if (!guid.test(adjustmentProduct.value) || !Number.isInteger(quantity) || quantity < 1 || quantity > 1000000 ||
      adjustmentReason.value.trim().length < 5 || adjustmentReason.value.trim().length > 240 ||
      (isIn && (!/^[0-9]+$/.test(cost) || !Number.isSafeInteger(Number(cost))))) return null;
    return { productGlobalId: adjustmentProduct.value, quantityDelta: isIn ? quantity : -quantity,
      reason: adjustmentReason.value.trim(), unitCostCents: isIn ? Number(cost) : null };
  };
  const resetApproval = () => { approvedPayload = null; adjustmentKey = null; commitAdjustment.disabled = true; };
  [adjustmentProduct, adjustmentType, adjustmentQuantity, adjustmentCost, adjustmentReason].forEach(x => x?.addEventListener('input', resetApproval));
  adjustmentType?.addEventListener('change', () => { adjustmentCostGroup.hidden = adjustmentType.value !== 'in'; if (adjustmentType.value !== 'in') adjustmentCost.value = ''; resetApproval(); });
  async function loadAdjustmentProducts() {
    try {
      const response = await fetch('/data/products', { credentials: 'same-origin', headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const payload = await response.json();
      const items = Array.isArray(payload) ? payload : Array.isArray(payload.items) ? payload.items : [];
      adjustmentProduct.replaceChildren(new Option('Selecciona un producto', ''));
      items.forEach(item => {
        if (item?.globalId && item?.active !== false) adjustmentProduct.add(new Option(`${item.name || item.code || 'Producto'}${item.code ? ' · ' + item.code : ''}`, item.globalId));
      });
      if (adjustmentProduct.options.length === 1) adjustmentStatus.textContent = 'No hay productos activos autorizados para la sucursal.';
    } catch (error) { adjustmentProduct.replaceChildren(new Option('No fue posible cargar productos', '')); adjustmentStatus.textContent = `Catálogo no disponible: ${error.message}`; }
  }
  previewAdjustment?.addEventListener('click', async () => {
    const payload = adjustmentPayload();
    if (!payload) { adjustmentStatus.textContent = 'Completa producto, cantidad entera, motivo y costo de entrada válidos.'; return; }
    resetApproval(); previewAdjustment.disabled = true; adjustmentStatus.textContent = 'Validando ajuste…';
    const query = new URLSearchParams({ productGlobalId: payload.productGlobalId, quantityDelta: String(payload.quantityDelta), reason: payload.reason });
    try {
      const response = await fetch(`/admin/inventory/adjustments/preview?${query}`, { credentials: 'same-origin', headers: { Accept: 'application/json' } });
      const result = await response.json().catch(() => ({}));
      if (!response.ok || result.feasible !== true) throw new Error(result.code || `HTTP ${response.status}`);
      approvedPayload = payload; adjustmentKey = makeId(); commitAdjustment.disabled = false;
      adjustmentStatus.textContent = `Validado: existencia actual ${result.currentStock}; proyección ${result.projectedStock}. Confirma para registrar.`;
    } catch (error) { adjustmentStatus.textContent = `Ajuste no autorizado: ${error.message}`; }
    finally { previewAdjustment.disabled = false; }
  });
  adjustmentForm?.addEventListener('submit', async event => {
    event.preventDefault();
    if (!approvedPayload || !adjustmentKey || !csrf) { adjustmentStatus.textContent = 'Valida el ajuste antes de confirmarlo.'; return; }
    commitAdjustment.disabled = true; previewAdjustment.disabled = true; adjustmentStatus.textContent = 'Registrando ajuste transaccional…';
    try {
      const response = await fetch('/admin/inventory/adjustments/commit', { method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'X-CSRF-TOKEN': csrf },
        body: JSON.stringify({ ...approvedPayload, idempotencyKey: adjustmentKey }) });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result.code || `HTTP ${response.status}`);
      adjustmentStatus.textContent = result.replay ? 'Ajuste ya registrado; no se duplicó.' : `Ajuste registrado. Existencia: ${result.previousStock} → ${result.newStock}.`;
      resetApproval(); await load(true);
    } catch (error) { adjustmentStatus.textContent = `No se registró el ajuste: ${error.message}. Puedes reintentar la misma confirmación.`; commitAdjustment.disabled = false; }
    finally { previewAdjustment.disabled = false; }
  });
  loadAdjustmentProducts();
  load(true);
})();
