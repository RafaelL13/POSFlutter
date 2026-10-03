final class AppEnvironment {
  const AppEnvironment._();
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.lasaguilasmercadodelmar.com',
  );
  static const syncPageSize = 100;
}
