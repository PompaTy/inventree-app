import "package:inventree/inventree/model.dart";
import "package:flutter/material.dart";
import "package:inventree/widget/vhc/box_detail.dart";

/// Keep calendar dates independent of local or UTC timezone conversion.
String? vhcCalendarDate(dynamic value) {
  if (value is! String || !RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    return null;
  }
  return value;
}

/// Decimal quantities are stored as text, never round-tripped through double.
String vhcQuantity(dynamic value) {
  final text = value?.toString() ?? "";
  final match = RegExp(r"^(\d+)(?:\.(\d{1,5}))?$").firstMatch(text);
  if (match == null ||
      match[1]!.length > 10 ||
      !RegExp("[1-9]").hasMatch(text)) {
    throw FormatException(
      "Expected a positive quantity with at most five decimal places",
      text,
    );
  }
  return text;
}

/// Shared expiry rules used by stock forms and future box editors.
class VhcExpiry {
  static String labelFor(String sterile) =>
      {"S": "ER", "NS": "N/A"}[sterile] ?? "";

  static bool valid(String sterile, String? date, String label) =>
      const ["", "S", "NS"].contains(sterile) &&
      (date == null || vhcCalendarDate(date) != null) &&
      (label.isEmpty || (date == null && label == labelFor(sterile)));
}

abstract class VhcModel extends InvenTreeModel {
  VhcModel();
  VhcModel.fromJson(Map<String, dynamic> json) : super.fromJson(json);

  int? nullableId(String field) => int.tryParse(getString(field));
  String? dateOnly(String field) => vhcCalendarDate(getValue(field));
  Map<String, dynamic>? detail(String field) {
    final value = getValue(field);
    return value is Map<String, dynamic> ? value : null;
  }

  @override
  bool get canView => api.vhcCapabilities.allows("read");
  @override
  bool get canCreate => false;
  @override
  bool get canEdit => false;
  @override
  bool get canDelete => false;
}

class VhcTeam extends VhcModel {
  VhcTeam();
  VhcTeam.fromJson(Map<String, dynamic> json) : super.fromJson(json);
  @override
  String get URL => "vhc/team/";
  @override
  VhcTeam createFromJson(Map<String, dynamic> json) => VhcTeam.fromJson(json);
  String get code => getString("code");
  String get color => getString("color");
  bool get active => getBool("active");
  int get displayOrder => getInt("display_order", backup: 0);
  @override
  bool get canCreate => api.vhcCapabilities.allows("manage_teams");
  @override
  bool get canEdit => canCreate;
  @override
  bool get canDelete => canCreate;
}

class VhcShipment extends VhcModel {
  VhcShipment();
  VhcShipment.fromJson(Map<String, dynamic> json) : super.fromJson(json);
  @override
  String get URL => "vhc/shipment/";
  @override
  VhcShipment createFromJson(Map<String, dynamic> json) =>
      VhcShipment.fromJson(json);
  String get reference => getString("reference");
  String get state => getString("status");
  String get kind => getString("kind");
  int get year => getInt("year");
  String? get departureDate => dateOnly("departure_date");
  String? get arrivalDate => dateOnly("arrival_date");
  @override
  bool get canCreate => api.vhcCapabilities.allows("manage_shipments");
  @override
  bool get canEdit => canCreate;
  @override
  bool get canDelete => canCreate;
}

class VhcPallet extends VhcModel {
  VhcPallet();
  VhcPallet.fromJson(Map<String, dynamic> json) : super.fromJson(json);
  @override
  String get URL => "vhc/pallet/";
  @override
  VhcPallet createFromJson(Map<String, dynamic> json) =>
      VhcPallet.fromJson(json);
  int? get shipmentId => nullableId("shipment");
  int get number => getInt("number");
  String get displayName => getString("display_name");
  @override
  bool get canCreate => api.vhcCapabilities.allows("manage_pallets");
  @override
  bool get canEdit => canCreate;
  @override
  bool get canDelete => canCreate;
}

class VhcShipmentWindow extends VhcModel {
  VhcShipmentWindow();
  VhcShipmentWindow.fromJson(Map<String, dynamic> json) : super.fromJson(json);
  @override
  String get URL => "vhc/current-shipment/";
  @override
  VhcShipmentWindow createFromJson(Map<String, dynamic> json) =>
      VhcShipmentWindow.fromJson(json);
  int? get shipmentId => nullableId("shipment");
  VhcShipment? get shipment => detail("shipment_detail") == null
      ? null
      : VhcShipment.fromJson(detail("shipment_detail")!);
  String? get startDate => dateOnly("start_date");
  String? get endDate => dateOnly("end_date");
  String get updatedBy => getString("updated_by_name");
  @override
  bool get canCreate => api.vhcCapabilities.allows("manage_shipment_windows");
  @override
  bool get canEdit => canCreate;
  @override
  bool get canDelete => canCreate;
}

