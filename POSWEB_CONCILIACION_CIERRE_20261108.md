# POSFLUTTER WEB — Adenda canónica de conciliación antirreproceso

Fecha: 2026-11-08. Fuente analizada: `POSWEB_CONCILIACION_ANTIRREPROCESO.txt` (511 líneas), commit `298452913dfd4b9ca2c8c678a4c32f05387fcc4c`.

## Precedencia de evidencias
1. Resultado final posterior y comparable prevalece sobre fallos de candidatos anteriores, **solo dentro del mismo alcance**.
2. PASS de build, ruta HTTP o captura no sustituye PASS funcional E2E, rollback ni producción.
3. Si difieren artefacto, host, datos, versión o criterio, conservar ambas evidencias y marcar pendiente de conciliación; no reejecutar por defecto.
4. No modificar los 14 archivos Git rastreados ni borrar los no rastreados durante la conciliación.

## Registro consolidado
| ID | Estado a preservar | Evidencia | Restricción / pendiente |
|---|---|---|---|
| P04-VISUAL | VERIFICADO históricamente R7.4, seis vistas | `DELIVERY_STATUS.md`, bloque R7.4, `artifacts/P04_VISUAL_LOCAL_20261107_040200/RESULTADOS.json` | No reabrir por FAIL antiguos R3/R7/R8; verificar correspondencia de candidato solo si hay cambio real |
| P04-HTTPS | VERIFICADO históricamente | `artifacts/P04_HTTPS_ISOLATED_20261104_134055`, 5/5 y tres sesiones | No sustituye E2E autenticado en IIS A15 |
| A01-A07 | COMPLETADO_VERIFICADO según matriz | `POSWEB_ACCEPTANCE_BASELINE.md`, P037/P038/P042 | No repetir sin regresión nueva |
| A08/A16 | COMPLETADO_VERIFICADO según actualización R7.4 | `POSWEB_ACCEPTANCE_BASELINE.md` y `DELIVERY_STATUS.md` | Ignorar narrativas históricas previas que siguen diciendo FAIL |
| A14 | VERIFICADO, 13 migraciones y 28 tablas SQL LAB | `POSWEB_ACCEPTANCE_BASELINE.md` | No recrear base ni migraciones |
| A15-SQLITE | VERIFICADO 9/9 | `artifacts/A15_SQLITE_TARGETED_20261108_085814/A15_CERTIFICACION_9_TESTS.txt` | FAIL inicial de runner es histórico, no estado final |
| A15-REG | VERIFICADO históricamente 136/136 | `artifacts/p042-catalog-coverage-r2-xunit-20261020.log` | No repetir suite sin cambios relevantes; evidencia de versión anterior |
| A15-SEED | EJECUTADO, CERRADO | `artifacts/A15_AUTHORIZED_SEED_20261108_091446` | No resembrar |
| A13-IIS | DISPONIBILIDAD ACTUAL VERIFICADA | 2026-11-08 IIS sitio/pool Started, TCP 8443, `/health/live` 200, `/Home/Login` 200 | E2E comercial autenticado en IIS no acreditado por health |
| A17-BACKUP | VERIFICADO 133 archivos y SHA256 sin diferencias | `artifacts/A17_BACKUP_REAL_20261107_111930/backup` | No repetir backup |
| A17-RESTORE | Restauración efectiva de 140 archivos SHA256 PASS y health 200/200 | `artifacts/A15_MODELSTATE_LAB_20261108_224150/iis_original` y salida recuperación | Conciliar contra criterio de rollback contractual antes de declarar A17 certificado |
| A15-AUTH-IIS | PENDIENTE de certificación específica | CURL V11 POST 200 sin sesión; `A15_BUSINESSEMPTY=true` | Comparar contrato P04 y cliente A15, sin nueva instrumentación o publicación inicial |
| A09/A10/A11/A12 | Preservar estados de matriz | `POSWEB_ACCEPTANCE_BASELINE.md` | A10/A11 NO_APLICA_JUSTIFICADO; A09/A12 completados |
| A18 | EN_DESARROLLO / BLOQUEADO por autorización | Matriz de aceptación y cierre comercial | No copiar datos sin autorización |
| P11 | BLOQUEADO por credenciales de firma | `POSWEB_CIERRE_COMERCIAL.md` | No crear keystore sustituta |
| A19 | BLOQUEADO | Matriz de aceptación | No desplegar producción sin autorización |

## Contradicciones y criterio de resolución
- `POSWEB_CIERRE_COMERCIAL.md` indica productos/categorías implementado sin verificar, mientras R7.4 aprueba la **paridad visual**: no equiparar paridad visual con alta/edición administrativa funcional. Conservar ambos alcances.
- `POSWEB_ACCEPTANCE_BASELINE.md` mantiene A13/A17 implementados no verificados pese a disponibilidad IIS y recuperación efectiva posteriores: documentar estas evidencias, sin promover a certificación completa automáticamente.
- `POSWEB_CIERRE_COMERCIAL.md` expresa 91.6% y matriz de aceptación 92.2%: usar 92.2% como valor **histórico ponderado**, no como avance actual calculado.
- `POSWEB_A13_A17_HISTORIAL_CONTINUIDAD.md` contiene intentos A15 SQLite FAIL anteriores al resultado final 9/9 PASS: conservar trazabilidad y no reabrir.
- La auditoría documental filtró líneas sensibles y extrajo como máximo 100 coincidencias por documento: no constituye revisión exhaustiva de archivos completos ni código fuente.

## Acción siguiente autorizable y de mínimo coste
Leer, sin ejecutar ni desplegar, los contratos de `HomeController`, `LoginForm`, `WebTenantSession`, la vista Login y el script CURL V11 para identificar la discrepancia del `BusinessGlobalId`. Solo si aparece diferencia demostrada, realizar parche mínimo y prueba dirigida con rollback; no repetir P04 ni seed. En paralelo conciliar criterios A17 contra recuperación ya registrada, sin nuevo backup.

## Seguridad y entrega
Sin modificaciones de fuentes, SQL, IIS ni Git durante esta conciliación. Estado producción: NO_GO. Estado de avance global: 92.2% histórico, no recalculado.
