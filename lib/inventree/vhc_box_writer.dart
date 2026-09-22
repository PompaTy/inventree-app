import "dart:convert";
import "package:inventree/api.dart";
import "package:inventree/inventree/vhc_api.dart";
import "package:inventree/inventree/vhc_box_draft.dart";
import "package:inventree/inventree/vhc_browser.dart";

typedef VhcBoxWriteRequest =
    Future<APIResponse> Function(
      String path,
      String method,
      Map<String, dynamic> body,
    );

class VhcBoxWriter {
  VhcBoxWriter(this.browser, {VhcBoxWriteRequest? request})
    : _request = request;
  final VhcBrowser browser;
  final VhcBoxWriteRequest? _request;
  bool canSave(bool editing) =>
      browser.canRead &&
      InvenTreeAPI().vhcCapabilities.allows(
        editing ? "edit_box" : "create_box",
      );

  Future<APIResponse> save(VhcBoxDraft draft) async {
    if (!canSave(draft.editing)) throw const VhcReadException(403);
    final body = draft.editing
        ? VhcApi.revisionBody(draft.original!, draft.toJson())
        : draft.toJson();
    final path = draft.original?.url ?? "vhc/box/";
    final method = draft.editing ? "PATCH" : "POST";
    final APIResponse response;
    if (_request != null) {
      response = await _request(path, method, body);
    } else {
      final api = InvenTreeAPI();
      final request = await api.apiRequest(path, method);
      // apiRequest awaits settings before applying auth headers. Recheck before sending.
      if (!canSave(draft.editing)) {
        request?.abort();
        throw const VhcReadException(403);
      }
      if (request == null) return APIResponse(error: "Request unavailable");
      response = await api.completeRequest(request, data: jsonEncode(body));
    }
    if (!canSave(draft.editing)) throw const VhcReadException(403);
    return response;
  }
}
