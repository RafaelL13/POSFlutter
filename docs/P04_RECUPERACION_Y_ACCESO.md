# POSFlutter Web — P04: recuperación, acceso y continuidad verificable

**Fuente canónica de código:** `C:\POSFlutter_Web\POSFlutter_Original`. **Estado de referencia:** noche del 5 de noviembre de 2026. Documento para ChatGPT, Codex y operadores del proyecto. Ningún resultado aquí sustituye una aceptación comercial.

## Estado que debe conservarse

| Elemento | Estado y evidencia | Alcance real |
|---|---|---|
| P04 | 11/11 PASS, `artifacts\P04_VISUAL_LOCAL_20261105_183339\RESULTADOS.json`; existe también evidencia de `185415` | Certificación del candidato LAB. **NO** repetir pruebas P04 sin regresión nueva. Copias preservadas: `docs/evidence/P04_RESULTADOS_183339.json` y `docs/evidence/P04_RESULTADOS_185415.json` (ambos 11/11 PASS, sin credenciales). |
| Kestrel 59444 | `RECOVERY=PASS`, SQL LAB accesible, `/health` 200, `/Home/Login` GET 200, TLS confiable. `artifacts\P04_KESTREL_RECOVERY\attempt_20261105_212337` | No se volvió a probar inicio de sesión en esa ejecución. Usuario confirmó que la URL funciona. |
| Kestrel 59447 | Usuario confirmó que funciona y aportó captura de Dashboard autenticado “Hola, operación central”. Copia no sensible: `docs/evidence/P04_59447_Dashboard_20261105.png` | Prueba de acceso y Dashboard visual, NO de transacciones/ventas productivas. |
| Git | `GIT_CHECKPOINT=BLOCKED_REPO_ROOT_MISMATCH` en recuperación V2 | Sin commit o push demostrado por ese resultado. |
| IIS 8443 | Rechazos 400 `Hostname` de HTTP.sys, correcciones probadas sin éxito | No reabrir experimentos de hostname sin evidencia técnica nueva. |
| IIS paralelo 18644/18645 | 400/503; sitio y pool revertidos (ausentes después del intento) | NO instalar de nuevo el ejecutor paralelo fallido. |
| Android release | Firma comercial actualizada bloqueada: faltan credenciales originales de la llave de firma | No cambiar keystore ni generar debug como release. |
| Producción | `NO_GO` | Ni web ni Android han sido aceptados en el entorno definitivo. |

**Puertos y PID no son identidades inmutables.** PID históricos: 59444 `36752`, 59447 `28652`; comprobar dueño y contenido si se reinician los procesos. **No detener ninguna instancia para registrar documentación o Git.**

## Dos publicaciones / dos rutas (no mezclar)

- Certificador e iniciador visual P04 aprobado: `C:\POSFlutter_Web\LAB_P04_VISUAL_20261104\run_20261105_183339\release`. `deploy/recovery/INICIAR_POSWEB_P04_CERTIFICADO_V2.ps1` selecciona un puerto libre comenzando por `59446`; el usuario observó `59447`. La correspondencia exacta entre un PID en ejecución y esta carpeta no debe inferirse solo de la captura.
- Recuperador Kestrel V2: publicación histórica `C:\POSFlutter_Web\LAB_P04_VISUAL_20261104\run_20261105_185415\release`, copia operativa `C:\POSFlutter_Web\POSFlutter_Original\artifacts\P04_KESTREL_RECOVERY\release`, manifest `deploy/recovery/P04_RECOVERY_VERIFIED.json`, script `deploy/recovery/RECUPERAR_POSFLUTTER_P04_KESTREL_V2.ps1`, escucha `https://localhost:59444`.
- Ambas son instancias **Kestrel HTTPS loopback**, no sitios IIS de entrega. La captura se obtuvo en 59447, no 59444. El ejecutor P04 original se detiene al terminar las pruebas; el iniciador visual independiente mantiene su proceso activo.

## Autenticación LAB recuperada: CERRADA

El mensaje inicial fue **“Acceso rechazado”**. Se utilizó el mecanismo autorizado ya existente `server\tools\MvcLabSeed\MvcLabSeed.csproj`, **solo** contra la base desechable LAB `POSFlutter_MvcLab_P04Visual_ac22f4bd8dd2407f9b488351d08156ca` sobre `(localdb)\POSWEB_V44_LAB_20261018`, para el usuario LAB `web.lab`. El operador proporcionó la contraseña mediante entorno de proceso; **no documentarla ni persistirla**. El mecanismo usa `ConnectionStrings__SqlServer` y `POSFLUTTER_LAB_PASSWORD`.

