/* POS workspace derived from Flutter PosScreen: catalog, cart and payment flow.
   It remains an MVC client: commands go only to the local MVC /checkout route. */
(() => {
  'use strict';
  const money = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' });
  const create = (tag, text, className) => { const node = document.createElement(tag); if (text !== undefined) node.textContent = text; if (className) node.className = className; return node; };
  const button = (text, onClick, className = 'secondary') => { const node = create('button', text, className); node.type = 'button'; node.addEventListener('click', onClick); return node; };
  const cents = value => Math.round(Number(value) * 100);
  const printReceipt = (target, result, payments, changeCents) => {
    if (!target) return false;
    const doc = target.document;
    doc.title = `Ticket ${result.folio || ''}`;
    const style = doc.createElement('style');
    style.textContent = 'body{font:14px Arial,sans-serif;margin:24px;max-width:360px}h1{font-size:20px;margin:0 0 8px}p{margin:5px 0}.total{font-size:18px;font-weight:bold;margin-top:14px;border-top:1px dashed #444;padding-top:10px}';
    doc.head.append(style);
    const title = doc.createElement('h1'); title.textContent = 'POSFlutter · Ticket de venta';
    const folio = doc.createElement('p'); folio.textContent = `Folio: ${result.folio || 'Sin folio'}`;
    const date = doc.createElement('p'); date.textContent = `Fecha: ${result.saleDateTime ? new Date(result.saleDateTime).toLocaleString('es-MX') : new Date().toLocaleString('es-MX')}`;
    const total = doc.createElement('p'); total.className = 'total'; total.textContent = `Total: ${money.format((Number(result.totalCents) || 0) / 100)}`;
    doc.body.append(title, folio, date);
    payments.forEach(payment => { const line = doc.createElement('p'); line.textContent = `${payment.method}: ${money.format(payment.amountCents / 100)}`; doc.body.append(line); });
    if (changeCents > 0) { const change = doc.createElement('p'); change.textContent = `Cambio: ${money.format(changeCents / 100)}`; doc.body.append(change); }
    doc.body.append(total);
    target.focus(); target.print();
    return true;
  };

  function renderPos() {
    const content = document.getElementById('content');
    const status = document.getElementById('status');
    const title = document.getElementById('page-title');
    if (!content || !status || !title) return;
    title.textContent = 'Nueva venta';
    content.replaceChildren();
    const cart = new Map();
    let catalog = [];
    let paymentMode = 'Cash';
    let checkoutAttemptKey = null;
    const invalidateCheckoutAttempt = () => { checkoutAttemptKey = null; };
    const layout = create('section', undefined, 'tablet-pos');
    const header = create('header', undefined, 'pos-operational-header');
    header.append(create('span', 'Caja y operación central', 'status-chip warning'), create('span', 'Punto de venta', 'pos-context'));
    const catalogPanel = create('section', undefined, 'tablet-card catalog-panel');
    const cartPanel = create('section', undefined, 'tablet-card cart-panel');
    const catalogTitle = create('h2', 'Productos');
    const hint = create('p', 'Busca por nombre, código/SKU o código de barras', 'muted');
    const search = create('input');
    search.type = 'search'; search.placeholder = 'Buscar productos'; search.autofocus = true;
    search.setAttribute('aria-label', 'Buscar productos');
    const products = create('div', undefined, 'tablet-product-grid');
    catalogPanel.append(catalogTitle, hint, search, products);
    layout.append(header, catalogPanel, cartPanel);
    content.append(layout);

    const drawProducts = () => {
      products.replaceChildren();
      const query = search.value.trim().toLocaleLowerCase('es-MX');
      const rows = catalog.filter(p => `${p.name || ''} ${p.code || ''} ${p.barcode || ''}`.toLocaleLowerCase('es-MX').includes(query));
      if (!rows.length) { products.append(create('p', 'No hay productos que coincidan con la búsqueda.', 'muted')); return; }
      rows.slice(0, 100).forEach(product => {
        const card = create('article', undefined, 'tablet-product-card');
        const stock = Number(product.availableQuantity || 0);
        const available = stock > 0;
        card.append(create('strong', product.name || 'Sin nombre'), create('small', `${product.code || product.barcode || 'Sin código'} · ${product.categoryName || 'Sin categoría'}`), create('b', money.format((Number(product.salePriceCents) || 0) / 100)), create('span', available ? `${stock} disponibles` : 'Agotado', available ? 'stock-chip' : 'stock-chip out'));
        const add = button('Agregar', () => { invalidateCheckoutAttempt(); const prior = cart.get(product.globalId); cart.set(product.globalId, { product, quantity: (prior?.quantity || 0) + 1 }); drawCart(); }, 'primary');
        add.setAttribute('aria-label', `Agregar ${product.name || 'producto'}`);
        // La disponibilidad mostrada es una instantánea: el checkout del servidor
        // conserva la validación autoritativa para evitar rechazos por datos obsoletos.
        add.title = available ? 'Agregar al carrito' : 'Sin existencia en la última consulta; el servidor validará al cobrar.';
        card.append(add); products.append(card);
      });
    };

    const quoteFromCart = async (entries, onMessage) => {
  const printable = window.open('', '_blank');
  const csrf = document.querySelector('meta[name="pos-csrf"]')?.content;
  if (!csrf) throw Error('Token de seguridad no disponible; actualiza la pÃ¡gina.');
  const lines = entries.map(x => ({ productGlobalId: x.product.globalId, quantity: x.quantity }));
  if (!lines.length || lines.some(x => !x.productGlobalId || !Number.isInteger(x.quantity) || x.quantity < 1)) throw Error('Carrito invÃ¡lido.');
  const response = await fetch('/quote/calculate', { method: 'POST', credentials: 'same-origin', cache: 'no-store', headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf }, body: JSON.stringify({ lines }) });
  if (response.status === 401) { location.assign('/Home/Login'); return; }
  const data = await response.json();
  if (!response.ok) throw Error(data.message || `CotizaciÃ³n no disponible (HTTP ${response.status}).`);
  if (!Array.isArray(data.lines) || !Number.isSafeInteger(data.totalCents)) throw Error('Respuesta de cotizaciÃ³n invÃ¡lida.');
  const expected = entries.reduce((sum, x) => sum + (Number(x.product.salePriceCents) || 0) * x.quantity, 0);
  const changed = expected !== data.totalCents;
  if (!printable) { onMessage('CotizaciÃ³n validada. Total: ' + new Intl.NumberFormat('es-MX', {style:'currency',currency:'MXN'}).format(data.totalCents/100) + (changed ? ' (precios actualizados).' : '.') + ' Habilita ventanas emergentes para imprimir.'); return; }
  const doc = printable.document;
  const style = doc.createElement('style'); style.textContent = 'body{font:16px Arial,sans-serif;margin:32px}table{width:100%;border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid #ccc;text-align:left}h1{font-size:22px}';
  doc.head.append(style); doc.title = 'CotizaciÃ³n POSFlutter';
  const h = doc.createElement('h1'); h.textContent = 'CotizaciÃ³n Â· Las Ãguilas'; doc.body.append(h);
  const note = doc.createElement('p'); note.textContent = 'Precios validados en servidor. No es una venta ni reserva inventario.'; doc.body.append(note);
  const table = doc.createElement('table'); const head = doc.createElement('tr');
  ['Producto','Cantidad','Precio','Subtotal'].forEach(s => {const th=doc.createElement('th');th.textContent=s;head.append(th);}); table.append(head);
  const money = n => new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN'}).format(n/100);
  data.lines.forEach(line => {const tr=doc.createElement('tr');[line.name,line.quantity,money(line.unitPriceCents),money(line.subtotalCents)].forEach(s=>{const td=doc.createElement('td');td.textContent=String(s);tr.append(td);});table.append(tr);}); doc.body.append(table);
  const total = doc.createElement('h2'); total.textContent = 'Total: ' + money(data.totalCents);doc.body.append(total);
  if (changed) {const warning=doc.createElement('p');warning.textContent='Los precios centrales difieren del carrito. Actualiza el catÃ¡logo antes de cobrar.';doc.body.append(warning);}
  printable.focus(); printable.print();
  onMessage(changed ? 'CotizaciÃ³n generada. Precios cambiaron; actualiza el catÃ¡logo antes de cobrar.' : 'CotizaciÃ³n generada sin registrar venta.');
};
const drawCart = () => {
      cartPanel.replaceChildren(create('h2', 'Carrito'));
      const lines = [...cart.values()];
      if (!lines.length) { cartPanel.append(create('p', 'Agrega productos para iniciar la venta.', 'pos-empty')); return; }
      const quantity = lines.reduce((sum, line) => sum + line.quantity, 0);
      const total = lines.reduce((sum, line) => sum + (Number(line.product.salePriceCents) || 0) * line.quantity, 0);
      cartPanel.append(create('span', `${quantity} artículos`, 'cart-count'));
      const lineList = create('div', undefined, 'tablet-cart-lines');
      lines.forEach(({ product, quantity: lineQuantity }) => {
        const row = create('article', undefined, 'tablet-cart-line');
        const controls = create('div', undefined, 'quantity-controls');
        controls.append(button('−', () => { invalidateCheckoutAttempt(); if (lineQuantity === 1) cart.delete(product.globalId); else cart.set(product.globalId, { product, quantity: lineQuantity - 1 }); drawCart(); }, 'icon-button'), create('b', String(lineQuantity)), button('+', () => { invalidateCheckoutAttempt(); cart.set(product.globalId, { product, quantity: lineQuantity + 1 }); drawCart(); }, 'icon-button'));
        row.append(create('span', product.name || 'Producto'), controls, create('strong', money.format(((Number(product.salePriceCents) || 0) * lineQuantity) / 100)), button('×', () => { invalidateCheckoutAttempt(); cart.delete(product.globalId); drawCart(); }, 'icon-button'));
        lineList.append(row);
      });
      cartPanel.append(lineList, create('h2', `Total: ${money.format(total / 100)}`, 'cart-total'));
      const payment = create('section', undefined, 'tablet-payment');
      payment.append(create('h3', 'Forma de pago'));
      const choices = create('div', undefined, 'payment-choices');
      const mixed = create('div', undefined, 'mixed-payment-inputs');
      const inputByMethod = {};
      [['Cash', '▣ Efectivo'], ['Card', '▤ Tarjeta'], ['Transfer', '⇄ Transferencia'], ['Mixed', '⇆ Mixto']].forEach(([mode, label]) => choices.append(button(label, () => { invalidateCheckoutAttempt(); paymentMode = mode; drawCart(); }, paymentMode === mode ? 'payment-choice selected' : 'payment-choice')));
      [['Cash', 'Efectivo'], ['Card', 'Tarjeta'], ['Transfer', 'Transferencia']].forEach(([method, label]) => { const input = create('input'); input.type = 'number'; input.min = '0'; input.step = '0.01'; input.placeholder = label; input.setAttribute('aria-label', `${label} pago mixto`); inputByMethod[method] = input; mixed.append(input); });
      const received = create('input'); received.type = 'number'; received.min = '0'; received.step = '0.01'; received.placeholder = 'Efectivo recibido'; received.setAttribute('aria-label', 'Efectivo recibido');
      const change = create('p', undefined, 'muted');
      const refreshTender = () => { const cashDue = paymentMode === 'Mixed' ? cents(inputByMethod.Cash.value || 0) : paymentMode === 'Cash' ? total : 0; const hasCash = cashDue > 0 || paymentMode === 'Cash'; received.hidden = !hasCash; mixed.hidden = paymentMode !== 'Mixed'; change.hidden = !hasCash; if (hasCash) { const tendered = cents(received.value || 0); change.textContent = tendered >= cashDue ? `Cambio: ${money.format((tendered - cashDue) / 100)}` : `Efectivo mínimo: ${money.format(cashDue / 100)}`; } };
      [received, ...Object.values(inputByMethod)].forEach(input => input.addEventListener('input', () => { invalidateCheckoutAttempt(); refreshTender(); }));
      payment.append(choices, mixed, received, change); cartPanel.append(payment);
      const checkout = async () => {
        const payments = paymentMode === 'Mixed' ? Object.entries(inputByMethod).map(([method, input]) => ({ method, amountCents: cents(input.value || 0) })).filter(x => x.amountCents > 0) : [{ method: paymentMode, amountCents: total }];
        const paymentTotal = payments.reduce((sum, value) => sum + value.amountCents, 0);
        const cashDue = payments.filter(x => x.method === 'Cash').reduce((sum, value) => sum + value.amountCents, 0);
        const tendered = cashDue ? cents(received.value || 0) : null;
        if (paymentTotal !== total) { status.textContent = 'El pago asignado debe coincidir exactamente con el total.'; return; }
        if (cashDue && (!Number.isSafeInteger(tendered) || tendered < cashDue)) { status.textContent = 'El efectivo recibido no cubre el importe en efectivo.'; received.focus(); return; }
        const csrf = document.querySelector('meta[name="pos-csrf"]')?.content;
        if (!csrf) { status.textContent = 'No se encontró protección antiforgery. Recarga la sesión.'; return; }
        const printable = window.open('', '_blank');
        const submit = cartPanel.querySelector('.pos-checkout'); submit.disabled = true; status.textContent = 'Confirmando venta en SQL Server…';
        try {
          const response = await fetch('/checkout', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf }, body: JSON.stringify({ idempotencyKey: checkoutAttemptKey ||= crypto.randomUUID(), lines: lines.map(line => ({ productGlobalId: line.product.globalId, quantity: line.quantity })), payments, receivedCashCents: tendered }) });
          if (response.status === 401) { printable?.close(); location.assign('/Home/Login'); return; }
          const result = await response.json(); if (!response.ok) throw Error(result.message || `HTTP ${response.status}`);
          const changeCents = cashDue ? Math.max(0, tendered - cashDue) : 0;
          checkoutAttemptKey = null; cart.clear(); drawCart(); status.textContent = `Venta ${result.folio} confirmada por servidor.`;
          const receipt = create('section', undefined, 'sale-receipt');
          const reprint = button('Reimprimir ticket', () => {
            const retryWindow = window.open('', '_blank');
            try {
              if (!printReceipt(retryWindow, result, payments, changeCents)) throw Error('El navegador bloqueó la ventana de impresión.');
              status.textContent = `Ticket ${result.folio} enviado a impresión.`;
            } catch (printError) {
              retryWindow?.close();
              status.textContent = `Venta ${result.folio} confirmada; no se pudo imprimir: ${printError.message || 'error del navegador'}. Puedes reintentar.`;
            }
          }, 'secondary');
          receipt.append(create('strong', '✓ Venta registrada'), create('span', `${result.folio} · ${money.format(result.totalCents / 100)}`), reprint); cartPanel.prepend(receipt);
          try {
            if (!printReceipt(printable, result, payments, changeCents)) throw Error('El navegador bloqueó la ventana de impresión.');
          } catch (printError) {
            printable?.close();
            status.textContent = `Venta ${result.folio} confirmada por servidor. Ticket disponible para reimpresión; la impresión inicial falló.`;
          }
        } catch (error) { printable?.close(); status.textContent = error.message || 'No se pudo confirmar la venta.'; submit.disabled = false; }
      };
      cartPanel.append(button(`Cotizar e imprimir`, async () => { try { await quoteFromCart([...cart.values()], message => { status.textContent = message; }); } catch (error) { status.textContent = error.message; } }, 'secondary'), button(`Cobrar ${money.format(total / 100)}`, checkout, 'primary pos-checkout'), button('Vaciar venta', () => { invalidateCheckoutAttempt(); cart.clear(); drawCart(); }, 'secondary'));
      refreshTender();
    };
    search.addEventListener('input', drawProducts);
    status.textContent = 'Consultando catálogo central…';
    fetch('/data/products', { credentials: 'same-origin', cache: 'no-store' }).then(async response => { if (response.status === 401) { location.assign('/Home/Login'); return null; } if (!response.ok) throw Error(`El catálogo respondió HTTP ${response.status}`); return response.json(); }).then(data => { if (!data) return; catalog = Array.isArray(data.items) ? data.items.filter(p => p.active !== false) : []; drawProducts(); drawCart(); status.textContent = 'Catálogo central listo para vender.'; }).catch(error => { products.append(create('p', error.message, 'error')); status.textContent = 'No se pudo cargar el catálogo.'; });
  }

  document.addEventListener('click', event => {
    const trigger = event.target.closest('#nav button[data-view="pos"]');
    if (!trigger) return;
    event.preventDefault(); event.stopImmediatePropagation();
    document.querySelectorAll('#nav button').forEach(button => button.classList.toggle('active', button === trigger));
    renderPos();
  }, true);
})();
