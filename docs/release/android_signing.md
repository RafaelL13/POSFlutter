# Firma Android release

- Alias: `posflutter-release`.
- Certificado SHA-256: `1190414E227223377C1DAB5C199A0C3ECA70B57F193B27F82BE082C97843EFC4`.
- El keystore y `android/key.properties` permanecen fuera de Git.
- Configure localmente `storeFile`, `storePassword`, `keyAlias` y `keyPassword`, o las variables `POSFLUTTER_RELEASE_*` equivalentes.
- Nunca copie contraseñas, `key.properties`, `.jks` o `.keystore` al repositorio, logs o manifest de release.
- El build release falla si falta cualquier valor; nunca usa firma debug como fallback.

Verificación:

```powershell
C:\src\Android\Sdk\build-tools\36.0.0\apksigner.bat verify --verbose --print-certs <APK>
```

Compare siempre la huella completa antes de distribuir.
