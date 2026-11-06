(() => {
 'use strict';
 const nav=document.getElementById('nav'); if(!nav)return;
 const shell=document.querySelector('.tablet-shell'),drawerToggle=document.getElementById('drawer-toggle'),drawerScrim=document.querySelector('.drawer-scrim');
 const setDrawer=open=>{if(!shell)return;shell.classList.toggle('drawer-open',open);drawerToggle?.setAttribute('aria-expanded',String(open));if(drawerScrim)drawerScrim.hidden=!open;};
 drawerToggle?.addEventListener('click',()=>setDrawer(!shell?.classList.contains('drawer-open')));
 drawerScrim?.addEventListener('click',()=>setDrawer(false));
 document.addEventListener('keydown',e=>{if(e.key==='Escape'&&shell?.classList.contains('drawer-open')){setDrawer(false);drawerToggle?.focus();}});
 const content=document.getElementById('content'),status=document.getElementById('status'),title=document.getElementById('page-title'),workspace=document.querySelector('.workspace');
 const labels={dashboard:'Resumen',products:'Productos',categories:'Categorías',inventory:'Inventario',lots:'Lotes',sales:'Ventas',purchases:'Compras',cash:'Caja',expenses:'Gastos',devices:'Monitoreo de tablets',branches:'Sucursales',users:'Usuarios',report:'Reportes',pos:'Punto de venta'};
 const reportKinds={'summary':'Resumen','sales':'Ventas','products':'Productos','products/low-performance':'Bajo rendimiento','categories':'Categorías','users':'Vendedores','purchases':'Compras','suppliers':'Proveedores','inventory':'Inventario','expenses':'Gastos','cash':'Caja','payment-methods':'Métodos de pago','cancellations':'Cancelaciones','trends/products':'Tendencias'};
 const money=new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN'});
 const names={globalId:'Identificador',productGlobalId:'Producto',branchGlobalId:'Sucursal',supplierGlobalId:'Proveedor',name:'Nombre',code:'Código',barcode:'Código de barras',presentation:'Presentación',salePriceCents:'Precio venta',unitCostCents:'Costo unitario',inventoryValueCents:'Valor inventario',fifoCostCents:'Costo FIFO',grossProfitCents:'Utilidad',availableQuantity:'Existencia',initialQuantity:'Cantidad inicial',totalCents:'Total',lastSyncAt:'Última sincronización',lastCommunicationAt:'Última comunicación',mode:'Modo',active:'Activo',status:'Estado',username:'Usuario',role:'Perfil',purchaseDate:'Fecha compra',saleDateTime:'Fecha venta',entryDate:'Fecha entrada',minimumStock:'Mínimo',serverVersion:'Versión'};
 let current='dashboard', sequence=0, catalog=[], cart=new Map(), latestRows=[], checkoutAttemptKey=null, unresolvedCheckoutActive=false;
 let monitorInterval=null, monitorBusy=false;
 const el=(tag,txt,cls)=>{const n=document.createElement(tag);if(txt!==undefined)n.textContent=String(txt??'—');if(cls)n.className=cls;return n;};
 const btn=(caption,fn,cls='secondary')=>{const b=el('button',caption,cls);b.type='button';b.addEventListener('click',fn);return b;};
 const api=async(path)=>{const r=await fetch('/data/'+path,{credentials:'same-origin',cache:'no-store'});if(r.status===401){location.assign('/Home/Login');throw Error('Sesión vencida');}if(!r.ok)throw Error(r.status===403?'Acceso denegado por permisos.':'La consulta respondió HTTP '+r.status);return r.json();};
 const items=data=>Array.isArray(data)?data:Array.isArray(data?.items)?data.items:[];
 const fmt=(key,value)=>{
  if(value===null||value===undefined)return '—';
  if(key.endsWith('Cents')&&typeof value==='number')return money.format(value/100);
  if(typeof value==='boolean')return value?'Sí':'No';
  if(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T/.test(value)){const date=new Date(value);if(!Number.isNaN(date.getTime()))return date.toLocaleString('es-MX');}
  if(typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(value))return value.slice(0,8)+'…';
  if(typeof value==='object')return JSON.stringify(value);
  return String(value);
 };
 function emptyState(kind){const panel=el('section',undefined,'tablet-empty-state');const labels={categories:'No hay categorías registradas.',inventory:'No hay existencias registradas.',products:'No hay productos disponibles.'};panel.append(el('h2',labels[kind]||'No hay registros disponibles.'),el('p','El estado mostrado procede del servidor central.','muted'));return panel;}
 function table(rows,limit=200,onRow=null,kind=''){const panel=el('div',undefined,'panel');if(!rows.length)return kind?emptyState(kind):(panel.append(el('p','No hay registros disponibles.','muted')),panel);
  const keys=Object.keys(rows[0]).filter(k=>typeof rows[0][k]!=='object').slice(0,16),t=el('table',undefined,'table'),head=el('thead'),tr=el('tr');keys.forEach(k=>tr.append(el('th',names[k]||k)));head.append(tr);t.append(head);
  const body=el('tbody');rows.slice(0,limit).forEach(r=>{const line=el('tr');if(onRow){line.tabIndex=0;line.className='selectable-row';line.addEventListener('click',()=>onRow(r));line.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();onRow(r);}});}keys.forEach(k=>{const cell=el('td',fmt(k,r[k]));if(typeof r[k]==='string'&&r[k].length>20)cell.title=r[k];line.append(cell);});body.append(line);});t.append(body);panel.append(t);if(rows.length>limit)panel.append(el('p',`Mostrando ${limit} de ${rows.length} registros. Refina tu consulta.`, 'muted'));return panel;
 }
 function saleDetails(sale){const panel=el('section',undefined,'panel');panel.append(el('h2','Detalle de venta confirmado por servidor'),btn('Cerrar detalle',()=>panel.remove()));
  if(!sale||typeof sale!=='object'){panel.append(el('p','Respuesta inválida','error'));return panel;}
  const fields=Object.entries(sale).filter(([,v])=>v!==null&&typeof v!=='object');panel.append(summary(Object.fromEntries(fields)));
  for(const [key,value] of Object.entries(sale))if(Array.isArray(value))panel.append(el('h3',key),table(value));return panel;}
 async function openSale(row,target,seq){const id=row.globalId;if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(String(id||''))){status.textContent='Venta sin identificador válido';return;}
  const existing=document.getElementById('sale-detail');if(existing)existing.remove();
  try{const data=await api('sale/'+encodeURIComponent(id));if(seq!==sequence)return;const panel=saleDetails(data);panel.id='sale-detail';target.prepend(panel);status.textContent='Detalle de venta consultado en servidor';}
  catch(e){if(seq!==sequence)return;status.textContent=e.message;}}
 function tabletRows(rows,kind){if(!rows.length)return emptyState(kind);const panel=el('section',undefined,'tablet-record-list');rows.slice(0,200).forEach(row=>{const card=el('article',undefined,'tablet-record-card');const heading=kind==='inventory'?(row.productName||row.name||row.code||'Existencia recibida del servidor'):(row.name||row.code||row.globalId);card.append(el('strong',heading));const fields=kind==='inventory'?['code','availableQuantity','inventoryValueCents','lastMovementAt']:['code','salePriceCents','availableQuantity','status'];const details=el('div',undefined,'tablet-record-details');fields.filter(key=>row[key]!==undefined&&row[key]!==null).forEach(key=>details.append(el('span',(names[key]||key)+': '+fmt(key,row[key]))));card.append(details);panel.append(card);});return panel;}
 function summary(data){const grid=el('div',undefined,'grid');Object.entries(data).filter(([,v])=>['string','number','boolean'].includes(typeof v)).slice(0,20).forEach(([k,v])=>{const a=el('div',undefined,'stat');a.append(el('small',names[k]||k),el('b',fmt(k,v)));grid.append(a);});return grid;}
 function metricCard(label,value){const card=el('article',undefined,'tablet-metric-card');card.append(el('span',label,'tablet-metric-label'),el('strong',value,'tablet-metric-value'));return card;}
 function moduleHeader(heading,subtitle,actionLabel,action){const header=el('header',undefined,'tablet-module-header'),copy=el('div');copy.append(el('h2',heading),el('p',subtitle));header.append(copy);if(actionLabel){const actionButton=btn(actionLabel,action,'primary tablet-primary-action');header.append(actionButton);}return header;}
 function dashboard(data){const panel=el('section',undefined,'tablet-dashboard-page'),source=data&&typeof data==='object'?data:{};panel.append(el('h2','Hola, operación central','tablet-welcome'),el('p','Principal · Administrador','tablet-role'));const sale=btn('Nueva venta',()=>show('pos'),'primary tablet-sale-action');panel.append(sale);const grid=el('section',undefined,'tablet-dashboard');const cards=[['Ventas de hoy',fmt('salesCents',source.salesCents??0)],['Operaciones',source.operations??0],['Caja',source.cashStatus||'Sin información'],['Inventario disponible',source.inventoryUnits!==undefined?String(source.inventoryUnits)+' unidades':'Sin información'],['Utilidad bruta',fmt('grossProfitCents',source.grossProfitCents??source.resultCents??0)],['Margen',source.marginBasisPoints!==undefined?(Number(source.marginBasisPoints)/100).toFixed(2)+' %':'Sin información'],['Gastos de hoy',fmt('expensesCents',source.expensesCents??0)],['Inventario valorizado',fmt('inventoryValueCents',source.inventoryValueCents??0)]];cards.forEach(([label,value])=>grid.append(metricCard(label,value)));panel.append(grid,el('h2','Accesos rápidos','tablet-section-title'));const actions=el('section',undefined,'tablet-quick-actions');[['Nueva venta','pos'],['Compras','purchases'],['Caja','cash'],['Inventario','inventory'],['Productos','products'],['Reportes','report']].forEach(([label,view])=>actions.append(btn(label,()=>show(view),'tablet-quick-action')));panel.append(actions);return panel;}
 function notice(title,message,links=[]){const card=el('section',undefined,'tablet-notice'),copy=el('div');copy.append(el('strong',title),el('p',message));card.append(el('span','ⓘ','tablet-notice-icon'),copy);if(links.length){const actions=el('div',undefined,'tablet-notice-actions');links.forEach(([label,view])=>actions.append(btn(label,()=>show(view),'text-action')));copy.append(actions);}return card;}
 function searchableCards(rows,kind){const wrap=el('section',undefined,'tablet-list-wrap'),search=el('input');search.type='search';search.placeholder=kind==='inventory'?'Buscar producto o código':'Buscar por nombre o código';search.setAttribute('aria-label',search.placeholder);const list=el('div',undefined,'tablet-record-list');const render=()=>{list.replaceChildren();const q=search.value.trim().toLocaleLowerCase('es-MX');const filtered=rows.filter(r=>JSON.stringify(r).toLocaleLowerCase('es-MX').includes(q));if(!filtered.length){list.append(emptyState(kind));return;}filtered.forEach(row=>{const heading=row.name||row.productName||row.code||'Registro central';const card=el('article',undefined,'tablet-record-card');card.append(el('strong',heading));const details=el('div',undefined,'tablet-record-details');const fields=kind==='inventory'?['code','availableQuantity','inventoryValueCents','lastMovementAt']:['code','salePriceCents','availableQuantity','active'];fields.filter(key=>row[key]!==undefined&&row[key]!==null).forEach(key=>details.append(el('span',(names[key]||key)+': '+fmt(key,row[key]))));card.append(details);list.append(card);});};search.addEventListener('input',render);wrap.append(search,list);render();return wrap;}
 function productsScreen(rows){const panel=el('section',undefined,'tablet-module-page');panel.append(moduleHeader('Productos','Administra el catálogo, precios de venta y alertas de stock.','Administrar catálogo',()=>location.assign('/admin/products')),notice('Crear un producto no agrega existencias','Registra una compra o entrada para aumentar el stock.',[['Ir a Compras','purchases'],['Ver inventario','inventory']]),searchableCards(rows,'products'));return panel;}
 function inventoryScreen(rows,data){
  const panel=el('section',undefined,'tablet-module-page');
  panel.append(moduleHeader('Inventario','Existencias centrales por producto, según permisos de la sesión.',null,null),notice('Movimientos de existencias','Compras agrega stock y ventas descuenta por FIFO. Los ajustes requieren autorización y no se habilitan desde esta vista de consulta.',[['Registrar compra o entrada','purchases']]));
  if(!rows){const value=data&&typeof data==='object'?(data.inventoryValueCents??data.valueCents):null;panel.append(value===null?emptyState('inventory'):metricCard('Valor de inventario',fmt('inventoryValueCents',value)));return panel;}
  if(!rows.length){panel.append(emptyState('inventory'));return panel;}
  const normalized=rows.map(row=>({...row,availableQuantity:row.availableQuantity??row.stock}));
  const units=normalized.reduce((sum,row)=>sum+(Number.isFinite(Number(row.availableQuantity))?Number(row.availableQuantity):0),0);
  const overview=el('section',undefined,'tablet-dashboard');overview.append(metricCard('Productos con existencias',String(normalized.length)),metricCard('Unidades disponibles',String(units)));panel.append(overview);
  const wrap=el('section',undefined,'tablet-list-wrap'),search=el('input');search.type='search';search.placeholder='Buscar por nombre, código o identificador';search.setAttribute('aria-label',search.placeholder);
  const list=el('section',undefined,'tablet-record-list');
  const render=()=>{const q=search.value.trim().toLocaleLowerCase('es-MX');list.replaceChildren();const filtered=normalized.filter(row=>[row.productName,row.name,row.code,row.productGlobalId].some(value=>String(value??'').toLocaleLowerCase('es-MX').includes(q)));
   if(!filtered.length){list.append(el('p','No hay existencias que coincidan con la búsqueda.','muted'));return;}
   filtered.slice(0,200).forEach(row=>{const card=el('article',undefined,'tablet-record-card'),name=row.productName||row.name||row.code||('Producto '+String(row.productGlobalId??'sin identificador').slice(0,8));card.append(el('strong',name));const details=el('div',undefined,'tablet-record-details');details.append(el('span','Existencia: '+fmt('availableQuantity',row.availableQuantity)));if(row.inventoryValueCents!==undefined&&row.inventoryValueCents!==null)details.append(el('span','Valor: '+fmt('inventoryValueCents',row.inventoryValueCents)));if(row.code)details.append(el('span','Código: '+row.code));if(row.productGlobalId)details.append(el('span','ID: '+row.productGlobalId));card.append(details);list.append(card);});
   if(filtered.length>200)list.append(el('p','Mostrando 200 de '+filtered.length+' productos. Refina la búsqueda.','muted'));
  };search.addEventListener('input',render);wrap.append(search,list);panel.append(wrap);render();return panel;
 }
 function purchaseScreen(rows){const panel=el('section',undefined,'tablet-module-page');panel.append(moduleHeader('Compras','Registra mercancía recibida. Cada compra confirmada aumenta el stock y crea sus lotes FIFO.','＋ Nueva compra',()=>location.assign('/purchases/create')),notice('Compras es la vía principal para agregar existencias','Cada recepción conserva proveedor, costo histórico y trazabilidad FIFO.'));if(!rows?.length)panel.append(emptyState('purchases'));else {const list=el('section',undefined,'tablet-record-list');rows.forEach(row=>{const card=el('article',undefined,'tablet-record-card');card.append(el('strong',row.supplierName||row.supplier||'Proveedor'),el('span','Compra confirmada','tablet-status'));const detail=el('div',undefined,'tablet-record-details');['purchaseDate','totalCents','status'].filter(k=>row[k]!==undefined).forEach(k=>detail.append(el('span',(names[k]||k)+': '+fmt(k,row[k]))));card.append(detail);list.append(card);});panel.append(list);}return panel;}
 function categoryScreen(rows){const panel=el('section',undefined,'tablet-module-page');panel.append(moduleHeader('Categorías','Organiza los productos del catálogo.','＋ Nueva categoría',()=>location.assign('/admin/categories')));if(!rows?.length)panel.append(emptyState('categories'));else panel.append(searchableCards(rows,'categories'));return panel;}
 async function load(path,target,seq){try{const data=await api(path);if(seq!==sequence)return;const payload=!Array.isArray(data)&&data&&Object.prototype.hasOwnProperty.call(data,'items')?data.items:data;const rows=Array.isArray(payload)?payload:null;latestRows=rows||[];if(path==='dashboard')target.append(dashboard(payload));else if(path==='products')target.append(productsScreen(rows||[]));else if(path==='inventory')target.append(inventoryScreen(rows,payload));else if(path==='purchases')target.append(purchaseScreen(rows));else if(path==='categories')target.append(categoryScreen(rows));else if(rows)target.append(table(rows,200,path==='sales'?(row)=>openSale(row,target,seq):null));else target.append(summary(payload));status.textContent='Datos recibidos · '+new Date().toLocaleString('es-MX');}catch(e){if(seq!==sequence)return;status.textContent='Consulta fallida';target.append(el('div',e.message,'error'));}}
 function csv(rows){if(!rows.length)return;const keys=Object.keys(rows[0]),escape=v=>{const raw=String(v??'');const safe=/^[\s]*[=+\-@\t\r]/.test(raw)?"'"+raw:raw;return '"'+safe.replaceAll('"','""')+'"';},data='\uFEFF'+[keys.map(escape).join(','),...rows.map(r=>keys.map(k=>escape(r[k]&&typeof r[k]==='object'?JSON.stringify(r[k]):r[k])).join(','))].join('\r\n');const blob=new Blob([data],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='POSFlutter_Reporte_'+new Date().toISOString().slice(0,10)+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 function reports(seq){const p=el('div',undefined,'panel'),form=el('div',undefined,'filters'),select=el('select'),from=el('input'),to=el('input'),result=el('div');
  Object.entries(reportKinds).forEach(([key,name])=>{const option=el('option',name);option.value=key;select.append(option);});
  from.type='date';to.type='date';const today=new Date(),start=new Date(today.getFullYear(),today.getMonth(),1);const localDate=d=>[d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');from.value=localDate(start);to.value=localDate(today);
  let reportRequest=0;const perform=async()=>{const request=++reportRequest;result.replaceChildren();latestRows=[];status.textContent='Consultando reporte central…';let path='report/'+select.value;
   if(select.value!=='inventory'){const first=new Date(from.value+'T00:00:00'),last=new Date(to.value+'T00:00:00');last.setDate(last.getDate()+1);if(!Number.isFinite(first.getTime())||!Number.isFinite(last.getTime())||first>=last||(last-first)>366*86400000){result.append(el('p','Selecciona un periodo válido.','error'));return;}path+='?from='+encodeURIComponent(first.toISOString())+'&to='+encodeURIComponent(last.toISOString());}
   try{const data=await api(path);if(seq!==sequence||request!==reportRequest)return;const rows=items(data);latestRows=rows;result.append(rows.length?table(rows):summary(data));status.textContent='Reporte actualizado · '+new Date().toLocaleString('es-MX');}catch(e){if(seq!==sequence||request!==reportRequest)return;result.append(el('p',e.message,'error'));status.textContent='Reporte no disponible';}
  };
  form.append(el('label','Tipo de reporte'),select,el('label','Desde'),from,el('label','Hasta'),to,btn('Consultar',perform,'primary'),btn('Exportar CSV',()=>csv(latestRows)),btn('Imprimir / PDF',()=>window.print()));
  p.append(el('h2','Reportes del servidor central'),form,el('p','Los importes y costos provienen de los registros centrales; no se recalculan desde los precios actuales.','muted'));content.append(p,result);perform();
 }
 function monitor(seq){
  const p=el('div',undefined,'panel');p.append(el('h2','Estado reportado por dispositivos'),el('p','El estado es una estimación basada en la última sincronización registrada. Un dispositivo desconectado puede tener operaciones locales no enviadas.','muted'));content.append(p);
  const result=el('div');p.append(result);
  const refresh=async()=>{
   if(monitorBusy)return;monitorBusy=true;
   try {const data=await api('devices');if(seq!==sequence)return;
    const rows=items(data).map(d=>{
     const value=d.lastSyncAt||null,stamp=value?Date.parse(value):NaN,minutes=Number.isFinite(stamp)?Math.max(0,Math.floor((Date.now()-stamp)/60000)):null;
     return {...d,estadoConocido:minutes===null?'Sin evidencia de sincronización':minutes<=5?'Sincronización reciente':minutes<=30?'Sincronización atrasada':'Sin sincronización reciente',minutosDesdeUltimaSincronizacion:minutes??'Desconocido',pendientesLocales:'No verificables desde servidor',consultadoEn:new Date().toISOString()};
    });
    result.replaceChildren(table(rows));status.textContent='Última consulta al servidor: '+new Date().toLocaleString('es-MX');
   }catch(e){if(seq!==sequence)return;result.replaceChildren(el('p',e.message,'error'));status.textContent='Monitoreo no disponible';}finally{monitorBusy=false;}
  };
  refresh();monitorInterval=setInterval(()=>{if(!document.hidden && seq===sequence)refresh();},30000);
 }
 function pos(seq){const page=el('section',undefined,'pos-tablet-page'),context=el('header',undefined,'pos-context-card'),wrap=el('div',undefined,'pos-layout'),left=el('section',undefined,'panel'),right=el('section',undefined,'panel'),search=el('input'),results=el('div',undefined,'product-grid');context.append(el('h2','Nueva venta'),el('p','Catálogo central · caja y sucursal de la sesión activa','muted'));page.append(context);search.placeholder='Buscar productos';search.setAttribute('aria-label','Buscar productos');left.append(el('h2','Productos'),search,results);
  left.classList.add('pos-catalog-panel');right.classList.add('pos-cart-panel');search.classList.add('pos-search-input');results.setAttribute('aria-label','CatÃ¡logo de productos');right.replaceChildren(el('h2','Carrito'));wrap.append(left,right);page.append(wrap);content.append(page);
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
const cents=value=>Math.round(Number(value)*100),invalidateCheckoutAttempt=()=>{checkoutAttemptKey=null;};
  /* POSWEB_P04_FROZEN_RETRY_V1 */

let pendingCheckoutBody=null;

window.addEventListener('beforeunload',event=>{
    if(!pendingCheckoutBody)return;
    event.preventDefault();
    event.returnValue='';
});

function pendingCheckoutWarning(){
    status.textContent='Existe un cobro pendiente de confirmación. No cambies el carrito; reintenta la misma operación.';
}

wrap.addEventListener('click',event=>{
    if(!pendingCheckoutBody)return;
    if(event.target.closest('.pos-checkout'))return;
    event.preventDefault();
    event.stopImmediatePropagation();
    pendingCheckoutWarning();
},true);

wrap.addEventListener('change',event=>{
    if(!pendingCheckoutBody)return;
    event.preventDefault();
    event.stopImmediatePropagation();
    pendingCheckoutWarning();
},true);

wrap.addEventListener('input',event=>{
    if(!pendingCheckoutBody)return;
    event.preventDefault();
    event.stopImmediatePropagation();
    pendingCheckoutWarning();
},true);

async function sendFrozenCheckout(body,submit){
    status.textContent='Confirmando venta en servidor…';

    const csrf=document.querySelector('meta[name="pos-csrf"]')?.content;

    if(!csrf)throw Error('Token de seguridad no disponible.');

    /* La solicitud ya está congelada: no modificar ni recalcular. */
    const response=await fetch('/checkout',{
        method:'POST',
        credentials:'same-origin',
        cache:'no-store',
        headers:{
            'Content-Type':'application/json',
            'X-CSRF-TOKEN':csrf
        },
        body:JSON.stringify(body)
    });

    if(response.status===401){
        throw Error('Sesión vencida. Verifica la operación antes de volver a iniciar sesión.');
    }

    let result;
    try{
        result=await response.json();
    }catch{
        throw Error('Respuesta incompleta. La operación puede haberse registrado; reintenta la misma solicitud.');
    }

    if(!response.ok){
        throw Error(result.message||'El servidor no confirmó el cobro. Conserva la operación pendiente.');
    }

    if(!result.saleGlobalId ||
       !Number.isSafeInteger(result.totalCents) ||
       !result.folio){
        throw Error('Confirmación incompleta. Conserva la operación pendiente.');
    }

    pendingCheckoutBody=null;
    unresolvedCheckoutActive=false;
    checkoutAttemptKey=null;
    sessionStorage.removeItem('POSWEB_P04_UNCERTAIN_CHECKOUT');
    cart.clear();
    drawCart();

    const receipt=el('section',undefined,'sale-receipt panel');

    receipt.append(
        el('h2','Venta confirmada'),
        el('p','Folio '+result.folio+' · '+money.format(result.totalCents/100)),
        el('p','Venta registrada en servidor.','notice'),
        btn('Imprimir comprobante',()=>window.print())
    );

    right.prepend(receipt);
    status.textContent='Venta '+result.folio+' confirmada.';
}

/* END_POSWEB_P04_FROZEN_RETRY_V1 */
const drawCart=()=>{right.querySelectorAll('.cart-content').forEach(x=>x.remove());const holder=el('div',undefined,'cart-content');let total=0;cart.forEach(({product,quantity},id)=>{const price=Number(product.salePriceCents)||0;total+=price*quantity;const row=el('div',undefined,'cart-line');const remove=btn('×',()=>{invalidateCheckoutAttempt();cart.delete(id);drawCart();});remove.setAttribute('aria-label','Quitar '+product.name);row.append(el('span',product.name+' × '+quantity),el('strong',money.format(price*quantity/100)),btn('−',()=>{invalidateCheckoutAttempt();if(quantity<=1)cart.delete(id);else cart.set(id,{product,quantity:quantity-1});drawCart();}),btn('+',()=>{invalidateCheckoutAttempt();cart.set(id,{product,quantity:quantity+1});drawCart();}),remove);holder.append(row);});
   if(!cart.size){
      const uncertainKey=sessionStorage.getItem('POSWEB_P04_UNCERTAIN_CHECKOUT');
      if(uncertainKey){
        holder.append(el('p','Existe un cobro previo sin confirmaciÃ³n local. No inicies otra venta.','notice'));
        const check=btn('Consultar cobro pendiente',async()=>{
          check.disabled=true;
          try{
            if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(uncertainKey))
              throw Error('La operaciÃ³n anterior no tiene clave recuperable. Requiere conciliaciÃ³n administrativa.');
            const resp=await fetch('/checkout/status/'+encodeURIComponent(uncertainKey),{credentials:'same-origin',cache:'no-store'});
            if(resp.status===401)throw Error('SesiÃ³n vencida. Reingresa con el operador original.');
            if(resp.status===403)throw Error('Identidad distinta. Reingresa con el operador original.');
            if(resp.status===404)throw Error('El servidor aÃºn no confirma esta venta. No se autoriza un segundo cobro; verifica de nuevo.');
            if(!resp.ok)throw Error('ConciliaciÃ³n no disponible; conserva el bloqueo.');
            const result=await resp.json();
            if(result.state!=='confirmed'||!result.saleGlobalId||!result.folio||!Number.isSafeInteger(result.totalCents))
              throw Error('Respuesta no verificable. Conserva el bloqueo.');
            sessionStorage.removeItem('POSWEB_P04_UNCERTAIN_CHECKOUT');
            unresolvedCheckoutActive=false;
            checkoutAttemptKey=null;
            status.textContent='Venta '+result.folio+' confirmada en servidor.';
            const receipt=el('section',undefined,'sale-receipt panel');
            receipt.append(el('h2','Venta conciliada'),el('p','Folio '+result.folio+' Â· '+money.format(result.totalCents/100)));
            right.prepend(receipt);
            drawCart();
          }catch(err){status.textContent=err.message;}
          finally{if(check.isConnected)check.disabled=false;}
        },'primary');
        holder.append(check);
      }else holder.append(el('p','Selecciona productos para iniciar una venta.','muted'));
      right.append(holder);return;
    }
   const payment=el('select'),cashReceived=el('input'),paymentLine=el('div',undefined,'payment-controls');[['Cash','Efectivo'],['Card','Tarjeta'],['Transfer','Transferencia']].forEach(([v,n])=>{const o=el('option',n);o.value=v;payment.append(o);});cashReceived.type='number';cashReceived.min='0';cashReceived.step='0.01';cashReceived.placeholder='Efectivo recibido';cashReceived.setAttribute('aria-label','Efectivo recibido');const change=el('p','','muted');const updateTender=()=>{const cash=payment.value==='Cash';cashReceived.hidden=!cash;change.hidden=!cash;if(cash){const received=cents(cashReceived.value||0);change.textContent=received>=total?'Cambio: '+money.format((received-total)/100):'Ingresa al menos '+money.format(total/100);}};payment.addEventListener('change',()=>{invalidateCheckoutAttempt();updateTender();});cashReceived.addEventListener('input',()=>{invalidateCheckoutAttempt();updateTender();});paymentLine.append(el('label','Forma de pago'),payment,cashReceived,change);
   
const checkout=async()=>{
    const submit=holder.querySelector('.pos-checkout');
    if(!submit || submit.disabled)return;

    submit.disabled=true;
    try{
        if(pendingCheckoutBody){
            await sendFrozenCheckout(pendingCheckoutBody,submit);
            return;
        }

        if(sessionStorage.getItem('POSWEB_P04_UNCERTAIN_CHECKOUT')){
            throw Error('Existe un cobro con resultado incierto de una sesión anterior. Verifica la venta en el servidor antes de iniciar otra.');
        }

        const csrf=document.querySelector('meta[name="pos-csrf"]')?.content;
        if(!csrf)throw Error('Token de seguridad no disponible.');

        const entries=[...cart.values()];
        if(!entries.length)throw Error('Carrito vacío.');

        const lines=entries.map(x=>({
            productGlobalId:x.product.globalId,
            quantity:x.quantity
        }));

        if(lines.some(x=>!x.productGlobalId ||
            !Number.isInteger(x.quantity) || x.quantity<1)){
            throw Error('Productos o cantidades inválidas.');
        }

        status.textContent='Validando precios centrales…';

        const quoteResponse=await fetch('/quote/calculate',{
            method:'POST',
            credentials:'same-origin',
            cache:'no-store',
            headers:{
                'Content-Type':'application/json',
                'X-CSRF-TOKEN':csrf
            },
            body:JSON.stringify({lines})
        });

        if(quoteResponse.status===401){
            location.assign('/Home/Login');
            return;
        }

        const quote=await quoteResponse.json();

        if(!quoteResponse.ok){
            throw Error(quote.message||'No fue posible validar precios.');
        }

        if(!Number.isSafeInteger(quote.totalCents) ||
            quote.totalCents<=0 ||
            !Array.isArray(quote.lines) ||
            quote.lines.length!==lines.length){
            throw Error('Cotización del servidor inválida.');
        }

        const quotedById=new Map(
            quote.lines.map(x=>[String(x.productGlobalId).toLowerCase(),x])
        );

        let calculated=0;
        let priceChanged=false;

        for(const entry of entries){
            const id=String(entry.product.globalId).toLowerCase();
            const quoted=quotedById.get(id);

            if(!quoted ||
                quoted.quantity!==entry.quantity ||
                !Number.isSafeInteger(quoted.unitPriceCents) ||
                quoted.unitPriceCents<0 ||
                !Number.isSafeInteger(quoted.subtotalCents) ||
                quoted.subtotalCents!==quoted.unitPriceCents*entry.quantity){
                throw Error('La cotización no coincide con el carrito.');
            }

            calculated+=quoted.subtotalCents;

            if(quoted.unitPriceCents!==Number(entry.product.salePriceCents)){
                priceChanged=true;
            }
        }

        if(!Number.isSafeInteger(calculated) ||
            calculated!==quote.totalCents){
            throw Error('Total de cotización inconsistente.');
        }

        if(priceChanged){
            entries.forEach(entry=>{
                const quoted=quotedById.get(
                    String(entry.product.globalId).toLowerCase()
                );
                entry.product.salePriceCents=quoted.unitPriceCents;
            });

            invalidateCheckoutAttempt();
            drawCart();

            status.textContent=
                'Los precios cambiaron. Revisa el nuevo total y confirma nuevamente.';
            return;
        }

        const method=payment.value;
        const amount=quote.totalCents;

        const received=method==='Cash'
            ? cents(cashReceived.value||0)
            : null;

        if(method==='Cash' &&
            (!Number.isSafeInteger(received)||received<amount)){
            status.textContent='El efectivo recibido no cubre el total.';
            cashReceived.focus();
            return;
        }

        const body={
            idempotencyKey:checkoutAttemptKey||=crypto.randomUUID(),
            lines,
            payments:[{method,amountCents:amount}],
            receivedCashCents:received
        };

        pendingCheckoutBody=JSON.parse(JSON.stringify(body));
        unresolvedCheckoutActive=true;

        /* Persistir sólo una señal, nunca secretos ni una venta reutilizable
           después de recargar o cambiar de usuario. */
        sessionStorage.setItem('POSWEB_P04_UNCERTAIN_CHECKOUT',body.idempotencyKey);

        await sendFrozenCheckout(pendingCheckoutBody,submit);
    }
    catch(error){
        status.textContent=error.message;
        if(submit.isConnected)submit.disabled=false;
    }
};
   holder.append(el('h2','Total: '+money.format(total/100)),paymentLine,btn('Cotizar e imprimir',async()=>{try{await quoteFromCart([...cart.values()],message=>{status.textContent=message;});}catch(error){status.textContent=error.message;}},'secondary'),btn('Cobrar y confirmar',checkout,'primary pos-checkout'),btn('Cancelar venta',()=>{invalidateCheckoutAttempt();cart.clear();drawCart();}));right.append(holder);updateTender();};
  const render=()=>{results.replaceChildren();const q=search.value.trim().toLocaleLowerCase('es-MX');catalog.filter(x=>(x.name+' '+x.code).toLocaleLowerCase('es-MX').includes(q)).slice(0,100).forEach(product=>{const item=el('article',undefined,'product-card'),id=product.globalId||product.code,stock=Number(product.availableQuantity);const meta=el('div',undefined,'product-card-meta');meta.append(el('small',product.code||'Sin código'));if(Number.isFinite(stock))meta.append(el('small',`${stock} disponibles`,'stock-chip'));item.append(el('strong',product.name),meta,el('b',money.format((Number(product.salePriceCents)||0)/100)),btn('Agregar',()=>{invalidateCheckoutAttempt();const old=cart.get(id);cart.set(id,{product,quantity:(old?.quantity||0)+1});drawCart();},'primary'));results.append(item);});};
  search.addEventListener('input',render);drawCart();api('products').then(data=>{if(seq!==sequence)return;catalog=items(data).filter(x=>x.active!==false);render();status.textContent='Catálogo central listo para vender.';}).catch(e=>results.append(el('p',e.message,'error')));
 }
 /* POSWEB_P04_PENDING_NAV_GUARD_V1 */
 /* POSWEB_P04_STATUS_LOOKUP_V1 */
 function show(kind){if(!(kind in labels))return;if(sessionStorage.getItem('POSWEB_P04_UNCERTAIN_CHECKOUT')&&kind!=='pos')kind='pos';if(unresolvedCheckoutActive){status.textContent='Cobro pendiente: conserva esta pantalla y reintenta la misma operaciÃ³n antes de navegar.';return;}if(monitorInterval!==null){clearInterval(monitorInterval);monitorInterval=null;}current=kind;const seq=++sequence;content.replaceChildren();latestRows=[];title.textContent=labels[kind];workspace?.classList.toggle('flutter-content-view',['dashboard','pos','products','categories','inventory'].includes(kind));nav.querySelectorAll('button').forEach(b=>b.classList.toggle('active',b.dataset.view===kind));status.textContent='Consultando SQL Server central…';
  if(kind==='purchases'){const bar=el('div',undefined,'module-actions');const link=el('a','Registrar compra','primary action-link');link.href='/purchases/create';bar.append(link);content.append(bar);}
  if(kind==='report')return reports(seq);if(kind==='devices')return monitor(seq);if(kind==='pos')return pos(seq);load(kind,content,seq);
 }
 nav.addEventListener('click',e=>{const b=e.target.closest('button[data-view]');if(b){setDrawer(false);show(b.dataset.view);}});document.getElementById('reload').addEventListener('click',()=>show(current));show(current);
})();
