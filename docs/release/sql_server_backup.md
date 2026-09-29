# Backup y restore de SQL Server productivo

## Estado de certificacion

P009.3 fue ejecutado contra el entorno autorizado de SQL Server y quedo cerrado en PASS.

Servidor: DESKTOP-L6KS3RK\SERVER
Base productiva: POSFlutter

La base productiva permanecio ONLINE. La restauracion de prueba se realizo exclusivamente sobre una base temporal aislada.

## Politica minima

- Backup full diario de POSFlutter; diferencial segun volumen y objetivo RPO.
- Backups de log cuando la estrategia adoptada y el recovery model lo requieran.
- Retencion definida por negocio.
- Copia secundaria protegida fuera del volumen o host principal de SQL Server.
- Acceso restringido a los respaldos.
- Alertas por fallo, espacio insuficiente y antiguedad del ultimo backup.
- Prueba periodica de restauracion en una base aislada, nunca directamente sobre produccion.

## Procedimiento certificado P009.3

El backup de certificacion fue generado como FULL con COPY_ONLY y CHECKSUM.

Posteriormente se ejecuto:

1. RESTORE VERIFYONLY WITH CHECKSUM.
2. Restore aislado a POSFlutter_DR_P009.
3. Confirmacion de la base recuperada en estado ONLINE.
4. DBCC CHECKDB.
5. Comparacion de las 23 tablas de usuario.
6. Comparacion exacta de conteos de filas en las 23 tablas.
7. Eliminacion controlada de POSFlutter_DR_P009.
8. Confirmacion de que POSFlutter productiva permanecio ONLINE.

La cuenta de aplicacion posflutter_api no debe recibir permisos administrativos de backup, restore o migracion.

## Evidencia P009.3

Backup certificado:

C:\Backups\POSFlutter\SQL\POSFlutter_P009_3C_20260925_001447.bak

SHA-256:

FB84B56F28360D9C5B500E7285E19051E868B1D20303D04B77D155BDF250BA4B

Resultados:

CENTRAL_DB_BACKUP=PASS
BACKUP_TYPE=FULL_COPY_ONLY
BACKUP_CHECKSUM=PASS
RESTORE_VERIFYONLY=PASS
RESTORE_TEST_DATABASE=POSFlutter_DR_P009
RESTORE_TEST_DATABASE_RESULT=PASS
RECOVERY_DATABASE_ONLINE=PASS
DBCC_CHECKDB=PASS
PRODUCTION_USER_TABLE_COUNT=23
RECOVERY_USER_TABLE_COUNT=23
TABLE_STRUCTURE_COMPARISON=PASS
ROW_COUNT_COMPARISON_23_OF_23=PASS
RECOVERY_DATABASE_CLEANUP=PASS
PRODUCTION_DATABASE_ONLINE_AFTER_TEST=PASS

La ruta anterior es evidencia de la certificacion P009.3 y no constituye un contrato permanente de ubicacion o retencion.

## Seguridad

No registrar passwords, connection strings con secretos, JWT signing keys, tokens, claves privadas ni material de firma Android en esta evidencia.

Una restauracion sobre produccion requiere autorizacion explicita y un procedimiento operativo de recuperacion separado.
