# POSFlutter Business Branding Architecture

## Alcance

La identidad del negocio es un agregado opcional de `Business`. Nunca participa en ventas, compras, inventario, FIFO o caja y nunca condiciona la operación offline.

## Persistencia local

SQLite schema 7 añade a `businesses`: `display_name`, `logo_blob`, `logo_mime_type`, `primary_color` y `branding_updated_at`. Todos son anulables para migrar bases existentes sin pérdida. Los fallbacks son nombre legal, icono storefront y color original.

El logo admite PNG, JPEG o WebP, máximo 256 KiB. El color se almacena como RGB entero y sólo puede pertenecer a la paleta controlada. `BusinessBrandingRepository.save` valida `businessWrite` y confirma en una transacción el cambio local y su operación `Business/Update` de SyncQueue.

## Sincronización y compatibilidad

Los contratos `Business/Create`, `Business/Update` y pull incorporan campos opcionales. `brandingUpdatedAt` funciona como marcador de presencia: si falta, un cliente anterior no modifica branding; si existe, `logoBase64: null` elimina el logo determinísticamente. El servidor valida bytes, firma, MIME y límite sin registrar el Base64.

El backend mantiene aislamiento por tenant, control de versión e idempotencia existentes. La migración EF `AddBusinessBranding` sólo añade columnas anulables. Un servidor nuevo acepta payloads antiguos; un cliente nuevo opera por completo sin red y sincroniza posteriormente.

## Presentación

Riverpod carga branding desde SQLite antes del login y reconstruye `MaterialApp` con `ColorScheme.fromSeed`. Login conserva el layout keyboard-safe, y login, dashboard y drawer muestran nombre comercial y la identidad legible de sucursal/dispositivo sin IDs técnicos. Configuración sólo es accesible con `businessWrite`; Acerca de expone datos de soporte no sensibles.

## Respaldo y recuperación

El logo vive dentro del archivo SQLite. El mecanismo existente basado en `VACUUM INTO` y restauración íntegra preserva automáticamente las columnas de branding; la versión 7 se valida con `integrity_check` y `foreign_key_check`.

## Rollout

1. Desplegar backend y migración EF.
2. Publicar cliente schema 7.
3. Configurar identidad desde un usuario autorizado.
4. Permitir que SyncQueue replique el agregado.

El branding no es requisito para vender y sus fallos visuales siempre degradan al fallback seguro.
