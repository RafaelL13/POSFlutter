# FASE 19 status

Actualizado: 2026-09-08. HEAD auditado: `6ca83d2482fd6f518456724a72539bbb1fc290f1`.

## Evidencia técnica disponible

- Flutter analyze PASS; tests `244/244` PASS.
- Backend build PASS; tests `60/60` PASS; publish y startup health PASS.
- Migración EF inicial versionada y aplicada externamente a SQL Server productivo.
- API pública `https://api.lasaguilasmercadodelmar.com/health`: HTTP 200 `Healthy`, reconfirmado el 2026-09-08.
- APK release `1.0.0+1` construido con `--dart-define=API_BASE_URL=https://api.lasaguilasmercadodelmar.com`.
- Firma v2, un firmante y certificado SHA-256 oficial verificados.
- AVD limpio `POSFlutter_Phase19_Clean`: instalación, proceso, actividad y ausencia de fatal errors PASS.
- Keystore secundario en `D:\POSFlutter_Backup\signing\posflutter-release.jks` fue verificado externamente con el mismo SHA-256. La unidad D: no está montada en la sesión del 2026-09-08, por lo que no se repitió la lectura.
- Structural gate, SQLite V5, secrets scan, autorización, FIFO, sync e idempotencia PASS según la regresión registrada.

## Pendientes obligatorios externos

1. Backup full de SQL Server, copia con retención y restore real verificado siguiendo `sql_server_backup.md`.
2. Primera tablet física, bootstrap con datos reales y validación de persistencia/sync siguiendo `first_production_device.md`.
3. UAT humana por roles y UAT offline-first completa.

## Intento de auditoría SQL del 2026-09-08

La sesión actual corre en el host `SISTEMAS`. La conexión integrada a `DESKTOP-L6KS3RK\SERVER` no encontró la instancia y el host no respondió a ping ni a una comprobación TCP. No se abrió ningún puerto, no se cambiaron servicios y no se ejecutó SQL contra producción. El backup y restore deben ejecutarse localmente en el servidor productivo con identidad administrativa siguiendo `sql_server_backup.md`.

El commit documental local tampoco pudo publicarse: GitHub respondió HTTP 403 porque la credencial activa `fullstackdevsystems` no tiene acceso a `RafaelL13/POSFlutter`. Se requiere corregir la autenticación Git antes del push; no se alteraron credenciales automáticamente.

Por estos pendientes: `PHASE=19 NOT_CLOSED`, `PRODUCTION_CANDIDATE=NO`, `CLIENT_UAT=PENDING_EXTERNAL`. No crear tag ni bundle final.
