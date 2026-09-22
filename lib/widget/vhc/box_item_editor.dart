import "package:flutter/material.dart";
import "package:dropdown_search/dropdown_search.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_box_draft.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/l10.dart";
import "package:inventree/widget/vhc/common.dart";

class VhcRelationField extends StatelessWidget {
  const VhcRelationField({
    required this.field,
    required this.label,
    required this.path,
    required this.browser,
    required this.onChanged,
    this.value,
    this.error,
    this.required = false,
    this.filters = const {},
    super.key,
  });
  final String field;
  final String label;
  final String path;
  final VhcBrowser browser;
  final Map<String, dynamic>? value;
  final String? error;
  final bool required;
  final Map<String, String> filters;
  final void Function(Map<String, dynamic>?) onChanged;

  @override
  Widget build(BuildContext context) => DropdownSearch<Map<String, dynamic>>(
    key: ValueKey(field),
    selectedItem: value,
    compareFn: (a, b) => a["pk"] == b["pk"],
    asyncItems: (search) => browser.choices(path, search, filters: filters),
    popupProps: PopupProps.bottomSheet(
      showSearchBox: true,
      isFilterOnline: true,
      errorBuilder: (context, search, error) => VhcErrorView(error),
    ),
    clearButtonProps: ClearButtonProps(isVisible: !required),
    dropdownDecoratorProps: DropDownDecoratorProps(
      dropdownSearchDecoration: InputDecoration(
        labelText: required ? "$label *" : label,
        errorText: error,
      ),
    ),
    itemAsString: (row) {
      final name =
          (row["display_name"] ??
                  row["reference"] ??
                  row["pathstring"] ??
                  row["name"] ??
                  "#${row["pk"]}")
              .toString();
      return path == "part/" ? "$name (${row["IPN"] ?? row["pk"]})" : name;
    },
    onChanged: onChanged,
  );
}

class VhcBoxItemEditor extends StatefulWidget {
  const VhcBoxItemEditor({
    required this.item,
    required this.index,
    required this.browser,
    required this.changed,
    required this.remove,
    required this.errors,
    super.key,
  });
  final VhcItemDraft item;
  final int index;
  final VhcBrowser browser;
  final VoidCallback changed;
  final VoidCallback remove;
  final Map<String, String> errors;
  @override
  State<VhcBoxItemEditor> createState() => _VhcBoxItemEditorState();
}

class _VhcBoxItemEditorState extends State<VhcBoxItemEditor> {
  late bool _newName =
      widget.item.partId == null && widget.item.partName.isNotEmpty;
  int _dateVersion = 0;
  String? error(String field) => widget.errors["items.${widget.index}.$field"];
  void change(VoidCallback action) {
    setState(action);
    widget.changed();
  }

  Future<void> _pickDate() async {
    var initial = DateTime.tryParse(widget.item.date ?? "") ?? DateTime.now();
    if (initial.year < 1900 || initial.year > 2100) initial = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (value == null || !mounted) return;
    change(() {
      widget.item.setDate(
        "${value.year.toString().padLeft(4, "0")}-${value.month.toString().padLeft(2, "0")}-${value.day.toString().padLeft(2, "0")}",
      );
      _dateVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final allowedLabel = VhcExpiry.labelFor(item.sterile);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${L10().part} ${widget.index + 1}",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: L10().vhcRemoveItem,
                  onPressed: widget.remove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L10().vhcNewItemName),
              value: _newName,
              onChanged: (value) => change(() {
                _newName = value;
                item.partId = null;
                item.partName = "";
              }),
            ),
            if (_newName)
              TextFormField(
                key: const ValueKey("new-part-name"),
                initialValue: item.partName,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: L10().name,
                  helperText: L10().vhcNewItemHint,
                  errorText: error("part_name"),
                ),
                onChanged: (value) => change(() => item.partName = value),
              )
            else
              VhcRelationField(
                field: "item-${widget.index}-part",
                label: L10().vhcSelectPart,
                path: "part/",
                browser: widget.browser,
                filters: const {"active": "true", "virtual": "false"},
                value: item.partId == null
                    ? null
                    : {"pk": item.partId, "name": item.partName},
                error: error("part_name") ?? error("part"),
                onChanged: (row) => change(() {
                  item.partId = row?["pk"] as int?;
                  item.partName = row?["name"]?.toString() ?? "";
                }),
              ),
            TextFormField(
              key: const ValueKey("item-quantity"),
              initialValue: item.quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: L10().quantity,
                errorText: error("quantity"),
              ),
              onChanged: (value) => change(() => item.quantity = value),
            ),
            TextFormField(
              initialValue: item.size,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: L10().stockSize,
                errorText: error("size"),
              ),
              onChanged: (value) => change(() => item.size = value),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey("sterile:${item.sterile}"),
              initialValue: item.sterile,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: L10().stockSterility,
                errorText: error("sterile"),
              ),
              items: {"": L10().vhcNoSterility, "S": "S", "NS": "NS"}.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (value) => change(() => item.setSterile(value ?? "")),
            ),
            TextFormField(
              key: ValueKey("item-date:$_dateVersion"),
              initialValue: item.date ?? "",
              decoration: InputDecoration(
                labelText: L10().expiryDate,
                hintText: "YYYY-MM-DD",
                errorText: error("expiry_date"),
                suffixIcon: IconButton(
                  tooltip: L10().vhcChooseDate,
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month),
                ),
              ),
              onChanged: (value) => change(() => item.setDate(value)),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey("expiry:${item.label}:${item.sterile}"),
              initialValue: item.label,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: L10().vhcExpiryLabel,
                errorText: error("expiry_label"),
              ),
              items:
                  {
                        "": L10().vhcUseDate,
                        if (allowedLabel.isNotEmpty) allowedLabel: allowedLabel,
                      }.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
              onChanged: (value) => change(() {
                item.setLabel(value ?? "");
                _dateVersion++;
              }),
            ),
          ],
        ),
      ),
    );
  }
}
