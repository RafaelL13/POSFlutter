(() => {
 'use strict';
 const nav=document.getElementById('nav'); if(!nav)return;
 const content=document.getElementById('content'),status=document.getElementById('status'),title=document.getElementById('page-title');
 const labels={dashboard:'Resumen',products:'Productos',inventory:'Inventario',lots:'Lotes',sales:'Ventas',purchases:'Compras',cash:'Caja',expenses:'Gastos',devices:'Monitoreo de tablets',branches:'Sucursales',users:'Usuarios',report:'Reportes',pos:'Punto de venta'};
 const reportKinds={'summary':'Resumen','sales':'Ventas','products':'Productos','products/low-performance':'Bajo rendimiento','categories':'Categorías','users':'Vendedores','purchases':'Compras','suppliers':'Proveedores','inventory':'Inventario','expenses':'Gastos','cash':'Caja','payment-methods':'Métodos de pago','cancellations':'Cancelaciones','trends/products':'Tendencias'};
 const money=new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN'});
 const names={globalId:'ID',name:'Nombre',code:'Código',salePriceCents:'Precio',availableQuantity:'Existencia',totalCents:'Total',lastSyncAt:'Última sincronización',lastCommunicationAt:'Última comunicación',mode:'Modo',active:'Activo',status:'Estado'};
 let current='dashboard', sequence=0, catalog=[], cart=new Map(), latestRows=[];
 let monitorInterval=null, monitorBusy=false;
 const el=(tag,txt,cls)=>{const n=document.createElement(tag);if(txt!==undefined)n.textContent=String(txt??'—');if(cls)n.className=cls;return n;};
 const btn=(caption,fn,cls='secondary')=>{const b=el('button',caption,cls);b.type='button';b.addEventListener('click',fn);return b;};
 const api=async(path)=>{const r=await fetch('/data/'+path,{credentials:'same-origin',cache:'no-store'});if(r.status===401){location.assign('/Home/Login');throw Error('Sesión vencida');}if(!r.ok)throw Error(r.status===403?'Acceso denegado por permisos.':'La API respondió HTTP '+r.status);return r.json();};
 const items=data=>Array.isArray(data)?data:Array.isArray(data?.items)?data.items:[];
 const fmt=(key,value)=>{
  if(value===null||value===undefined)return '—';
  if(key.endsWith('Cents')&&typeof value==='number')return money.format(value/100);
  if(typeof value==='boolean')return value?'Sí':'No';
  if(typeof value==='object')return JSON.stringify(value);
  return String(value);
 };
 function table(rows,limit=200,onRow=null){const panel=el('div',undefined,'panel');if(!rows.length){panel.append(el('p','No hay registros disponibles.','muted'));return panel;}
  const keys=Object.keys(rows[0]).filter(k=>typeof rows[0][k]!=='object').slice(0,16),t=el('table',undefined,'table'),head=el('thead'),tr=el('tr');keys.forEach(k=>tr.append(el('th',names[k]||k)));head.append(tr);t.append(head);
  const body=el('tbody');rows.slice(0,limit).forEach(r=>{const line=el('tr');if(onRow){line.tabIndex=0;line.className='selectable-row';line.addEventListener('click',()=>onRow(r));line.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();onRow(r);}});}keys.forEach(k=>line.append(el('td',fmt(k,r[k]))));body.append(line);});t.append(body);panel.append(t);if(rows.length>limit)panel.append(el('p',`Mostrando ${limit} de ${rows.length} registros. Refina tu consulta.`, 'muted'));return panel;
 }
 function saleDetails(sale){const panel=el('section',undefined,'panel');panel.append(el('h2','Detalle de venta confirmado por servidor'),btn('Cerrar detalle',()=>panel.remove()));
  if(!sale||typeof sale!=='object'){panel.append(el('p','Respuesta inválida','error'));return panel;}
  const fields=Object.entries(sale).filter(([,v])=>v!==null&&typeof v!=='object');panel.append(summary(Object.fromEntries(fields)));
  for(const [key,value] of Object.entries(sale))if(Array.isArray(value))panel.append(el('h3',key),table(value));return panel;}
 async function openSale(row,target,seq){const id=row.globalId;if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(String(id||''))){status.textContent='Venta sin identificador válido';return;}
  const existing=document.getElementById('sale-detail');if(existing)existing.remove();
  try{const data=await api('sale/'+encodeURIComponent(id));if(seq!==sequence)return;const panel=saleDetails(data);panel.id='sale-detail';target.prepend(panel);status.textContent='Detalle de venta consultado en servidor';}
  catch(e){if(seq!==sequence)return;status.textContent=e.message;}}
 function summary(data){const grid=el('div',undefined,'grid');Object.entries(data).filter(([,v])=>['string','number','boolean'].includes(typeof v)).slice(0,20).forEach(([k,v])=>{const a=el('div',undefined,'stat');a.append(el('small',names[k]||k),el('b',fmt(k,v)));grid.append(a);});return grid;}
 async function load(path,target,seq){try{const data=await api(path);if(seq!==sequence)return;const rows=Array.isArray(data)?data:Array.isArray(data?.items)?data.items:null;latestRows=rows||[];target.append(rows?table(rows,200,path==='sales'?(row)=>openSale(row,target,seq):null):summary(data));status.textContent='Datos recibidos · '+new Date().toLocaleString('es-MX');}catch(e){if(seq!==sequence)return;status.textContent='Consulta fallida';target.append(el('div',e.message,'error'));}}
 function csv(rows){if(!rows.length)return;const keys=Object.keys(rows[0]),escape=v=>{const raw=String(v??'');const safe=/^[\s]*[=+\-@\t\r]/.test(raw)?"'"+raw:raw;return '"'+safe.replaceAll('"','""')+'"';},data='\uFEFF'+[keys.map(escape).join(','),...rows.map(r=>keys.map(k=>escape(r[k]&&typeof r[k]==='object'?JSON.stringify(r[k]):r[k])).join(','))].join('\r\n');const blob=new Blob([data],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='POSFlutter_Reporte_'+new Date().toISOString().slice(0,10)+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 function reports(seq){const p=el('div',undefined,'panel'),form=el('div',undefined,'filters'),select=el('select'),from=el('input'),to=el('input'),result=el('div');
  Object.entries(reportKinds).forEach(([key,name])=>{const option=el('option',name);option.value=key;select.append(option);});
  from.type='date';to.type='date';const today=new Date(),start=new Date(today.getFullYear(),today.getMonth(),1);const localDate=d=>[d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');from.value=localDate(start);to.value=localDate(today);
  let reportRequest=0;const perform=async()=>{const request=++reportRequest;result.replaceChildren();latestRows=[];status.textContent='Consultando reporte central…';let path='report/'+select.value;
   if(select.value!=='inventory'){const first=new Date(from.value+'T00:00:00'),last=new Date(to.value+'T00:00:00');last.setDate(last.getDate()+1);if(!Number.isFinite(first.getTime())||!Number.isFinite(last.getTime())||first>=last||(last-first)>366*86400000){result.append(el('p','Selecciona un periodo válido.','error'));return;}path+='?from='+encodeURIComponent(first.toISOString())+'&to='+encodeURIComponent(last.toISOString());}
   try{const data=await api(path);if(seq!==sequence||request!==reportRequest)return;const rows=items(data);latestRows=rows;result.append(rows.length?table(rows):summary(data));status.textContent='Reporte actualizado · '+new Date().toLocaleString('es-MX');}catch(e){if(seq!==sequence||request!==reportRequest)return;result.append(el('p',e.message,'error'));status.textContent='Reporte no disponible';}
  };
  form.append(el('label','Tipo de reporte'),select,el('label','Desde'),from,el('label','Hasta'),to,btn('Consultar',perform,'primary'),btn('Exportar CSV',()=>csv(latestRows)),btn('Imprimir / PDF',()=>window.print()));
  p.append(el('h2','Reportes del servidor central'),form,el('p','Los importes y costos provienen de la API; no se recalculan desde los productos actuales.','muted'));content.append(p,result);perform();
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
 function pos(seq){const wrap=el('div',undefined,'pos-layout'),left=el('section',undefined,'panel'),right=el('section',undefined,'panel'),search=el('input'),results=el('div',undefined,'product-grid');search.placeholder='Buscar producto por nombre o código';search.setAttribute('aria-label','Buscar productos');left.append(el('h2','Catálogo central'),search,results);
  right.append(el('h2','Carrito de cotización'),el('p','Solo cálculo visual. No registra ventas, pagos ni movimientos de inventario.','notice'));wrap.append(left,right);content.append(wrap);
  const drawCart=()=>{right.querySelectorAll('.cart-content').forEach(x=>x.remove());const holder=el('div',undefined,'cart-content');let total=0;cart.forEach(({product,quantity},id)=>{const cents=Number(product.salePriceCents)||0;total+=cents*quantity;const row=el('div',undefined,'cart-line');row.append(el('span',product.name+' × '+quantity),el('strong',money.format(cents*quantity/100)),btn('−',()=>{if(quantity<=1)cart.delete(id);else cart.set(id,{product,quantity:quantity-1});drawCart();}),btn('+',()=>{cart.set(id,{product,quantity:quantity+1});drawCart();}));holder.append(row);});holder.append(el('h2','Total estimado: '+money.format(total/100)),btn('Validar precios centrales',async()=>{
    const lines=[...cart.values()].map(x=>({productGlobalId:x.product.globalId,quantity:x.quantity}));
    if(!lines.length){status.textContent='Carrito vacío';return;}
    const csrf=document.querySelector('meta[name="pos-csrf"]')?.content;
    try {const response=await fetch('/quote/calculate',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','X-CSRF-TOKEN':csrf||''},body:JSON.stringify({lines})});
      if(response.status===401){location.assign('/Home/Login');return;}
      const quote=await response.json();if(!response.ok)throw Error(quote.message||'No se pudo validar la cotización');
      const previous=right.querySelector('.server-quote');if(previous)previous.remove();
      right.append(el('p','Total validado por servidor: '+money.format(quote.totalCents/100)+' — NO ES VENTA CONFIRMADA','server-quote notice'));
    }catch(error){status.textContent=error.message;}
   },'primary'),btn('Limpiar',()=>{cart.clear();drawCart();}));right.append(holder);};
  const render=()=>{results.replaceChildren();const q=search.value.trim().toLocaleLowerCase('es-MX');catalog.filter(x=>(x.name+' '+x.code).toLocaleLowerCase('es-MX').includes(q)).slice(0,100).forEach(product=>{const item=el('article',undefined,'product-card'),id=product.globalId||product.code;item.append(el('strong',product.name),el('small',product.code||''),el('b',money.format((Number(product.salePriceCents)||0)/100)),btn('Agregar',()=>{const old=cart.get(id);cart.set(id,{product,quantity:(old?.quantity||0)+1});drawCart();},'primary'));results.append(item);});};
  search.addEventListener('input',render);drawCart();api('products').then(data=>{if(seq!==sequence)return;catalog=items(data).filter(x=>x.active!==false);render();status.textContent='Catálogo central recibido · cotización local no confirmada';}).catch(e=>results.append(el('p',e.message,'error')));
 }
 function show(kind){if(!(kind in labels))return;if(monitorInterval!==null){clearInterval(monitorInterval);monitorInterval=null;}current=kind;const seq=++sequence;content.replaceChildren();latestRows=[];title.textContent=labels[kind];nav.querySelectorAll('button').forEach(b=>b.classList.toggle('active',b.dataset.view===kind));status.textContent='Consultando API central…';
  if(kind==='report')return reports(seq);if(kind==='devices')return monitor(seq);if(kind==='pos')return pos(seq);load(kind,content,seq);
 }
 nav.addEventListener('click',e=>{const b=e.target.closest('button[data-view]');if(b)show(b.dataset.view);});document.getElementById('reload').addEventListener('click',()=>show(current));show(current);
})();
