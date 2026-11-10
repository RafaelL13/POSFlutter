(() => {
 "use strict";
 const formatMoney = cents => (Number(cents || 0) / 100).toLocaleString("es-MX", {style:"currency",currency:"MXN"});
 const add = (parent,tag,text,className) => {
   const el=document.createElement(tag);
   if(className) el.className=className;
   el.textContent=String(text ?? "");
   parent.appendChild(el);
   return el;
 };
 async function showReport() {
   const target=document.querySelector("#content");
   if(!target) return;
   target.replaceChildren();
   add(target,"h2","Reporte comercial de ventas");
   const exportLink=document.createElement("a");
   exportLink.id="p054-export-sales";
   exportLink.href="/reports/export-sales.csv";
   exportLink.textContent="Exportar ventas CSV";
   exportLink.setAttribute("download","ventas-autorizadas.csv");
   exportLink.className="secondary";
   target.appendChild(exportLink);
   add(target,"p","Datos confirmados en el servidor central. Se muestran hasta 500 ventas autorizadas.");
   const status=add(target,"p","Consultando ventas...");
   try {
     const response=await fetch("/reports/summary",{credentials:"same-origin",cache:"no-store",headers:{"Accept":"application/json"}});
     if(!response.ok) throw new Error("HTTP "+response.status);
     const result=await response.json();
     const dashboard=result.dashboard || {};
     const sales=Array.isArray(result.sales) ? result.sales : [];
     status.textContent="Actualizado: "+new Date(result.generatedAt).toLocaleString("es-MX");
     const cards=document.createElement("section"); cards.className="report-kpis";target.appendChild(cards);
     [["Ventas de hoy",formatMoney(dashboard.salesCents)],["Operaciones de hoy",dashboard.operations ?? "â€”"],
      ["Costo FIFO de hoy",dashboard.fifoCostCents===undefined?"Restringido":formatMoney(dashboard.fifoCostCents)],
      ["Utilidad bruta de hoy",dashboard.grossProfitCents===undefined?"Restringido":formatMoney(dashboard.grossProfitCents)]]
       .forEach(([label,value])=>{const tile=add(cards,"div",label,"report-kpi");add(tile,"strong",value);});
     add(target,"h3","Historial autorizado de ventas ("+sales.length+")");
     const table=document.createElement("table");table.className="report-table";
     const thead=document.createElement("thead"),header=document.createElement("tr");
     ["Folio","Fecha","Importe","Estado","Costo FIFO","Utilidad"].forEach(h=>add(header,"th",h));
     thead.appendChild(header);table.appendChild(thead);
     const tbody=document.createElement("tbody");
     for(const sale of sales) {
       const tr=document.createElement("tr");
       [sale.folio||sale.globalId||"",sale.saleDateTime?new Date(sale.saleDateTime).toLocaleString("es-MX"):"",
        formatMoney(sale.totalCents),sale.status||"",
        sale.fifoCostCents===undefined?"Restringido":formatMoney(sale.fifoCostCents),
        sale.grossProfitCents===undefined?"Restringido":formatMoney(sale.grossProfitCents)]
        .forEach(v=>add(tr,"td",v));
       tbody.appendChild(tr);
     }
     table.appendChild(tbody);target.appendChild(table);
   } catch(e) { status.textContent="No fue posible consultar el reporte: "+e.message; }
 }
 document.addEventListener("click",e=>{
   const button=e.target.closest("[data-view='report']");
   if(!button) return;
   e.preventDefault(); e.stopImmediatePropagation();
   document.querySelectorAll("#nav button").forEach(el=>el.classList.toggle("active",el===button));
   const title=document.querySelector("#page-title");if(title) title.textContent="Reportes";
   const desc=document.querySelector("#page-desc");if(desc) desc.textContent="Ventas y utilidades autorizadas";
   showReport();
 },true);
})();