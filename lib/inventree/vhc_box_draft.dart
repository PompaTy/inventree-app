import "dart:convert";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/l10.dart";

class VhcItemDraft {
  VhcItemDraft();
  VhcItemDraft.fromItem(VhcBoxItem item)
    : partId = item.partId,
      partName = item.partName,
      quantity = item.quantity,
      size = item.size,
      sterile = item.sterile,
      date = item.expiryDate,
      label = item.expiryLabel;
  int? partId;
  String partName = "";
  String quantity = "1";
  String size = "";
  String sterile = "";
  String? date;
  String label = "";

  void setSterile(String value) {
    sterile = value;
    if (label != VhcExpiry.labelFor(value)) label = "";
  }

  void setDate(String? value) {
    date = value == null || value.trim().isEmpty ? null : value.trim();
    if (date != null) label = "";
  }

  void setLabel(String value) {
    label = value;
    if (value.isNotEmpty) date = null;
  }

  Map<String, dynamic> rawJson() => {
    if (partId != null) "part": partId else "part_name": partName.trim(),
    "quantity": quantity.trim(),
    "size": size.trim(),
    "sterile": sterile,
    "expiry_date": date,
    "expiry_label": label,
  };
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (partId == null && partName.trim().isEmpty) {
      errors["part_name"] = L10().vhcPartRequired;
    }
    if (partName.trim().length > 100) errors["part_name"] = L10().vhcMax100;
    try {
      vhcQuantity(quantity.trim());
    } on FormatException {
      errors["quantity"] = L10().vhcQuantityInvalid;
    }
    if (size.trim().length > 100) errors["size"] = L10().vhcMax100;
    if (date != null && vhcCalendarDate(date) == null) {
      errors["expiry_date"] = L10().vhcDateInvalid;
    }
    if (!VhcExpiry.valid(sterile, date, label)) {
      errors["expiry_label"] = L10().vhcExpiryInvalid;
    }
    return errors;
  }
}

class VhcBoxDraft {
  VhcBoxDraft() : original = null {
    items.add(VhcItemDraft());
  }
  VhcBoxDraft.fromBox(VhcBox box)
    : original = VhcBox.fromJson(
        jsonDecode(jsonEncode(box.jsondata)) as Map<String, dynamic>,
      ) {
    number = box.boxNumber;
    otherTeam = box.otherTeamDescription;
    note = box.note;
    source = box.source;
    for (final field in [
      "team",
      "shipment",
      "pallet",
      "current_location",
      "destination",
    ]) {
      final pk = box.nullableId(field);
      if (pk != null) {
        relations[field] = {...?box.detail("${field}_detail"), "pk": pk};
      }
    }
    items.addAll(box.items.map(VhcItemDraft.fromItem));
    _initialItems = jsonEncode(items.map((item) => item.rawJson()).toList());
  }
  final VhcBox? original;
  String number = "";
  String otherTeam = "";
  String note = "";
  String source = "DONATION_PURCHASE";
  final relations = <String, Map<String, dynamic>>{};
  final items = <VhcItemDraft>[];
  String _initialItems = "[]";
  bool get editing => original != null;
  bool get itemsChanged =>
      jsonEncode(items.map((item) => item.rawJson()).toList()) != _initialItems;

  void selectRelation(String field, Map<String, dynamic>? row) {
    if (row == null) {
      relations.remove(field);
    } else {
      relations[field] = {...row};
    }
    if (field == "shipment") relations.remove("pallet");
    if (field == "pallet" && row != null && row["shipment"] != null) {
      relations["shipment"] = {
        if (row["shipment_detail"] is Map<String, dynamic>)
          ...(row["shipment_detail"] as Map<String, dynamic>),
        "pk": row["shipment"],
      };
    }
  }

  List<String> get removedStock =>
      original?.items
          .where(
            (old) =>
                old.stockItemId != null &&
                !items.any((item) => item.partId == old.partId),
          )
          .map((item) => item.partName)
          .toList() ??
      [];

  Map<String, String> validate() {
    final errors = <String, String>{};
    if ((editing || number.trim().isNotEmpty) &&
        !RegExp(r"^\d{6}$").hasMatch(number.trim())) {
      errors["box_number"] = L10().vhcNumberInvalid;
    }
    if (relations["team"] == null) errors["team"] = L10().vhcTeamRequired;
    if (otherTeam.length > 100) {
      errors["other_team_description"] = L10().vhcMax100;
    }
    if (note.length > 500) errors["note"] = L10().vhcMax500;
    if ((!editing || itemsChanged) && items.isEmpty) {
      errors["items"] = L10().vhcItemRequired;
    }
    for (var i = 0; i < items.length; i++) {
      items[i].validate().forEach(
        (field, message) => errors["items.$i.$field"] = message,
      );
      for (var j = 0; j < i; j++) {
        final a = items[i];
        final b = items[j];
        if ((a.partId != null && a.partId == b.partId) ||
            ((a.partId == null || b.partId == null) &&
                a.partName.trim().isNotEmpty &&
                a.partName.trim().toLowerCase() ==
                    b.partName.trim().toLowerCase())) {
          errors["items.$i.part_name"] = L10().vhcDuplicateItem;
        }
      }
    }
    return errors;
  }

  Map<String, dynamic> toJson() {
    if (validate().isNotEmpty) throw const FormatException("Invalid box draft");
    return {
      "box_number": number.trim(),
      "team": relations["team"]!["pk"],
      "other_team_description": otherTeam.trim(),
      "note": note.trim(),
      "source": source,
      for (final field in [
        "shipment",
        "pallet",
        "current_location",
        "destination",
      ])
        field: relations[field]?["pk"],
      if (!editing || itemsChanged)
        "items": items.map((item) => item.rawJson()).toList(),
    };
  }
}

/// Preserve nested field paths so server errors can appear beside their inputs.
Map<String, String> vhcBoxErrors(dynamic data, [String prefix = ""]) {
  final errors = <String, String>{};
  if (data is Map<Object?, Object?>) {
    data.forEach(
      (key, value) => errors.addAll(
        vhcBoxErrors(value, prefix.isEmpty ? key.toString() : "$prefix.$key"),
      ),
    );
  } else if (data is List<dynamic>) {
    if (data.every((value) => value is String)) {
      if (data.isNotEmpty) errors[prefix] = data.join("\n");
    } else {
      for (var i = 0; i < data.length; i++) {
        errors.addAll(vhcBoxErrors(data[i], "$prefix.$i"));
      }
    }
  } else if (data != null) {
    errors[prefix.isEmpty ? "detail" : prefix] = data.toString();
  }
  return errors;
}
