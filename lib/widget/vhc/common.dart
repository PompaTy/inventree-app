import "package:flutter/material.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/l10.dart";

String vhcReadError(Object? error) {
  final status = error is VhcReadException ? error.status : -1;
  if (status == 401 || status == 403) return L10().vhcAccessUnavailable;
  if (status == 404) return L10().vhcBoxMissing;
  return L10().errorFetch;
}

class VhcErrorView extends StatelessWidget {
  const VhcErrorView(this.error, {this.retry, super.key});
  final Object? error;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(vhcReadError(error), textAlign: TextAlign.center),
        if (retry != null)
          TextButton(onPressed: retry, child: Text(L10().vhcRetry)),
      ],
    ),
  );
}

class VhcTeamBadge extends StatelessWidget {
  const VhcTeamBadge(this.team, {super.key});
  final VhcTeam team;
  @override
  Widget build(BuildContext context) {
    final hex = team.color.replaceFirst("#", "");
    final color = RegExp(r"^[0-9a-fA-F]{6}$").hasMatch(hex)
        ? Color(0xff000000 | int.parse(hex, radix: 16))
        : Theme.of(context).colorScheme.primary;
    return Chip(
      avatar: Icon(Icons.circle, color: color, size: 14),
      label: Text(team.name),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Pagination with independent initial / next-page errors and stale-request guards.
class VhcPagedList<T> extends StatefulWidget {
  const VhcPagedList({
    required this.load,
    required this.itemBuilder,
    required this.emptyText,
    super.key,
  });
  final Future<VhcPage<T>> Function(int offset) load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  @override
  State<VhcPagedList<T>> createState() => _VhcPagedListState<T>();
}

class _VhcPagedListState<T> extends State<VhcPagedList<T>> {
  final List<T> _items = [];
  bool _busy = false;
  bool _more = true;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy && !reset) return;
    final generation = ++_generation;
    setState(() {
      if (reset) {
        _items.clear();
        _more = true;
      }
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.load(_items.length);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _more = page.hasMore && page.items.isNotEmpty;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        if (error is VhcReadException &&
            (error.status == 401 || error.status == 403)) {
          _items.clear();
        }
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => _load(reset: true),
    child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length + 1,
      itemBuilder: (context, index) {
        if (index < _items.length) {
          return widget.itemBuilder(context, _items[index]);
        }
        if (_busy) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (_error != null) return VhcErrorView(_error, retry: _load);
        if (_items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(widget.emptyText, textAlign: TextAlign.center),
          );
        }
        if (_more) {
          return TextButton(onPressed: _load, child: Text(L10().vhcLoadMore));
        }
        return const SizedBox(height: 24);
      },
    ),
  );
}
