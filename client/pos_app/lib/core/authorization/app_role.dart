enum AppRole {
  administrator('Administrator'),
  manager('Manager'),
  supervisor('Supervisor'),
  seller('Seller');

  const AppRole(this.wireValue);

  final String wireValue;

  static AppRole? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim();

    for (final role in AppRole.values) {
      if (role.wireValue == normalized) {
        return role;
      }
    }

    return null;
  }
}
