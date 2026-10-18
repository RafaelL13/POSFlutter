(() => {
  'use strict';
  const status = document.getElementById('cash-audit-status');
  const root = document.getElementById('cash-audit-content');
  const button = document.getElementById('cash-audit-refresh');
  if (!root || !status || !button) return;
  const pesos = value => (Number(value || 0) / 100).toLocaleString('es-MX', { style: 'currency', currency: 'MXN' });
  function element(parent, type, value) {
    const e = document.createElement(type);
    e.textContent = String(value ?? '');
    parent.appendChild(e);
    return e;
  }
  async function refresh() {
    root.replaceChildren();
    status.textContent = 'Consultando datos del servidor...';
    button.disabled = true;
    try {
      const response = await fetch('/cash-operations/sales-audit', { credentials: 'same-origin', cache: 'no-store', headers: { 'Accept': 'application/json' } });
      if (response.status === 409) {
        status.textContent = 'Se requiere exactamente una caja abierta para el usuario y dispositivo actuales.';
        return;
      }
      if (response.status === 401 || response.status === 403) {
        status.textContent = 'SesiÃ³n vencida o usuario sin autorizaciÃ³n.';
        return;
      }
      if (!response.ok) throw new Error('HTTP ' + response.status);
      const data = await response.json();
      if (data.closeAuthorized !== false || data.attribution !== 'PROVISIONAL_TIME_DEVICE_USER') throw new Error('Contrato de auditorÃ­a no esperado');
      status.textContent = 'AuditorÃ­a consultada. No habilita el cierre de caja.';
      const table = document.createElement('table');
      const tbody = document.createElement('tbody');
      [
        ['Caja', data.cashSessionGlobalId],
        ['Saldo inicial', pesos(data.openingBalanceCents)],
        ['Ventas identificadas', data.matchedSaleCount],
        ['Cobros en efectivo identificados', pesos(data.matchedCashPaymentsCents)],
        ['Cobros de otros operadores', pesos(data.otherDeviceCashPaymentsCents)],
        ['Ventas sin pago Cash documentado', data.salesMissingCashPaymentCount],
        ['Movimientos manuales', data.movementCount],
        ['Neto de movimientos', pesos(data.manualDeltaCents)],
        ['Gastos en efectivo', pesos(data.cashExpenseCents)],
        ['Saldo esperado provisional', pesos(data.provisionalExpectedCents)],
        ['Cierre habilitado', 'No. Requiere conciliaciÃ³n definitiva']
      ].forEach(([name, value]) => {
        const tr = document.createElement('tr');
        element(tr, 'th', name);
        element(tr, 'td', value);
        tbody.appendChild(tr);
      });
      table.appendChild(tbody); root.appendChild(table);
      element(root, 'h2', 'Advertencias de conciliaciÃ³n');
      const ul = document.createElement('ul');
      const warnings = Array.isArray(data.warnings) ? data.warnings : [];
      for (const warning of warnings) element(ul, 'li', warning);
      if (!warnings.length) element(ul, 'li', 'La vinculaciÃ³n sigue siendo provisional.');
      root.appendChild(ul);
    } catch (error) {
      status.textContent = 'La auditorÃ­a no se pudo completar: ' + String(error.message || error);
    } finally { button.disabled = false; }
  }
  button.addEventListener('click', refresh);
  refresh();
})();