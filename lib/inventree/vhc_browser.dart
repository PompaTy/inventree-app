import "package:inventree/api.dart";
import "package:inventree/inventree/vhc.dart";

typedef VhcReadRequest =
    Future<APIResponse> Function(String path, Map<String, String> params);

class VhcReadException implements Exception {
  const VhcReadException(this.status);
  final int status;
}

class VhcPage<T> {
  const VhcPage(this.items, {this.hasMore = false});
  final List<T> items;
  final bool hasMore;
}

/// Reads are bound to the account which opened the screen.
class VhcBrowser {
  VhcBrowser({VhcReadRequest? request}) : _request = request;

  final VhcReadRequest? _request;
  final _profile = InvenTreeAPI().profile;
  final _server = InvenTreeAPI().profile?.server;
  final _token = InvenTreeAPI().profile?.token;
  InvenTreeAPI get api => InvenTreeAPI();
  bool get canRead =>
      identical(_profile, api.profile) &&
      _server == api.profile?.server &&
      _token == api.profile?.token &&
      api.vhcCapabilities.supports("boxes") &&
      api.vhcCapabilities.allows("read");

  Future<dynamic> _get(String path, Map<String, String> params) async {
    if (!canRead) throw const VhcReadException(403);
    // Encode query values once; search text may contain &, #, + or Unicode.
    final response =
        await (_request?.call(path, params) ??
            api.get(
              "$path?${Uri(queryParameters: params).query}",
              optional: true,
            ));
    if (!canRead) throw const VhcReadException(403);
    if (response.statusCode != 200) throw VhcReadException(response.statusCode);
    return response.data;
  }

  static VhcPage<T> parsePage<T>(
    dynamic data,
    T Function(Map<String, dynamic>) parse,
  ) {
    final dynamic rows = data is Map<String, dynamic> ? data["results"] : data;
    if (rows is! List<dynamic> ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      throw const VhcReadException(0);
    }
    return VhcPage(
      rows.cast<Map<String, dynamic>>().map(parse).toList(),
      hasMore: data is Map<String, dynamic> && data["next"] != null,
    );
  }

  Future<VhcPage<VhcBox>> boxes(
    int offset,
    Map<String, String> filters,
  ) async => parsePage(
    await _get("vhc/box/", {
      "ordering": "box_number",
      ...filters,
      "limit": "25",
      "offset": "$offset",
    }),
    VhcBox.fromJson,
  );

  Future<VhcBox> box(int pk) async {
    final data = await _get("vhc/box/$pk/", {});
    if (data is! Map<String, dynamic> || data["pk"] != pk) {
      throw const VhcReadException(0);
    }
    return VhcBox.fromJson(data);
  }

  Future<VhcPage<VhcBoxEvent>> events(int pk, int offset) async => parsePage(
    await _get("vhc/event/", {
      "box": "$pk",
      "ordering": "-timestamp",
      "limit": "25",
      "offset": "$offset",
    }),
    VhcBoxEvent.fromJson,
  );

  Future<List<Map<String, dynamic>>> choices(
    String path,
    String search, {
    String? shipment,
  }) async {
    final page = parsePage(
      await _get(path, {
        "search": search,
        "limit": "25",
        if (shipment != null) "shipment": shipment,
      }),
      (row) => row,
    );
    return page.items;
  }
}
