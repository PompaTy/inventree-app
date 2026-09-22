import "package:inventree/api_form.dart";
import "package:inventree/inventree/vhc.dart";

/// Keep the date and special expiration label mutually exclusive.
void updateVhcExpiryFields(List<APIFormField> fields, String changed) {
  final byName = {for (final field in fields) field.name: field};
  final sterile = byName["sterile"];
  final label = byName["expiry_label"];
  final date = byName["expiry_date"];
  if (sterile == null || label == null || date == null) return;
  sterile.data["value"] = sterile.value ?? "";
  label.data["value"] = label.value ?? "";
  final allowed = VhcExpiry.labelFor(sterile.value.toString());
  if (changed == "sterile" && label.value != allowed) {
    label.data["value"] = "";
  }
  if (changed == "expiry_label" && label.value != "") {
    date.data["value"] = null;
  }
  if (changed == "expiry_date" && date.value != null) {
    label.data["value"] = "";
  }
}

class VhcStockFormState extends APIFormWidgetState {
  @override
  List<APIFormField> get formFields {
    final fields = super.formFields;
    final byName = {for (final field in fields) field.name: field};
    final sterile = byName["sterile"];
    final label = byName["expiry_label"];
    if (sterile != null && label != null) {
      final allowed = VhcExpiry.labelFor(sterile.value?.toString() ?? "");
      label.data["choices"] = [
        {"value": "", "display_name": "---------"},
        if (allowed.isNotEmpty) {"value": allowed, "display_name": allowed},
      ];
    }
    return fields;
  }

  @override
  void onValueChanged(String field, dynamic value) {
    updateVhcExpiryFields(super.formFields, field);
    super.onValueChanged(field, value);
  }
}
