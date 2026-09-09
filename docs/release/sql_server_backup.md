# Backup y restore de SQL Server productivo

Estado FASE 19: `PENDING_EXTERNAL`. Este procedimiento requiere acceso administrativo al servidor y no fue ejecutado por el agente actual.

Intento 2026-09-08: desde `SISTEMAS`, `DESKTOP-L6KS3RK\SERVER` no estuvo accesible por red. La auditoría de recovery model, historial, Agent, espacio, backup y restore no pudo ejecutarse. Realice los pasos siguientes directamente en `DESKTOP-L6KS3RK`; no exponga 1433 para habilitar esta tarea.

## Política mínima

- Backup full diario de `POSFlutter`; diferencial según volumen y objetivo RPO.
- Backups de log frecuentes si se usa modelo `FULL`; verifique primero el recovery model.
- Retención mínima acordada por negocio (recomendado: diarios 14 días, semanales 8 semanas y mensuales 12 meses).
- Copia secundaria cifrada fuera del volumen/host de SQL Server, con acceso restringido.
- Alertas por fallo, espacio insuficiente y antigüedad del último backup.
- Prueba de restauración periódica en una base aislada, nunca sobre producción.

## Ejecución controlada

Use SQL Server Agent o la herramienta corporativa de backup con una identidad administrativa; `posflutter_api` no debe recibir permisos de backup/migración. El nombre y destino deben incluir fecha UTC y no contener credenciales.

Antes de go-live registre: archivo full creado, `RESTORE VERIFYONLY` satisfactorio, checksum cuando la versión lo soporte, copia secundaria confirmada y responsable/retención. Después restaure en una base temporal aislada, ejecute `DBCC CHECKDB`, confirme tablas/migraciones y elimine la base temporal mediante el cambio operativo autorizado.

## Evidencia requerida

```text
CENTRAL_DB_BACKUP=PASS
BACKUP_UTC=
BACKUP_LOCATION_PRIMARY=
BACKUP_LOCATION_SECONDARY=
RESTORE_VERIFYONLY=PASS
RESTORE_TEST_DATABASE=PASS
DBCC_CHECKDB=PASS
EXECUTED_BY=
```

No registre passwords, connection strings ni claves en esta evidencia.