/// Box items have no standalone endpoint; writes go through their parent box.
class VhcBoxItem extends VhcModel {
  VhcBoxItem.fromJson(Map<String, dynamic> json) : super.fromJson(json);
  @override
  VhcBoxItem createFromJson(Map<String, dynamic> json) =>
      VhcBoxItem.fromJson(json);
  int? get partId => nullableId("part");
  int? get stockItemId => nullableId("stock_item");
  String get partName =>
      detail("part_detail")?["name"]?.toString() ?? getString("part_name");
  String get quantity => vhcQuantity(getValue("quantity"));
  String get size => getString("size");
  String get sterile => getString("sterile");
  String? get expiryDate => dateOnly("expiry_date");
  String get expiryLabel => getString("expiry_label");
  String get expiryDisplay => expiryDate ?? expiryLabel;

  Map<String, dynamic> toWriteJson() {
    if ((partId == null && partName.trim().isEmpty) ||
        (partId != null && partId! <= 0)) {
      throw const FormatException("Select a part or enter a part name");
    }
    if (!VhcExpiry.valid(sterile, expiryDate, expiryLabel) ||
        (getValue("expiry_date") != null && expiryDate == null)) {
      throw const FormatException(
        "Invalid sterility or expiration combination",
      );
    }
    return {
      if (partId != null) "part": partId else "part_name": partName,
      "quantity": quantity,
      "size": size,
      "sterile": sterile,
      "expiry_date": expiryDate,
      "expiry_label": expiryLabel,
    };
  }
}

class VhcBox extends VhcModel {
  VhcBox();
  VhcBox.fromJson(Map<String, dynamic> json) : super.fromJson(json);
  @override
  String get URL => "vhc/box/";
  @override
  String get webUrl => api.makeUrl("/web/boxes/$pk/");
  @override
  Future<Object?> goToDetailPage(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<Object>(
      builder: (context) => VhcBoxDetail(pk, boxNumber: boxNumber),
    ),
  );
  @override
  VhcBox createFromJson(Map<String, dynamic> json) => VhcBox.fromJson(json);
  String get boxNumber => getString("box_number");
  int get revision => getInt("revision", backup: 0);
  String get contents => getString("contents");
  String get note => getString("note");
  String get state => getString("status");
  String get source => getString("source");
  String get otherTeamDescription => getString("other_team_description");
  int? get teamId => nullableId("team");
  int? get shipmentId => nullableId("shipment");
  int? get palletId => nullableId("pallet");
  int? get currentLocationId => nullableId("current_location");
  int? get destinationId => nullableId("destination");
  VhcTeam? get team => detail("team_detail") == null
      ? null
      : VhcTeam.fromJson(detail("team_detail")!);
  VhcShipment? get shipment => detail("shipment_detail") == null
      ? null
      : VhcShipment.fromJson(detail("shipment_detail")!);
  VhcPallet? get pallet => detail("pallet_detail") == null
      ? null
      : VhcPallet.fromJson(detail("pallet_detail")!);
  List<VhcBoxItem> get items => (getValue("items") is List<dynamic>)
      ? (getValue("items") as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(VhcBoxItem.fromJson)
            .toList()
      : [];
  @override
  bool get canCreate => api.vhcCapabilities.allows("create_box");
  @override
  bool get canEdit => api.vhcCapabilities.allows("edit_box");
  @override
  bool get canDelete => api.vhcCapabilities.allows("delete_box");
}

class VhcBoxEvent extends VhcModel {
  VhcBoxEvent();
  VhcBoxEvent.fromJson(Map<String, dynamic> json) : super.fromJson(json);
  @override
  String get URL => "vhc/event/";
  @override
  VhcBoxEvent createFromJson(Map<String, dynamic> json) =>
      VhcBoxEvent.fromJson(json);
  int? get boxId => nullableId("box");
  String get action => getString("action");
  String get actionText => getString("action_text");
  String get userName => getString("user_name");
  DateTime? get timestamp => getDate("timestamp");
  Map<String, dynamic> get changes => detail("changes") ?? {};
}
