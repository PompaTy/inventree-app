import "package:flutter/material.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/part.dart";
import "package:inventree/inventree/stock.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/l10.dart";
import "package:inventree/widget/vhc/common.dart";
import "package:inventree/widget/vhc/box_editor.dart";

class VhcBoxDetail extends StatefulWidget {
  const VhcBoxDetail(
    this.boxId, {
    this.boxNumber = "",
    this.browser,
    super.key,
  });
  final int boxId;
  final String boxNumber;
  final VhcBrowser? browser;
  @override
  State<VhcBoxDetail> createState() => _VhcBoxDetailState();
}

class _VhcBoxDetailState extends State<VhcBoxDetail> {
  late final VhcBrowser _browser = widget.browser ?? VhcBrowser();
  VhcBox? _box;
  Object? _error;
  bool _busy = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    InvenTreeAPI().registerCallback(_connectionChanged);
    _load();
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    InvenTreeAPI().unregisterCallback(_connectionChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final box = await _browser.box(widget.boxId);
      if (!mounted || generation != _generation) return;
      setState(() => _box = box);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _box = null;
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final box = _box;
    if (box == null || !_browser.canRead || !box.canEdit) return;
    await Navigator.push<VhcBox>(
      context,
      MaterialPageRoute<VhcBox>(
        builder: (context) => VhcBoxEditor(box: box, browser: _browser),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final box = _box;
    final canRead = _browser.canRead;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            canRead
                ? "${L10().vhcBox} ${box?.boxNumber ?? widget.boxNumber}"
                : L10().vhcBox,
          ),
          actions: [
            if (canRead && box != null && box.canEdit)
              IconButton(
                tooltip: L10().vhcEditBox,
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
            if (canRead)
              IconButton(
                tooltip: L10().refresh,
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            if (canRead && box != null)
              IconButton(
                tooltip: L10().vhcOpenWeb,
                onPressed: box.goToInvenTreePage,
                icon: const Icon(Icons.open_in_new),
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: L10().vhcOverview),
              Tab(text: L10().vhcContents),
              Tab(text: L10().history),
            ],
          ),
        ),
        body: !canRead
            ? const Center(child: VhcErrorView(VhcReadException(403)))
            : _busy
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: VhcErrorView(_error, retry: _load))
            : box == null
            ? const SizedBox.shrink()
            : TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [VhcBoxOverview(box)],
                    ),
                  ),
                  RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (box.items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(L10().vhcNoContents),
                          ),
                        for (final item in box.items) VhcBoxItemTile(item),
                      ],
                    ),
                  ),
                  VhcPagedList<VhcBoxEvent>(
                    key: ValueKey("history:${box.pk}:$_generation"),
                    load: (offset) => _browser.events(box.pk, offset),
                    emptyText: L10().vhcNoHistory,
                    itemBuilder: (context, event) => VhcEventTile(event),
                  ),
                ],
              ),
      ),
    );
  }
}

class VhcBoxOverview extends StatelessWidget {
  const VhcBoxOverview(this.box, {super.key});
  final VhcBox box;

