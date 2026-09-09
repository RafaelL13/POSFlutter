# Production readiness map

Auditoría actualizada de FASE 19 sobre `6ca83d2482fd6f518456724a72539bbb1fc290f1`.

| AREA | CURRENT_STATE | RISK | PRODUCTION_REQUIREMENT | ACTION_REQUIRED | SEVERITY |
|---|---|---|---|---|---|
| Git | `main` limpio y sincronizado | Bajo | Fuente reproducible | Verificar al cierre | BLOCKING |
| Versión Android | `1.0.0+1` | Bajo | Identidad productiva estable | Mantener para primera producción | KEEP |
| Firma | Keystore externo, fallback debug prohibido y segunda copia verificada | Bajo | Misma identidad y secretos externos | Mantener copias seguras | KEEP |
| API Flutter | Release construido con `API_BASE_URL=https://api.lasaguilasmercadodelmar.com`; health público 200/Healthy | Bajo | URL HTTPS real por despliegue | Mantener dart-define en cada build productivo | KEEP |
| Backend config | SQL/JWT vacíos en Git; startup fail-closed | Bajo | Secretos por ambiente | Documentar variables y HTTPS | BLOCKING |
| JWT/autorización | Issuer/audience/lifetime/tenant y roles validados | Bajo | Mantener políticas probadas | Regresión completa | BLOCKING |
| HTTPS | Redirección backend; cliente sin bypass TLS | Bajo | Certificado válido/reverse proxy | Documentar despliegue | BLOCKING |
| SQLite | V5, FK/integrity/rollback validados | Bajo | Fresh install y upgrade sin pérdida | Ejecutar gates y tests | BLOCKING |
| Dinero | Centavos enteros, parser usaba `double` | Media | Conversión decimal exacta | Sustituir parser y probar | BLOCKING |
| Offline/FIFO/caja | Persistencia y autorización cubiertas | Bajo | Venta sin red y reinicio seguro | Acceptance automatizada/evidencia | BLOCKING |
| Sync | Outbox, idempotencia, rechazo terminal y cursor probados | Bajo | Sin pérdida/duplicados | Regresión cliente/servidor | BLOCKING |
| Backup/restore | Integridad, reauth y copia preventiva | Bajo | Runbook y prueba | Documentar y ejecutar tests | BLOCKING |
| Backend publish | Publish/startup smoke ejecutados; IIS loopback `127.0.0.1:8080` tras Cloudflare Tunnel | Bajo | Publish Release reproducible | Mantener despliegue sin listener público en 8080 | KEEP |
| Dependencias | Sin inventario final | Media | Auditar vulnerabilidades/obsolescencia | Ejecutar herramientas, no upgrade masivo | BLOCKING |
| Kotlin plugin | Warning de compatibilidad futura | Bajo | Release actual compila | Registrar deuda, no migrar al final | NON_BLOCKING |
| Dispositivo/UAT | AVD limpio pasó install/launch; tablet física y UAT no ejecutadas | Alta operativa | Primera tablet y UAT reales | Ejecutar checklist externo antes de aprobación productiva | BLOCKING |
| SQL Server backup | No hay evidencia de backup/restore productivo ejecutado | Alta operativa | Full backup, copia separada y restore verificado | Ejecutar `sql_server_backup.md` con identidad administrativa | BLOCKING |

No se autoriza cerrar FASE 19 mientras el backup/restore central, la primera tablet y el UAT offline-first permanezcan pendientes. El endpoint HTTPS y el smoke Android ya están resueltos.
