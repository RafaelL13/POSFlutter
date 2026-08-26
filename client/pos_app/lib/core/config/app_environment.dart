final class AppEnvironment {
  const AppEnvironment._();
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://10.0.2.2:7043');
  static const syncPageSize = 100;
}
