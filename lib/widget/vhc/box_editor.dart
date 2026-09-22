import "package:flutter/material.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_box_draft.dart";
import "package:inventree/inventree/vhc_box_writer.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/l10.dart";
import "package:inventree/widget/vhc/box_item_editor.dart";
import "package:inventree/widget/vhc/common.dart";

class VhcBoxEditor extends StatefulWidget {
  const VhcBoxEditor({this.box, this.browser, this.writer, super.key});
  final VhcBox? box;
  final VhcBrowser? browser;
  final VhcBoxWriter? writer;
  @override
  State<VhcBoxEditor> createState() => _VhcBoxEditorState();
}

class _VhcBoxEditorState extends State<VhcBoxEditor> {
  late final _browser = widget.browser ?? VhcBrowser();
  late final _writer = widget.writer ?? VhcBoxWriter(_browser);
  late VhcBoxDraft _draft = widget.box == null
      ? VhcBoxDraft()
      : VhcBoxDraft.fromBox(widget.box!);
  final _scroll = ScrollController();
  Map<String, String> _errors = {};
  bool _dirty = false;
  bool _busy = false;
  bool _sending = false;
  bool _conflict = false;
  bool _uncertain = false;
  bool _blocked = false;
  bool _allowPop = false;
  String? _message;
  int _version = 0;

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
    _scroll.dispose();
    super.dispose();
  }

  void _change() {
    setState(() {
      _dirty = true;
      _errors = {};
    });
  }

  void _top() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L10().cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  void _exit([VhcBox? box]) {
    setState(() {
      _allowPop = true;
      _dirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, box);
    });
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (!_dirty ||
        await _confirm(
          L10().vhcDiscardTitle,
          _uncertain ? L10().vhcSaveUncertain : L10().vhcDiscardBody,
          L10().vhcDiscard,
        )) {
      if (mounted) _exit();
    }
  }

  Future<void> _reload() async {
    if (_busy || !_draft.editing) return;
    if (!await _confirm(
          L10().vhcDiscardTitle,
          L10().vhcDiscardBody,
          L10().vhcReloadBox,
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      setState(() => _sending = true);
      final box = await _browser.box(_draft.original!.pk);
      if (!mounted) return;
      setState(() {
        _draft = VhcBoxDraft.fromBox(box);
        _version++;
        _dirty = false;
        _conflict = false;
        _uncertain = false;
        _blocked = false;
        _message = null;
        _errors = {};
      });
    } catch (error) {
      if (mounted) setState(() => _message = vhcReadError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _sending = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy ||
        _conflict ||
        _uncertain ||
        _blocked ||
        !_writer.canSave(_draft.editing)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _errors = _draft.validate();
      _message = _errors.isEmpty ? null : L10().vhcFixErrors;
    });
    if (_errors.isNotEmpty) {
      _top();
      return;
    }
    // Lock the form before the review dialog to prevent double submissions.
    setState(() => _busy = true);
    try {
      final removed = _draft.removedStock;
      if (removed.isNotEmpty &&
          !await _confirm(
            L10().vhcRemoveStockTitle,
            "${L10().vhcRemoveStockBody}\n\n${removed.join("\n")}",
            L10().save,
          )) {
        return;
      }
      if (!mounted) return;
      setState(() => _sending = true);
      final response = await _writer.save(_draft);
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = VhcBox.fromJson(response.asMap());
        if (result.pk > 0 && result.revision > 0) {
          _exit(result);
          return;
        }
        setState(() {
          _uncertain = true;
          _message = L10().vhcSaveUncertain;
        });
      } else if (response.statusCode == 409 ||
          response.asMap().containsKey("revision")) {
        setState(() {
          _conflict = true;
          _message = L10().vhcSaveConflict;
        });
      } else if (response.statusCode == 400) {
        setState(() {
          _errors = vhcBoxErrors(response.data);
          _message = L10().vhcSaveFailed;
        });
      } else if ([401, 403, 404].contains(response.statusCode)) {
        setState(() {
          _blocked = true;
          _message = vhcReadError(VhcReadException(response.statusCode));
        });
      } else {
        setState(() {
          _uncertain = true;
          _message = L10().vhcSaveUncertain;
        });
      }
      _top();
    } catch (error) {
      if (mounted) {
        setState(() {
          _blocked = error is VhcReadException;
          _uncertain = !_blocked;
          _message = _blocked ? vhcReadError(error) : L10().vhcSaveUncertain;
        });
      }
      _top();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _sending = false;
        });
      }
    }
  }

  Widget _relation(
    String field,
    String label,
    String path, {
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: VhcRelationField(
      field: "box-$field",
      label: label,
      path: path,
      required: required,
      browser: _browser,
      value: _draft.relations[field],
      error: _errors[field],
      filters: field == "pallet" && _draft.relations["shipment"] != null
          ? {"shipment": "${_draft.relations["shipment"]!["pk"]}"}
          : const {},
      onChanged: (row) {
        _draft.selectRelation(field, row);
        _change();
      },
    ),
  );

  String _errorLabel(String path) {
    final names = {
      "box_number": L10().vhcBoxNumber,
      "team": L10().vhcTeam,
      "items": L10().vhcContents,
      "part_name": L10().part,
      "part": L10().part,
      "quantity": L10().quantity,
      "size": L10().stockSize,
      "sterile": L10().stockSterility,
      "expiry_date": L10().expiryDate,
      "expiry_label": L10().vhcExpiryLabel,
      "note": L10().notes,
      "source": L10().vhcSource,
      "shipment": L10().shipment,
      "pallet": L10().vhcPallet,
      "current_location": L10().stockLocation,
      "destination": L10().destination,
      "other_team_description": L10().vhcOtherTeam,
    };
    final parts = path.split(".");
    if (parts.length > 2 && parts.first == "items") {
      return "${L10().part} ${(int.tryParse(parts[1]) ?? 0) + 1} — ${names[parts.last] ?? parts.last.replaceAll("_", " ")}";
    }
    return names[path] ?? path.replaceAll("_", " ");
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _writer.canSave(_draft.editing);
    return PopScope<VhcBox>(
      canPop: _allowPop || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_draft.editing ? L10().vhcEditBox : L10().vhcCreateBox),
          actions: [
            if (canSave)
              IconButton(
                tooltip: L10().save,
                onPressed: _busy || _conflict || _uncertain || _blocked
                    ? null
                    : _save,
                icon: const Icon(Icons.save_outlined),
              ),
          ],
        ),
        body: !canSave
            ? const Center(child: VhcErrorView(VhcReadException(403)))
            : Column(
                children: [
                  if (_sending) const LinearProgressIndicator(),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_message != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_message!),
                                    for (final error in _errors.entries)
                                      Text(
                                        "${_errorLabel(error.key)}: ${error.value}",
                                      ),
                                    if ((_conflict || _uncertain) &&
                                        _draft.editing)
                                      TextButton(
                                        onPressed: _busy ? null : _reload,
                                        child: Text(L10().vhcReloadBox),
                                      ),
                                    if (_uncertain && !_draft.editing)
                                      TextButton(
                                        onPressed: _busy ? null : _leave,
                                        child: Text(L10().vhcReviewBoxes),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          AbsorbPointer(
                            absorbing: _busy,
                            child: ExcludeFocus(
                              excluding: _busy,
                              child: Column(
                                key: ValueKey(_version),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    key: const ValueKey("box-number"),
                                    initialValue: _draft.number,
                                    maxLength: 6,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: L10().vhcBoxNumber,
                                      helperText: _draft.editing
                                          ? null
                                          : L10().vhcAutoNumber,
                                      errorText: _errors["box_number"],
                                    ),
                                    onChanged: (value) {
                                      _draft.number = value;
                                      _change();
                                    },
                                  ),
                                  _relation(
                                    "team",
                                    L10().vhcTeam,
                                    "vhc/team/",
                                    required: true,
                                  ),
                                  if (_draft.relations["team"]?["code"] ==
                                          "OTHER" ||
                                      _draft.otherTeam.isNotEmpty)
                                    TextFormField(
                                      initialValue: _draft.otherTeam,
                                      maxLength: 100,
                                      decoration: InputDecoration(
                                        labelText: L10().vhcOtherTeam,
                                        errorText:
                                            _errors["other_team_description"],
                                      ),
                                      onChanged: (value) {
                                        _draft.otherTeam = value;
                                        _change();
                                      },
                                    ),
                                  Text(
                                    L10().vhcContents,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  for (
                                    var index = 0;
                                    index < _draft.items.length;
                                    index++
                                  )
                                    VhcBoxItemEditor(
                                      key: ObjectKey(_draft.items[index]),
                                      item: _draft.items[index],
                                      index: index,
                                      browser: _browser,
                                      errors: _errors,
                                      changed: _change,
                                      remove: () {
                                        _draft.items.removeAt(index);
                                        _change();
                                      },
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      _draft.items.add(VhcItemDraft());
                                      _change();
                                    },
                                    icon: const Icon(Icons.add),
                                    label: Text(L10().vhcAddItem),
                                  ),
                                  _relation(
                                    "current_location",
                                    L10().stockLocation,
                                    "stock/location/",
                                  ),
                                  _relation(
                                    "destination",
                                    L10().destination,
                                    "stock/location/",
                                  ),
                                  _relation(
                                    "shipment",
                                    L10().shipment,
                                    "vhc/shipment/",
                                  ),
                                  if (!_draft.editing)
                                    Text(L10().vhcAutoShipment),
                                  _relation(
                                    "pallet",
                                    L10().vhcPallet,
                                    "vhc/pallet/",
                                  ),
                                  DropdownButtonFormField<String>(
                                    initialValue: _draft.source,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: L10().vhcSource,
                                      errorText: _errors["source"],
                                    ),
                                    items:
                                        {
                                              "DONATION_PURCHASE":
                                                  L10().vhcDonationPurchase,
                                              "CONTAINER_ARRIVAL":
                                                  L10().vhcContainerArrival,
                                              "RETURNED_INVENTORY":
                                                  L10().vhcReturnedInventory,
                                              "HONDURAS_PURCHASE":
                                                  L10().vhcHondurasPurchase,
                                              "ADJUSTMENT": L10().vhcAdjustment,
                                            }.entries
                                            .map(
                                              (e) => DropdownMenuItem(
                                                value: e.key,
                                                child: Text(e.value),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (value) {
                                      _draft.source =
                                          value ?? "DONATION_PURCHASE";
                                      _change();
                                    },
                                  ),
                                  TextFormField(
                                    key: const ValueKey("box-note"),
                                    initialValue: _draft.note,
                                    maxLength: 500,
                                    maxLines: 3,
                                    decoration: InputDecoration(
                                      labelText: L10().notes,
                                      errorText: _errors["note"],
                                    ),
                                    onChanged: (value) {
                                      _draft.note = value;
                                      _change();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
