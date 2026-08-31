# PHASE18E_SCREEN_AUDIT

Fecha: 2026-08-30

Base: `bc54cce9688791a5b8e53b13b2f0588d87f09e53`

Alcance: cierre visual y de interacción de las pantallas existentes; sin cambios de dominio, sincronización, autorización, backend ni esquema (permanece V5).

| SCREEN | STATUS | UX_GAPS | RESPONSIVE_GAPS | FORM_GAPS | STATE_GAPS | ACCESSIBILITY_GAPS | TARGET_FIX |
|---|---|---|---|---|---|---|---|
| Productos | NEEDS_POLISH | Filas densas y técnicas | Verificar 390/800/1280 | Validación insuficiente | Vacío sin CTA | Campos sin indicador requerido | Formulario validado, CTA vacío y feedback |
| Categorías | NEEDS_POLISH | Alta demasiado silenciosa | Verificar escalado 1.2 | Nombre vacío | Vacío sin CTA | Requerido no anunciado | Validación y feedback compartidos |
| Proveedores | NEEDS_POLISH | Alta demasiado silenciosa | Verificar escalado 1.2 | Nombre vacío | Vacío sin CTA | Requerido no anunciado | Validación y feedback compartidos |
| Compras | NEEDS_FIX | Identificadores técnicos inevitables en flujo actual | Diálogo debe desplazarse en móvil | Cantidad/costo/IDs inválidos; doble envío | Error genérico | Sin ayuda contextual | Campos numéricos validados y submit bloqueado |
| Inventario | NEEDS_FIX | Ajuste sensible poco guiado | Diálogo debe desplazarse en móvil | Delta y motivo inválidos | Vacío sin acción | Motivo requerido no visible | Validación, CTA vacío y autorización conservada |
| Ventas | NEEDS_POLISH | Cancelación sensible requiere claridad | Verificar landscape tablet | ID/motivo vacíos | Vacío sin acción | Acción sensible sin feedback final | Validación y feedback; permisos conservados |
| Caja | NEEDS_FIX | Acciones no reflejan progreso | Wrap ya adaptable; verificar móvil | Montos inválidos | Lista interna hereda estados comunes | Etiquetas requeridas ausentes | Validación monetaria y bloqueo durante operación |
| Gastos | NEEDS_POLISH | Alta sin confirmación | Verificar móvil | Concepto/monto inválidos | Vacío sin CTA | Requeridos ausentes | Validación, CTA vacío y feedback |
| Reportes | NEEDS_FIX | Exportación correcta pero poco resiliente | Lista desplazable adaptable | N/A | Error se mostraba como carga infinita | Estado de error no comunicado | Error explícito y feedback de exportación |
| Usuarios | NEEDS_POLISH | Vista sólo lectura coherente con capacidades actuales | Verificar 390/800/1280 | No existe alta local autorizada en esta pantalla | Estados comunes correctos | Filas técnicas | Mantener sólo lectura; no inventar mutaciones |
| Respaldos | NEEDS_FIX | Restauración no estaba expuesta | Card adaptable | Ruta y confirmación ausentes | Sin progreso/error | Riesgo destructivo poco comunicado | Confirmación explícita, autorización y feedback |
| Administración cloud | NEEDS_POLISH | Datos crudos en diálogos | Verificar tablet/móvil | N/A | Offline poco accionable | Carga no semántica | Estados Design System y mensaje offline |
| Atención de sync | NEEDS_POLISH | Clasificación ya implementada en 18A.9 | Verificar text scale 1.2 | N/A | Estados existentes | Revisar anuncios de estado | Pruebas de regresión, sin alterar semántica |
| First-run / login | GOOD | Flujo funcional y tematizado en 18C | Conserva scroll y teclado | Validaciones existentes | Estados existentes | Revisar escala de texto | Sólo regresión; evitar reabrir autenticación |

## Decisiones de implementación

- `DatabaseListScreen` concentra carga, error, vacío con acción, refresco y bloqueo de doble envío para todos los catálogos operativos.
- `textForm` usa campos de formulario reales, muestra validación junto al campo, recorta espacios y distingue cancelar de completar.
- Los campos numéricos rechazan texto, negativos no autorizados y cero cuando el dominio exige una cantidad positiva; el ajuste de inventario conserva signo.
- Las acciones sensibles existentes mantienen sus capacidades y `runWithSpecialAuthorization`; el pulido no elude permisos.
- Restaurar respaldo exige ruta, confirmación destructiva explícita y autorización especial. No se cambia la implementación transaccional ni el esquema.
- No se agrega una mutación de usuarios porque la pantalla actual es deliberadamente de lectura; inventar un alta cambiaría el contrato de dominio y excedería 18E.

## Matriz responsive objetivo

Las pruebas representativas deben montar Productos, Compras, Inventario, Ventas, Caja, Gastos, Reportes, Usuarios y Respaldos en `390x844`, `800x1280` y `1280x800`, con escalas de texto `1.0` y `1.2`. Criterios: sin overflow, acciones accesibles, diálogos desplazables y estados legibles.

## Criterio de cierre

Este documento es una auditoría de entrada, no una declaración de cierre. FASE 18E sólo puede marcarse `CLOSED` tras ejecutar realmente Flutter analyze/test, builds Android debug/release, verificación de firma, gates Python, build/test .NET, revisión Git, commit, push y verificación del bundle/clone requeridos.
