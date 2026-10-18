(() => {
  'use strict';
  const views = {
    dashboard: ['dashboard','Resumen'], products: ['products','Productos'],
    inventory: ['inventory','Inventario'], lots: ['lots','Lotes FIFO'],
    sales: ['sales','Ventas'], purchases: ['purchases','Compras'],
    cash: ['cash','Caja'], expenses: ['expenses','Gastos'],
    devices: ['devices','Tablets'], branches: ['branches','Sucursales'],
    users: ['users','Usuarios']
  };
  const nav = document.getElementById('nav');
  const content = document.getElementById('content');
  const status = document.getElementById('status');
  if (!nav || !content || !status) return;
  let active = null;
  const fmt = v => v === null || v === undefined ? 'â€”' :
    typeof v === 'object' ? JSON.stringify(v) : String(v);
  const money = v => (Number(v) / 100).toLocaleString('es-MX',{style:'currency',currency:'MXN'});
  const pretty = k => ({globalId:'Identificador',productGlobalId:'Producto',folio:'Folio',
    totalCents:'Total',saleDateTime:'Fecha',stock:'Existencia',name:'Nombre',
    status:'Estado',availableQuantity:'Disponible',initialQuantity:'Inicial',
    salePriceCents:'Precio',grossProfitCents:'Utilidad',openingBalanceCents:'Fondo inicial'})[k] || k;
  function cell(tr,tag,text){const el=document.createElement(tag);el.textContent=text;tr.appendChild(el);}
  function table(rows){
    if(!rows.length){content.textContent='Sin registros disponibles para esta cuenta y sus permisos.';return;}
    const keys=Object.keys(rows[0]).slice(0,12);
    const wrap=document.createElement('div');wrap.style.overflowX='auto';
    const t=document.createElement('table'); t.className='p054-table';
    const head=document.createElement('thead'),hr=document.createElement('tr');
    keys.forEach(k=>cell(hr,'th',pretty(k)));head.appendChild(hr);t.appendChild(head);
    const body=document.createElement('tbody');
    rows.slice(0,500).forEach(r=>{const tr=document.createElement('tr');keys.forEach(k=>cell(tr,'td',k.endsWith('Cents')&&Number.isFinite(Number(r[k]))?money(r[k]):fmt(r[k])));body.appendChild(tr);});
    t.appendChild(body);wrap.appendChild(t);content.replaceChildren(wrap);
  }
  async function load(key){
    const entry=views[key];if(!entry)return;active=key;
    document.getElementById('page-title').textContent=entry[1];
    status.textContent='Consultando SQL Serverâ€¦';
    try{
      const response=await fetch('/data/'+entry[0],{credentials:'same-origin',headers:{Accept:'application/json'},cache:'no-store'});
      if(response.status===401){location.href='/Home/Login';return;}
      if(response.status===403){content.textContent='Sin autorizaciÃ³n para consultar este mÃ³dulo.';status.textContent='Acceso restringido';return;}
      if(!response.ok)throw Error('HTTP '+response.status);
      const result=await response.json();let rows=result.items;
      if(!Array.isArray(rows))rows=[rows];
      table(rows);status.textContent=rows.length+' registro(s) consultados';
    }catch(e){status.textContent='No se pudo consultar: '+e.message;content.textContent='Verifica conexiÃ³n y permisos.';}
  }
  nav.addEventListener('click',e=>{
    const b=e.target.closest('button[data-view]');if(!b)return;
    const key=b.dataset.view;if(!views[key])return;
    // Use capture phase to prevent the previous preliminary JS from replacing real data.
    e.preventDefault();e.stopImmediatePropagation();
    nav.querySelectorAll('button').forEach(x=>x.classList.toggle('active',x===b));
    load(key);
  },true);
  const reload=document.getElementById('reload');
  if(reload)reload.addEventListener('click',e=>{if(!active)return;e.preventDefault();e.stopImmediatePropagation();load(active);},true);
  const css=document.createElement('style');css.textContent='.p054-table{width:100%;border-collapse:collapse;font-size:0.9rem}.p054-table th,.p054-table td{padding:0.7rem;border-bottom:1px solid #7775;text-align:left;white-space:nowrap}.p054-table th{font-weight:700}';document.head.appendChild(css);
})();