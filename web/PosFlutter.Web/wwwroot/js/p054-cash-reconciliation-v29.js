(() => {
  "use strict";
  const cashButtonSelector = '#nav [data-view="cash"]';
  const asMoney = cents => (Number(cents || 0) / 100).toLocaleString('es-MX',{style:'currency',currency:'MXN'});
  const add = (parent, tag, value, className) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    element.textContent = value === undefined || value === null ? '' : String(value);
    parent.appendChild(element);
    return element;
  };
  const line = (container, label, value) => {
    const row = add(container,'div','', 'cash-reconciliation-line');
    add(row,'span',label);
    add(row,'strong',value);
  };
  async function render() {
    const root=document.getElementById('content');
    if (!root) return;
    root.replaceChildren();
    add(root,'h2','PreconciliaciÃ³n de caja');
    add(root,'p','Vista previa informativa. No autoriza ni ejecuta cierres.');
    const status=add(root,'p','Consultando caja...');
    try {
      const response=await fetch('/cash-operations/reconciliation-preview',{
        credentials:'same-origin',cache:'no-store',headers:{Accept:'application/json'}
      });
      if(response.status===401 || response.status===403) {
        status.textContent='Acceso no autorizado. Inicia sesiÃ³n con un usuario autorizado.';
        return;
      }
      if(response.status===409) {
        status.textContent='No se puede consultar: se requiere exactamente una caja abierta.';
        return;
      }
      if(!response.ok) throw new Error('HTTP '+response.status);
      const data=await response.json();
      status.textContent='Resultado provisional del servidor central';
      const summary=add(root,'section','', 'cash-reconciliation-summary');
      line(summary,'Saldo inicial',asMoney(data.openingBalanceCents));
      line(summary,'Movimientos manuales',String(data.manualMovementCount ?? 0));
      line(summary,'VariaciÃ³n manual',asMoney(data.manualDeltaCents));
      line(summary,'Cobros coincidentes',asMoney(data.matchedCashSalesCents));
      line(summary,'Saldo esperado provisional',asMoney(data.provisionalExpectedCents));
      const warnings=Array.isArray(data.warnings)?data.warnings:[];
      add(root,'h3','Advertencias y validaciones');
      const list=add(root,'ul','');
      if(!warnings.length){add(list,'li','No se proporcionaron advertencias adicionales.');}
      for(const warning of warnings) {
        if(typeof warning==='string') add(list,'li',warning);
        else add(list,'li',JSON.stringify(warning));
      }
      const authorized=(data.closeAuthorized===true && data.requiresReview===false);
      add(root,'p',authorized ? 'El servidor reporta condiciones de cierre revisadas; no se ejecutarÃ¡ ningÃºn cierre desde esta pantalla.'
          : 'CIERRE BLOQUEADO: esta vista no autoriza cierres de caja.', 'cash-reconciliation-status');
      add(root,'p',data.explanation || 'Importes sujetos a revisiÃ³n de ventas, pagos y gastos.');
    } catch(error){status.textContent='No se pudo obtener la preconciliaciÃ³n: '+error.message;}
  }
  document.addEventListener('click',event => {
    const btn=event.target.closest(cashButtonSelector);
    if(!btn) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    document.querySelectorAll('#nav button').forEach(b=>b.classList.toggle('active',b===btn));
    const title=document.getElementById('page-title');if(title)title.textContent='Caja';
    const desc=document.getElementById('page-desc');if(desc)desc.textContent='PreconciliaciÃ³n de efectivo';
    render();
  },true);
})();