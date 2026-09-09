# Despliegue del servidor

Requisitos: .NET 10, SQL Server soportado, cuenta de servicio con privilegios mínimos, HTTPS válido y sistema de secretos.

Publique `server/src/Api/Api.csproj` en Release. Configure externamente:

- `ConnectionStrings__SqlServer` con cifrado según infraestructura;
- `Jwt__SigningKey` aleatoria y robusta;
- `Jwt__Issuer=POSFlutter` y `Jwt__Audience=POSFlutter.Client`, salvo migración coordinada;
- logging y URLs del host/reverse proxy.

La API falla al iniciar sin cadena SQL o signing key. Development Swagger sólo se habilita en Development. Producción debe terminar TLS en IIS/reverse proxy o Kestrel, reenviar correctamente el esquema HTTPS y restringir CORS/host/firewall conforme a la red. Flutter jamás conecta directamente a SQL Server.

Tras desplegar: compruebe `/health`, login/enrollment, push/pull y logs sin tokens ni payloads financieros sensibles. Configure backups SQL Server, retención, prueba periódica de restore, monitor de salud, errores 5xx y operaciones “Requiere atención”.

## Topología productiva Las Águilas

- API pública: `https://api.lasaguilasmercadodelmar.com`.
- IIS escucha únicamente en `127.0.0.1:8080`; no exponga `0.0.0.0:8080`.
- Cloudflare Tunnel corre en el mismo servidor y reenvía a `http://127.0.0.1:8080`.
- SQL Server usa la base `POSFlutter`; el usuario runtime `posflutter_api` tiene sólo `db_datareader` y `db_datawriter`.
- Migraciones EF se aplican con una identidad administrativa/deployment separada.
- No abra SQL Server/1433 a Internet ni puertos del módem para la API.

El health público fue verificado con HTTP 200 `Healthy`. Reinicio IIS/cloudflared y persistencia fueron probados externamente. Consulte `sql_server_backup.md` antes del go-live.
