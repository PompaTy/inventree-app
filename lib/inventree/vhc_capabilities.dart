enum VhcAvailability {
  unknown,
  available,
  unsupported,
  unauthorized,
  unavailable,
}

/// Custom server capabilities are independent of the upstream API version.
class VhcCapabilities {
  const VhcCapabilities({
    this.availability = VhcAvailability.unknown,
    this.version = 0,
    this.features = const {},
    this.actions = const {},
    this.stockFields = const {},
  });

  factory VhcCapabilities.fromResponse(int status, dynamic data) {
    if (status == 404) {
      return const VhcCapabilities(availability: VhcAvailability.unsupported);
    }
    if (status == 401 || status == 403) {
      return const VhcCapabilities(availability: VhcAvailability.unauthorized);
    }
    if (status != 200 || data is! Map<String, dynamic>) {
      return const VhcCapabilities(availability: VhcAvailability.unavailable);
    }
    final version = int.tryParse("${data["version"]}") ?? 0;
    if (version != 1) {
      return VhcCapabilities(
        availability: VhcAvailability.unsupported,
        version: version,
      );
    }
    Set<String> enabled(dynamic values) => values is Map<String, dynamic>
        ? values.entries
              .where((entry) => entry.value == true)
              .map((entry) => entry.key.toString())
              .toSet()
        : <String>{};
    return VhcCapabilities(
      availability: VhcAvailability.available,
      version: version,
      features: Set.unmodifiable(enabled(data["features"])),
      actions: Set.unmodifiable(enabled(data["actions"])),
      stockFields: Set.unmodifiable(
        data["stock_fields"] is List<dynamic>
            ? (data["stock_fields"] as List<dynamic>).whereType<String>()
            : <String>[],
      ),
    );
  }

  final VhcAvailability availability;
  final int version;
  final Set<String> features;
  final Set<String> actions;
  final Set<String> stockFields;

  bool get available => availability == VhcAvailability.available;
  bool supports(String feature) => available && features.contains(feature);
  bool allows(String action) => available && actions.contains(action);
  bool hasStockField(String field) => available && stockFields.contains(field);
}
