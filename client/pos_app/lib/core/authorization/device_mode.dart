enum DeviceMode {
  pointOfSale('PointOfSale'),
  adminReadOnly('AdminReadOnly');

  const DeviceMode(this.wireValue);

  final String wireValue;

  static DeviceMode? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim();

    for (final mode in DeviceMode.values) {
      if (mode.wireValue == normalized) {
        return mode;
      }
    }

    return null;
  }
}