  Widget _field(String label, String value) =>
      ListTile(title: Text(label), subtitle: Text(value.isEmpty ? "—" : value));
  Widget _location(
    BuildContext context,
    String label,
    int? pk,
    Map<String, dynamic>? detail,
  ) => ListTile(
    title: Text(label),
    subtitle: Text(
      detail?["pathstring"]?.toString() ??
          detail?["name"]?.toString() ??
          (pk == null ? "—" : "#$pk"),
    ),
    trailing: pk == null ? null : const Icon(Icons.chevron_right),
    onTap: pk == null
        ? null
        : () => InvenTreeStockLocation.fromJson({
            ...?detail,
            "pk": pk,
          }).goToDetailPage(context),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _field(L10().status, box.getString("status_text", backup: box.state)),
      if (box.team != null)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: VhcTeamBadge(box.team!),
          ),
        )
      else
        _field(L10().vhcTeam, ""),
      if (box.otherTeamDescription.isNotEmpty)
        _field(L10().vhcOtherTeam, box.otherTeamDescription),
      _field(L10().vhcContents, box.contents),
      _field(L10().shipment, box.shipment?.reference ?? ""),
      _field(L10().vhcPallet, box.pallet?.displayName ?? ""),
      _location(
        context,
        L10().stockLocation,
        box.currentLocationId,
        box.detail("current_location_detail"),
      ),
      _location(
        context,
        L10().destination,
        box.destinationId,
        box.detail("destination_detail"),
      ),
      _field(L10().vhcSource, box.getString("source_text", backup: box.source)),
      _field(L10().notes, box.note),
      _field(L10().creationDate, box.getString("created")),
      _field(L10().lastUpdated, box.getString("updated")),
    ],
  );
}

class VhcBoxItemTile extends StatelessWidget {
  const VhcBoxItemTile(this.item, {super.key});
  final VhcBoxItem item;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(item.partName),
          subtitle: Text(
            [
              "${L10().quantity}: ${item.quantity}",
              if (item.size.isNotEmpty) "${L10().stockSize}: ${item.size}",
              if (item.sterile.isNotEmpty)
                "${L10().stockSterility}: ${item.sterile}",
              if (item.expiryDisplay.isNotEmpty)
                "${L10().expiryDate}: ${item.expiryDisplay}",
            ].join("\n"),
          ),
          trailing: item.partId == null
              ? null
              : const Icon(Icons.chevron_right),
          onTap: item.partId == null
              ? null
              : () => InvenTreePart.fromJson({
                  "pk": item.partId,
                }).goToDetailPage(context),
        ),
        if (item.stockItemId != null)
          TextButton.icon(
            onPressed: () => InvenTreeStockItem.fromJson({
              "pk": item.stockItemId,
            }).goToDetailPage(context),
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text(L10().vhcLinkedStock),
          ),
      ],
    ),
  );
}

/// Human-readable audit values, supporting old summaries and nested item snapshots.
String vhcHistoryValue(dynamic value) {
  if (value == null || value == "") return "—";
  if (value is List<dynamic>) {
    return value.isEmpty ? "—" : value.map(vhcHistoryValue).join("\n");
  }
  if (value is Map<String, dynamic>) {
    return value.entries
        .map(
          (entry) =>
              "${entry.key.replaceAll("_", " ")}: ${vhcHistoryValue(entry.value)}",
        )
        .join(", ");
  }
  return value.toString();
}

class VhcEventTile extends StatelessWidget {
  const VhcEventTile(this.event, {super.key});
  final VhcBoxEvent event;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(
      event.actionText.isEmpty
          ? event.action.replaceAll("_", " ")
          : event.actionText,
    ),
    subtitle: Text(
      [
        event.userName,
        event.getString("timestamp"),
      ].where((value) => value.isNotEmpty).join(" · "),
    ),
    childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (event.getString("notes").isNotEmpty) Text(event.getString("notes")),
      if (event.detail("from_location_detail") != null ||
          event.detail("to_location_detail") != null)
        Text(
          "${event.detail("from_location_detail")?["pathstring"] ?? "—"} → ${event.detail("to_location_detail")?["pathstring"] ?? "—"}",
        ),
      for (final entry in event.changes.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            entry.value is Map<String, dynamic> &&
                    ((entry.value as Map<String, dynamic>).containsKey(
                          "from",
                        ) ||
                        (entry.value as Map<String, dynamic>).containsKey("to"))
                ? "${entry.key.replaceAll("_", " ")}\n${vhcHistoryValue(entry.value["from"])} → ${vhcHistoryValue(entry.value["to"])}"
                : "${entry.key.replaceAll("_", " ")}: ${vhcHistoryValue(entry.value)}",
          ),
        ),
    ],
  );
}
