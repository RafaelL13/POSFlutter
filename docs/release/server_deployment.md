# Despliegue del servidor

Requisitos: .NET 10, SQL Server soportado, cuenta de servicio con privilegios mínimos, HTTPS válido y sistema de secretos.

Publique `server/src/Api/Api.csproj` en Release. Configure externamente:

- `ConnectionStrings__SqlServer` con cifrado según infraestructura;
- `Jwt__SigningKey` aleatoria y robusta;
- `Jwt__Issuer=POSFlutter` y `Jwt__Audience=POSFlutter.Client`, salvo migración coordinada;
- logging y URLs del host/reverse proxy.

La API falla al iniciar sin cadena SQL o signing key. Development Swagger sólo se habilita en Development. Producción debe terminar TLS en IIS/reverse proxy o Kestrel, reenviar correctamente el esquema HTTPS y restringir CORS/host/firewall conforme a la red. Flutter jamás conecta directamente a SQL Server.

Tras desplegar: compruebe `/health`, login/enrollment, push/pull y logs sin tokens ni payloads financieros sensibles. Configure backups SQL Server, retención, prueba periódica de restore, monitor de salud, errores 5xx y operaciones “Requiere atención”.
