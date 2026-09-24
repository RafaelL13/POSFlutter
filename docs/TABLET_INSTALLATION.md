# Tablet installation

The tablet installer requires one authorized ADB device, checks the APK SHA-256, verifies the release signing certificate with `apksigner`, checks Android API level, installs without clearing data, validates installed package/version, and launches the app.

Use a release manifest as the source for hash, certificate, version name, and version code. ADB installation alone is not enrollment: follow first-run and enrollment against the HTTPS API, then verify that local login and selling work while disconnected.

`Reset-POSFlutterTablet.ps1` is destructive by design and requires interactive confirmation. It is only for the clean-install UAT after backup/recovery approval.
