import "package:flutter/material.dart";
import "package:dropdown_search/dropdown_search.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/l10.dart";

class VhcFilterSelection {
  const VhcFilterSelection(this.values, this.labels);
  final Map<String, String> values;
  final Map<String, String> labels;
}

class VhcBoxFilters extends StatefulWidget {
  const VhcBoxFilters({
    required this.browser,
    required this.selection,
    super.key,
  });
  final VhcBrowser browser;
  final VhcFilterSelection selection;
  @override
  State<VhcBoxFilters> createState() => _VhcBoxFiltersState();
}

class _VhcBoxFiltersState extends State<VhcBoxFilters> {
  late final _values = {...widget.selection.values};
  late final _labels = {...widget.selection.labels};

  Widget _choice(String key, String label, Map<String, String> choices) =>
      DropdownButtonFormField<String>(
        initialValue: _values[key] ?? "",
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: {"": L10().vhcAll, ...choices}.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: (value) => setState(() {
          if (value == null || value.isEmpty) {
            _values.remove(key);
          } else {
            _values[key] = value;
            if (key == "status" && (value == "LOST" || value == "CLOSED")) {
              _values.remove("active");
            }
          }
        }),
      );

  String _name(Map<String, dynamic> row) =>
      (row["display_name"] ??
              row["reference"] ??
              row["pathstring"] ??
              row["name"] ??
              row["pk"])
          .toString();

  Widget _relation(String key, String label, String path) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: DropdownSearch<Map<String, dynamic>>(
      key: ValueKey("$key:${_values[key]}"),
      selectedItem: _values[key] == null
          ? null
          : {
              "pk": int.parse(_values[key]!),
              "name": _labels[key] ?? _values[key],
            },
      asyncItems: (search) => widget.browser.choices(
        path,
        search,
        shipment: key == "pallet" ? _values["shipment"] : null,
      ),
      popupProps: const PopupProps.bottomSheet(
        showSearchBox: true,
        isFilterOnline: true,
      ),
      clearButtonProps: const ClearButtonProps(isVisible: true),
      dropdownDecoratorProps: DropDownDecoratorProps(
        dropdownSearchDecoration: InputDecoration(labelText: label),
      ),
      itemAsString: _name,
      onChanged: (row) => setState(() {
        if (row == null) {
          _values.remove(key);
          _labels.remove(key);
        } else {
          _values[key] = row["pk"].toString();
          _labels[key] = _name(row);
        }
        if (key == "shipment") {
          _values.remove("pallet");
          _labels.remove("pallet");
        }
      }),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(L10().filteringOptions),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(L10().vhcActiveOnly),
              value: _values["active"] == "true",
              onChanged: (value) => setState(() {
                if (value) {
                  _values["active"] = "true";
                } else {
                  _values.remove("active");
                }
              }),
            ),
            _choice("status", L10().status, {
              "PACKED": L10().vhcPacked,
              "PALLETIZED": L10().vhcPalletized,
              "IN_TRANSIT": L10().vhcInTransit,
              "HONDURAS_WAREHOUSE": L10().vhcHondurasWarehouse,
              "DISTRIBUTED": L10().vhcDistributed,
              "RETURNED": L10().vhcReturned,
              "LOST": L10().vhcLost,
              "CLOSED": L10().vhcClosed,
            }),
            _relation("team", L10().vhcTeam, "vhc/team/"),
            _relation("shipment", L10().shipment, "vhc/shipment/"),
            _relation("pallet", L10().vhcPallet, "vhc/pallet/"),
            _relation(
              "current_location",
              L10().stockLocation,
              "stock/location/",
            ),
            _relation("destination", L10().destination, "stock/location/"),
            _choice("ordering", L10().vhcSort, {
              "box_number": L10().vhcBox,
              "-box_number": L10().vhcBoxDescending,
              "-updated": L10().lastUpdated,
              "team__name": L10().vhcTeam,
              "shipment__reference": L10().shipment,
              "current_location__pathstring": L10().stockLocation,
            }),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () =>
            Navigator.pop(context, const VhcFilterSelection({}, {})),
        child: Text(L10().vhcClear),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(L10().cancel),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, VhcFilterSelection(_values, _labels)),
        child: Text(L10().vhcApply),
      ),
    ],
  );
}
