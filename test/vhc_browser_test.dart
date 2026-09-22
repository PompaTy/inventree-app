import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:dropdown_search/dropdown_search.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/stock.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/user_profile.dart";
import "package:inventree/widget/stock/vhc_stock_info.dart";
import "package:inventree/widget/vhc/box_detail.dart";
import "package:inventree/widget/vhc/box_filters.dart";
import "package:inventree/widget/vhc/box_list.dart";
import "package:inventree/widget/vhc/common.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = InvenTreeAPI();
  final fixture =
      jsonDecode(File("docs/vhc-api-examples.json").readAsStringSync())
          as Map<String, dynamic>;
  final box = fixture["created_box"] as Map<String, dynamic>;
  Future<void> access([int status = 200]) async {
    await api.refreshVhcCapabilities(
      loader: () async =>
          APIResponse(statusCode: status, data: fixture["capabilities_staff"]),
    );
  }

  setUp(() async {
    api.profile = UserProfile(
      server: "https://inventory.example",
      token: "test",
    );
    await access();
  });

  test(
    "pages accept paginated and array responses; malformed data is an error",
    () {
      expect(
        VhcBrowser.parsePage({
          "results": [box],
          "next": "?offset=25",
        }, VhcBox.fromJson).hasMore,
        isTrue,
      );
      expect(
        VhcBrowser.parsePage([box], VhcBox.fromJson).items.single.boxNumber,
        "260001",
      );
      expect(VhcBrowser.parsePage([], VhcBox.fromJson).hasMore, isFalse);
      expect(
        () => VhcBrowser.parsePage({"detail": "invalid"}, VhcBox.fromJson),
        throwsA(isA<VhcReadException>()),
      );
    },
  );

  test("list, history and lookup requests use the backend filters", () async {
    final calls = <(String, Map<String, String>)>[];
    final browser = VhcBrowser(
      request: (path, params) async {
        calls.add((path, params));
        return APIResponse(statusCode: 200, data: []);
      },
    );
    await browser.boxes(25, {
      "search": "Gloves & gauze #1",
      "team": "3",
      "status": "PACKED",
    });
    expect(calls.last.$1, "vhc/box/");
    expect(calls.last.$2, {
      "ordering": "box_number",
      "search": "Gloves & gauze #1",
      "team": "3",
      "status": "PACKED",
      "limit": "25",
      "offset": "25",
    });
    await browser.events(7, 25);
    expect(calls.last.$1, "vhc/event/");
    expect(calls.last.$2, {
      "box": "7",
      "ordering": "-timestamp",
      "limit": "25",
      "offset": "25",
    });
    await browser.choices("vhc/pallet/", "Pallet 2", shipment: "4");
    expect(calls.last.$2["shipment"], "4");
  });

  test(
    "an account change rejects an in-flight response and future reads",
    () async {
      final pending = Completer<APIResponse>();
      final browser = VhcBrowser(request: (_, _) => pending.future);
      final response = browser.box(7);
      final assertion = expectLater(response, throwsA(isA<VhcReadException>()));
      api.profile = UserProfile(
        server: "https://another.example",
        token: "other",
      );
      await access();
      pending.complete(APIResponse(statusCode: 200, data: box));
      await assertion;
      expect(browser.canRead, isFalse);
      await expectLater(browser.boxes(0, {}), throwsA(isA<VhcReadException>()));
    },
  );

  test("unauthorized, deleted and server errors stay distinct", () async {
    for (final status in [403, 404, 503]) {
      final browser = VhcBrowser(
        request: (_, _) async => APIResponse(statusCode: status),
      );
      await expectLater(
        browser.box(7),
        throwsA(
          isA<VhcReadException>().having((e) => e.status, "status", status),
        ),
      );
    }
  });

  testWidgets("unsupported servers do not issue box reads", (tester) async {
    await access(404);
    var reads = 0;
    final browser = VhcBrowser(
      request: (_, _) async {
        reads++;
        return APIResponse();
      },
    );
    await tester.pumpWidget(MaterialApp(home: VhcBoxList(browser: browser)));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.textContaining("unavailable for this account"), findsOneWidget);
  });

  testWidgets("list searches, loads the next page, and opens a native detail", (
    tester,
  ) async {
    final calls = <Map<String, String>>[];
    final browser = VhcBrowser(
      request: (path, params) async {
        if (path == "vhc/box/7/") {
          return APIResponse(statusCode: 200, data: box);
        }
        if (path == "vhc/event/") return APIResponse(statusCode: 200, data: []);
        calls.add({...params});
        final second = params["offset"] != "0";
        return APIResponse(
          statusCode: 200,
          data: {
            "results": [
              if (!second) box else {...box, "pk": 8, "box_number": "000008"},
            ],
            "next": second ? null : "?offset=1",
          },
        );
      },
    );
    await tester.pumpWidget(MaterialApp(home: VhcBoxList(browser: browser)));
    await tester.pumpAndSettle();
    expect(find.text("Box 260001"), findsOneWidget);
    await tester.tap(find.text("Load more"));
    await tester.pumpAndSettle();
    expect(calls.last["offset"], "1");
    expect(find.text("Box 000008"), findsOneWidget);
    await tester.enterText(find.byType(TextField), "Gloves & gauze");
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(calls.last["search"], "Gloves & gauze");
    expect(calls.last["offset"], "0");
    await tester.tap(find.text("Box 260001"));
    await tester.pumpAndSettle();
    expect(find.byType(VhcBoxDetail), findsOneWidget);
    expect(find.text("Packed"), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, "Contents"));
    await tester.pumpAndSettle();
    expect(find.textContaining("12.00000"), findsOneWidget);
    expect(find.text("Open linked stock"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("pagination retries a failed next page without losing rows", (
    tester,
  ) async {
    var fails = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VhcPagedList<int>(
            load: (offset) async {
              if (offset == 0) return const VhcPage([1], hasMore: true);
              if (fails) throw const VhcReadException(503);
              return const VhcPage([2]);
            },
            emptyText: "empty",
            itemBuilder: (_, value) => Text("Row $value"),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("Load more"));
    await tester.pumpAndSettle();
    expect(find.text("Row 1"), findsOneWidget);
    expect(find.text("Try again"), findsOneWidget);
    fails = false;
    await tester.tap(find.text("Try again"));
    await tester.pumpAndSettle();
    expect(find.text("Row 2"), findsOneWidget);
    expect(find.text("Row 1"), findsOneWidget);
  });

  testWidgets("new searches ignore late old responses", (tester) async {
    final pending = Completer<APIResponse>();
    final browser = VhcBrowser(
      request: (_, params) async {
        if (params["search"] == "") return pending.future;
        return APIResponse(
          statusCode: 200,
          data: [
            {...box, "box_number": "000009"},
          ],
        );
      },
    );
    await tester.pumpWidget(MaterialApp(home: VhcBoxList(browser: browser)));
    await tester.pump();
    await tester.enterText(find.byType(TextField), "new");
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    pending.complete(APIResponse(statusCode: 200, data: [box]));
    await tester.pumpAndSettle();
    expect(find.text("Box 000009"), findsOneWidget);
    expect(find.text("Box 260001"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("deleted box shows an error, not stale summary contents", (
    tester,
  ) async {
    final browser = VhcBrowser(
      request: (_, _) async => APIResponse(statusCode: 404),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VhcBoxDetail(7, boxNumber: "260001", browser: browser),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("This box is no longer available."), findsOneWidget);
    expect(find.textContaining("Bandages"), findsNothing);
  });

  testWidgets("empty and failed history remain distinct", (tester) async {
    var historyFails = false;
    final browser = VhcBrowser(
      request: (path, _) async {
        if (path == "vhc/box/7/") {
          return APIResponse(statusCode: 200, data: box);
        }
        return APIResponse(statusCode: historyFails ? 503 : 200, data: []);
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: VhcBoxDetail(7, browser: browser)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("History"));
    await tester.pumpAndSettle();
    expect(find.text("No box history yet."), findsOneWidget);
    historyFails = true;
    await tester.tap(find.byTooltip("Refresh"));
    await tester.pumpAndSettle();
    expect(find.text("No box history yet."), findsNothing);
    expect(find.text("Try again"), findsOneWidget);
  });

  testWidgets(
    "filter selection retains labels and resets pallet when shipment changes",
    (tester) async {
      final browser = VhcBrowser(
        request: (_, _) async => APIResponse(statusCode: 200, data: []),
      );
      VhcFilterSelection? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text("Filters"),
                onPressed: () async {
                  selection = await showDialog<VhcFilterSelection>(
                    context: context,
                    builder: (_) => VhcBoxFilters(
                      browser: browser,
                      selection: const VhcFilterSelection(
                        {"shipment": "1", "pallet": "2"},
                        {"shipment": "Autumn", "pallet": "Pallet 2"},
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text("Filters"));
      await tester.pumpAndSettle();
      final shipment = tester.widget<DropdownSearch<Map<String, dynamic>>>(
        find.byKey(const ValueKey("shipment:1")),
      );
      shipment.onChanged!({"pk": 3, "reference": "Winter"});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("pallet:null")), findsOneWidget);
      await tester.tap(find.text("Apply"));
      await tester.pumpAndSettle();
      expect(selection!.values["shipment"], "3");
      expect(selection!.labels["shipment"], "Winter");
      expect(selection!.values.containsKey("pallet"), isFalse);
    },
  );

  testWidgets("stock box link opens native route without launching the web app", (
    tester,
  ) async {
    final item = InvenTreeStockItem.fromJson({
      "vhc_box": {"pk": 7, "box_number": "000007"},
    });
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: VhcStockInfo(item))),
    );
    // Revoke access before opening so no live server is needed for this route test.
    await access(404);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(tester.widget<VhcBoxDetail>(find.byType(VhcBoxDetail)).boxId, 7);
    expect(find.textContaining("unavailable for this account"), findsOneWidget);
  });

  testWidgets("history displays legacy and structured decimal changes", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              VhcEventTile(
                VhcBoxEvent.fromJson({
                  "pk": 1,
                  "action_text": "Edited",
                  "user_name": "Operator",
                  "changes": {
                    "items": {
                      "from": "Gloves (2)",
                      "to": [
                        {
                          "part_name": "Gloves",
                          "quantity": "3.00001",
                          "expiry_label": "ER",
                        },
                      ],
                    },
                  },
                }),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text("Edited"));
    await tester.pumpAndSettle();
    expect(find.textContaining("3.00001"), findsOneWidget);
    expect(find.textContaining("Gloves (2)"), findsOneWidget);
    expect(find.textContaining("ER"), findsOneWidget);
  });

  testWidgets("box views fit a phone with large text and long team names", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final largeBox = {
      ...box,
      "team_detail": {
        "pk": 1,
        "name": "General Medicine and Surgical Supplies Team",
        "color": "invalid",
      },
    };
    final browser = VhcBrowser(
      request: (path, _) async => APIResponse(
        statusCode: 200,
        data: path == "vhc/box/7/" ? largeBox : [largeBox],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: VhcBoxList(browser: browser),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text("Box 260001"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, "Contents"));
    await tester.pumpAndSettle();
    expect(find.textContaining("12.00000"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("disconnect removes already displayed boxes", (tester) async {
    final browser = VhcBrowser(
      request: (_, _) async => APIResponse(statusCode: 200, data: [box]),
    );
    await tester.pumpWidget(MaterialApp(home: VhcBoxList(browser: browser)));
    await tester.pumpAndSettle();
    expect(find.text("Box 260001"), findsOneWidget);
    api.disconnectFromServer();
    await tester.pumpAndSettle();
    expect(find.text("Box 260001"), findsNothing);
    expect(find.textContaining("unavailable for this account"), findsOneWidget);
  });
}
