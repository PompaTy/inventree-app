import "package:flutter/material.dart";
import "package:inventree/inventree/stock.dart";
import "package:inventree/l10.dart";

/// Compact custom information shared by stock lists and stock details.
class VhcStockInfo extends StatelessWidget {
  const VhcStockInfo(
    this.item, {
    this.showOwnershipHint = false,
    this.showExpiry = true,
    super.key,
  });

  final InvenTreeStockItem item;
  final bool showOwnershipHint;
  final bool showExpiry;

  @override
  Widget build(BuildContext context) {
    final capabilities = item.api.vhcCapabilities;
    final box = capabilities.hasStockField("vhc_box") ? item.vhcBox : null;
    final details = [
      if (capabilities.hasStockField("size") && item.size.isNotEmpty)
        "${L10().stockSize}: ${item.size}",
      if (capabilities.hasStockField("sterile") && item.sterile.isNotEmpty)
        "${L10().stockSterility}: ${item.sterile}",
      if (showExpiry &&
          capabilities.hasStockField("expiry_label") &&
          item.expiryDisplay.isNotEmpty)
        "${L10().expiryDate}: ${item.expiryDisplay}",
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (box != null)
          TextButton.icon(
            onPressed: box.goToInvenTreePage,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              [
                "${L10().vhcBox}: ${box.boxNumber}",
                if (box.team != null) "${L10().vhcTeam}: ${box.team!.name}",
              ].join(" · "),
            ),
          ),
        if (details.isNotEmpty) Text(details.join(" · ")),
        if (box != null && showOwnershipHint) Text(L10().vhcOwnedStock),
      ],
    );
  }
}
