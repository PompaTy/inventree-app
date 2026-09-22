import "package:inventree/api.dart";
import "package:inventree/inventree/vhc.dart";

/// VHC actions use the custom capability contract, not the upstream API version.
class VhcApi {
  InvenTreeAPI get api => InvenTreeAPI();

  void _require(String action) {
    if (!api.vhcCapabilities.allows(action)) {
      throw StateError("VHC action is not available: $action");
    }
  }

  static Map<String, dynamic> revisionBody(
    VhcBox box,
    Map<String, dynamic> data,
  ) {
    if (box.pk <= 0 || box.revision < 1) {
      throw StateError("Load the box before changing it");
    }
    return {...data, "revision": box.revision};
  }

  static Map<String, dynamic> bulkMoveBody(
    List<VhcBox> boxes,
    int location, {
    String? status,
    String notes = "",
  }) {
    if (boxes.isEmpty ||
        boxes.map((box) => box.pk).toSet().length != boxes.length ||
        location <= 0) {
      throw ArgumentError("Select distinct boxes and a destination location");
    }
    for (final box in boxes) {
      revisionBody(box, {});
    }
    return {
      "boxes": boxes.map((box) => box.pk).toList(),
      "revisions": {for (final box in boxes) "${box.pk}": box.revision},
      "location": location,
      if (status != null) "status": status,
      "notes": notes,
    };
  }

  Future<APIResponse> scan(String barcode) {
    _require("read");
    if (!api.vhcCapabilities.supports("box_scan")) {
      throw StateError("Box scanning is not available");
    }
    return api.get("vhc/box/scan/", params: {"barcode": barcode.trim()});
  }

  Future<APIResponse> update(VhcBox box, Map<String, dynamic> changes) {
    _require("edit_box");
    return api.patch(box.url, body: revisionBody(box, changes));
  }

  Future<APIResponse> move(
    VhcBox box,
    int location, {
    String? status,
    String notes = "",
  }) {
    _require("move_box");
    if (location <= 0) throw ArgumentError.value(location, "location");
    return api.post(
      "${box.url}move/",
      body: revisionBody(box, {
        "location": location,
        if (status != null) "status": status,
        "notes": notes,
      }),
      expectedStatusCode: null,
    );
  }

  Future<APIResponse> changeStatus(
    VhcBox box,
    String status, {
    String notes = "",
  }) {
    _require("change_box_status");
    return api.post(
      "${box.url}status/",
      body: revisionBody(box, {"status": status, "notes": notes}),
      expectedStatusCode: null,
    );
  }

  /// Return validation/conflict responses intact; never silently retry a write.
  Future<APIResponse> bulkMove(
    List<VhcBox> boxes,
    int location, {
    String? status,
    String notes = "",
  }) {
    _require("bulk_move");
    return api.post(
      "vhc/box/bulk-move/",
      body: bulkMoveBody(boxes, location, status: status, notes: notes),
      expectedStatusCode: null,
    );
  }
}
