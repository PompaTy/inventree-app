import "dart:async";
import "package:flutter/material.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/l10.dart";
import "package:inventree/widget/vhc/box_detail.dart";
import "package:inventree/widget/vhc/box_filters.dart";
import "package:inventree/widget/vhc/common.dart";
import "package:inventree/widget/vhc/box_editor.dart";

class VhcBoxList extends StatefulWidget {
  const VhcBoxList({this.browser, super.key});
  final VhcBrowser? browser;
  @override
  State<VhcBoxList> createState() => _VhcBoxListState();
}

class _VhcBoxListState extends State<VhcBoxList> {
  late final VhcBrowser _browser = widget.browser ?? VhcBrowser();
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = "";
  VhcFilterSelection _selection = const VhcFilterSelection({
    "active": "true",
  }, {});
  int _refresh = 0;

  @override
  void initState() {
    super.initState();
    InvenTreeAPI().registerCallback(_connectionChanged);
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    InvenTreeAPI().unregisterCallback(_connectionChanged);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _create() async {
    final box = await Navigator.push<VhcBox>(
      context,
      MaterialPageRoute<VhcBox>(
        builder: (context) => VhcBoxEditor(browser: _browser),
      ),
    );
    if (!mounted) return;
    setState(() => _refresh++);
    if (box != null && _browser.canRead) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) =>
              VhcBoxDetail(box.pk, boxNumber: box.boxNumber, browser: _browser),
        ),
      );
      if (mounted) setState(() => _refresh++);
    }
  }

  Future<void> _filters() async {
    final result = await showDialog<VhcFilterSelection>(
      context: context,
      builder: (context) =>
          VhcBoxFilters(browser: _browser, selection: _selection),
    );
    if (result != null && mounted) setState(() => _selection = result);
  }

  @override
  Widget build(BuildContext context) {
    final filters = {..._selection.values, "search": _query};
    return Scaffold(
      floatingActionButton:
          _browser.canRead &&
              InvenTreeAPI().vhcCapabilities.allows("create_box")
          ? FloatingActionButton(
              tooltip: L10().vhcCreateBox,
              onPressed: _create,
              child: const Icon(Icons.add),
            )
          : null,
      appBar: AppBar(
        title: Text(L10().vhcBoxes),
        actions: [
          IconButton(
            tooltip: L10().refresh,
            onPressed: () => setState(() => _refresh++),
            icon: const Icon(Icons.refresh),
          ),
          if (_browser.canRead)
            IconButton(
              tooltip: L10().filteringOptions,
              onPressed: _filters,
              icon: const Icon(Icons.filter_list),
            ),
        ],
      ),
      body: !_browser.canRead
          ? const Center(child: VhcErrorView(VhcReadException(403)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: L10().vhcSearchBoxes,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: L10().vhcClear,
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _searchChanged("");
                        },
                      ),
                    ),
                    onChanged: _searchChanged,
                    onSubmitted: (value) {
                      _debounce?.cancel();
                      setState(() => _query = value.trim());
                    },
                  ),
                ),
                Expanded(
                  child: VhcPagedList<VhcBox>(
                    key: ValueKey("$filters:$_refresh"),
                    load: (offset) => _browser.boxes(offset, filters),
                    emptyText: L10().vhcNoBoxes,
                    itemBuilder: (context, box) => VhcBoxTile(
                      box,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (context) => VhcBoxDetail(
                              box.pk,
                              boxNumber: box.boxNumber,
                              browser: _browser,
                            ),
                          ),
                        );
                        if (mounted) setState(() => _refresh++);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class VhcBoxTile extends StatelessWidget {
  const VhcBoxTile(this.box, {required this.onTap, super.key});
  final VhcBox box;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.inventory_2_outlined),
    title: Text("${L10().vhcBox} ${box.boxNumber}"),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(box.getString("status_text", backup: box.state)),
        if (box.team != null) VhcTeamBadge(box.team!),
        if (box.contents.isNotEmpty)
          Text(box.contents, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (box.detail("current_location_detail") != null)
          Text(
            box.detail("current_location_detail")!["pathstring"]?.toString() ??
                "",
          ),
        if (box.shipment != null)
          Text("${L10().shipment}: ${box.shipment!.reference}"),
        if (box.pallet != null)
          Text("${L10().vhcPallet}: ${box.pallet!.displayName}"),
      ],
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
