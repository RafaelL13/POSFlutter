# Instalación y actualización Android

Requisitos: Android API 24 o posterior, almacenamiento disponible, hora del dispositivo correcta y acceso HTTPS al backend para sincronizar.

1. Verifique SHA-256 del APK y certificado de firma.
2. Autorice instalación desde la fuente controlada si la política del dispositivo lo exige.
3. Instale el APK. Para actualización por ADB use `adb install -r <APK>`.
4. Confirme versión `1.0.0` y complete enrollment/login.
5. Ejecute una venta controlada, sincronización y respaldo.

Antes de desinstalar, sincronice y cree un respaldo local: Android puede eliminar SQLite al desinstalar. Si una actualización falla, no desinstale ni borre datos; consulte el rollback de `production_checklist.md`. Una versión anterior sólo puede instalarse si comparte firma y es compatible con schema V5.
