# Production readiness map

Auditoría de FASE 19 sobre `22b0384b651d2ea1eb3ae52ac62841cf896c085f`.

| AREA | CURRENT_STATE | RISK | PRODUCTION_REQUIREMENT | ACTION_REQUIRED | SEVERITY |
|---|---|---|---|---|---|
| Git | `main` limpio y sincronizado | Bajo | Fuente reproducible | Verificar al cierre | BLOCKING |
| Versión Android | `0.1.0+1` | Media | Identidad productiva estable | Adoptar `1.0.0+1`; conservar versionCode 1 | BLOCKING |
| Firma | Keystore externo, fallback debug prohibido | Bajo | Misma identidad y secretos externos | Verificar APK y segunda copia | BLOCKING |
| API Flutter | `API_BASE_URL` por dart-define; default de emulador | Alta | URL HTTPS real por despliegue | Compilar artefacto con URL productiva | BLOCKING |
| Backend config | SQL/JWT vacíos en Git; startup fail-closed | Bajo | Secretos por ambiente | Documentar variables y HTTPS | BLOCKING |
| JWT/autorización | Issuer/audience/lifetime/tenant y roles validados | Bajo | Mantener políticas probadas | Regresión completa | BLOCKING |
| HTTPS | Redirección backend; cliente sin bypass TLS | Bajo | Certificado válido/reverse proxy | Documentar despliegue | BLOCKING |
| SQLite | V5, FK/integrity/rollback validados | Bajo | Fresh install y upgrade sin pérdida | Ejecutar gates y tests | BLOCKING |
| Dinero | Centavos enteros, parser usaba `double` | Media | Conversión decimal exacta | Sustituir parser y probar | BLOCKING |
| Offline/FIFO/caja | Persistencia y autorización cubiertas | Bajo | Venta sin red y reinicio seguro | Acceptance automatizada/evidencia | BLOCKING |
| Sync | Outbox, idempotencia, rechazo terminal y cursor probados | Bajo | Sin pérdida/duplicados | Regresión cliente/servidor | BLOCKING |
| Backup/restore | Integridad, reauth y copia preventiva | Bajo | Runbook y prueba | Documentar y ejecutar tests | BLOCKING |
| Backend publish | Build/test disponibles | Media | Publish Release reproducible | Ejecutar publish y startup smoke | BLOCKING |
| Dependencias | Sin inventario final | Media | Auditar vulnerabilidades/obsolescencia | Ejecutar herramientas, no upgrade masivo | BLOCKING |
| Kotlin plugin | Warning de compatibilidad futura | Bajo | Release actual compila | Registrar deuda, no migrar al final | NON_BLOCKING |
| Dispositivo/UAT | Depende de ADB y validación humana | Media | Smoke si hay dispositivo; UAT separado | Detectar ADB y entregar checklist | NON_BLOCKING |

No se autoriza cerrar como candidata mientras exista un hallazgo crítico/alto abierto o el APK no use un endpoint HTTPS de despliegue explícito.