Antes de modificar la identidad LAB se realizó respaldo de SQL: `artifacts\P04_VISUAL_MANUAL\backup\MVC_LAB_BEFORE_IDENTITY_20261105_214347.bak`. Según la evidencia compartida: `LAB_BACKUP=PASS`, `LAB_IDENTITY=PASS`, `SQL_SCOPE=LAB_ONLY`, `IIS_CHANGES=NONE`. Después el usuario inició sesión y mostró el Dashboard de administrador en `https://localhost:59447/`.

**NO repetir `MvcLabSeed`, NO restablecer la contraseña y NO ejecutar scripts que roten identidades por rutina.** Si se pierde acceso, primero determinar la causa y validar el respaldo. Nunca versionar `.bak`, contraseñas, tokens, cookies, cadenas con secretos, DPAPI, `key.properties`, keystores ni datos LAB sensibles.

## Reproducción autorizada solo ante reinicio/caída

1. Confirmar que la instancia realmente está caída. Si 59444 o 59447 siguen funcionando, **no ejecutarlos otra vez**. Probar `/health` mediante HTTPS con comprobación de certificado.
2. Consultar el manifest y los hashes de la publicación antes de arrancar. No usar un `release.zip` distinto sin comparar su contenido.
3. Para 59444, usar **solo ante caída** el `RECUPERAR_POSFLUTTER_P04_KESTREL_V2.ps1` de `deploy/recovery`, respetando LAB y sus guardias; no ejecutarlo para cerrar Git.
4. Para una instancia visual separada, `INICIAR_POSWEB_P04_CERTIFICADO_V2.ps1` muestra el puerto elegido y arranca `dotnet PosFlutter.Web.dll` con `ASPNETCORE_ENVIRONMENT=Development`, `ASPNETCORE_URLS=https://localhost:<puerto>` y `ConnectionStrings__SqlServer` apuntando a LocalDB LAB; no contiene passwords. **No usar en red del cliente ni como instalador productivo**.
5. Si el acceso falla, recuperar evidencia diagnóstica sin resetear identidades ni modificar SQL de producción.

## Git, versiones y fuente de verdad

- La publicación binaria aprobada y un checkpoint documental **no prueban que todos los cambios fuente estén confirmados en Git**. Antes de liberar, comparar las fuentes vigentes, los hashes de los binarios, la rama actual y los cambios pendientes. No consolidar código por simple equivalencia de DLL.
- El checkpoint local solo debe agregar los scripts/manifest de recuperación, esta guía, una captura de evidencia desensibilizada, y una nota aditiva a los documentos de estado existentes **si están limpios y no conflictuados**. Preservar absolutamente otros cambios preparados en el índice.
- Prohibido `git add .`, `git reset --hard`, `git clean`, commits de otros módulos y `git push` sin autorización expresa. Si Git no cubre la raíz canónica, **detener el commit sin hacer `git init`** y entregar el paquete de recuperación independiente.
- Después del commit verificar hash HEAD, listado exacto de archivos, estado del índice preexistente y las dos URL; un commit local NO significa remoto actualizado.
- Documento contractual principal en repo: `POSWEB_CIERRE_COMERCIAL.md`; estado operativo: `POSWEB_EXECUTION_STATE.md`; estado de entrega: `DELIVERY_STATUS.md`. Evitar archivos equivalentes duplicados si esos documentos ya existen.

## Pendientes reales de entrega (no reabrir lo aprobado)

1. Cerrar Git sin mezclar trabajo pendiente o secretos; documentar hash de commit real y confirmar respaldo.
2. Congelar/consolidar el código fuente que corresponde al candidato funcional y registrar hashes frente a las publicaciones aprobadas.
3. Verificar contra criterios pendientes de la matriz contractual la operación completa: caja, venta/cobro, FIFO, compras, inventario y sincronización Android, **solo donde no exista PASS vigente**. El Dashboard autenticado no certifica estas transacciones.
4. Preparar servidor comercial e instancia SQL apta para servicio, identidad de aplicación, TLS/hostname comercial, respaldo/reversión; resolver el error IIS sin repetir parches de hostname fallidos. Publicar en destino autorizado, probar operación tras reinicio.
5. Resolver legítimamente la firma APK original; verificar instalación/actualización y sincronización extremo a extremo con web. No reemplazar certificado sin evaluar incompatibilidad de actualizaciones.
6. Aceptación final del cliente y entrega documentada. Producción permanece `NO_GO` hasta certificación, autorización y operación real.

**Regla máxima:** preservar la versión que funciona, no repetir P04, no volver a tocar credenciales LAB y no declarar entrega terminada por una captura o por un ZIP.

**Referencia a conversación compartida:** `https://chatgpt.com/share/6aed5bd4-be9c-83e8-a03b-c426811896a6` (no se pudo extraer el texto completo desde el entorno de ChatGPT; el proceso anterior se reconstruyó de los scripts y evidencias aportados por el usuario).
