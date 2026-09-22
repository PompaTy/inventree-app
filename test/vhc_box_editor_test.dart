import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:dropdown_search/dropdown_search.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_box_writer.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/user_profile.dart";
import "package:inventree/widget/vhc/box_editor.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures =
      jsonDecode(File("docs/vhc-api-examples.json").readAsStringSync())
          as Map<String, dynamic>;
  Map<String, dynamic> data() =>
      jsonDecode(jsonEncode(fixtures["created_box"])) as Map<String, dynamic>;
  VhcBox box() => VhcBox.fromJson(data());
  setUp(() async {
    InvenTreeAPI().profile = UserProfile(
      server: "https://inventory.example",
      token: "test",
    );
    await InvenTreeAPI().refreshVhcCapabilities(
      loader: () async =>
          APIResponse(statusCode: 200, data: fixtures["capabilities_staff"]),
    );
  });

  Future<void> open(
    WidgetTester tester,
    VhcBrowser browser,
    VhcBoxWriter writer, {
    bool creating = false,
    void Function(VhcBox?)? done,
    bool phone = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: phone
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              )
            : null,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text("Open"),
              onPressed: () async {
                final result = await Navigator.push<VhcBox>(
                  context,
                  MaterialPageRoute<VhcBox>(
                    builder: (_) => VhcBoxEditor(
                      box: creating ? null : box(),
                      browser: browser,
                      writer: writer,
                    ),
                  ),
                );
                done?.call(result);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text("Open"));
    await tester.pumpAndSettle();
  }

  void select(WidgetTester tester, String key, Map<String, dynamic> row) =>
      tester
          .widget<DropdownSearch<Map<String, dynamic>>>(
            find.byKey(ValueKey(key)),
          )
          .onChanged!(row);
  Future<void> quantity(WidgetTester tester, String value) async {
    final finder = find.byKey(const ValueKey("item-quantity"));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, value);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byTooltip("Save"));
    await tester.pumpAndSettle();
  }

  testWidgets(
    "creating a box sends a decimal string and opens the saved result",
    (tester) async {
      final browser = VhcBrowser();
      Map<String, dynamic>? sent;
      VhcBox? saved;
      final writer = VhcBoxWriter(
        browser,
        request: (path, method, body) async {
          expect(path, "vhc/box/");
          expect(method, "POST");
          sent = body;
          return APIResponse(statusCode: 201, data: data());
        },
      );
      await open(
        tester,
        browser,
        writer,
        creating: true,
        done: (value) => saved = value,
      );
      select(tester, "box-team", {"pk": 1, "name": "General"});
      await tester.pump();
      select(tester, "item-0-part", {"pk": 1, "name": "Bandages"});
      await tester.pump();
      await quantity(tester, "9999999999.99999");
      await save(tester);
      expect(sent!["box_number"], "");
      expect(sent!["items"][0]["quantity"], "9999999999.99999");
      expect(saved!.pk, 7);
      expect(find.byType(VhcBoxEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    "item validation and nested server errors keep the draft editable",
    (tester) async {
      final browser = VhcBrowser();
      var calls = 0;
      final writer = VhcBoxWriter(
        browser,
        request: (_, _, body) async {
          calls++;
          return APIResponse(
            statusCode: 400,
            data: {
              "items": [
                {
                  "quantity": ["Quantity not allowed."],
                },
              ],
            },
          );
        },
      );
      await open(tester, browser, writer);
      await quantity(tester, "0");
      await save(tester);
      expect(calls, 0);
      expect(find.textContaining("positive quantity"), findsWidgets);
      await quantity(tester, "2.00001");
      await save(tester);
      expect(calls, 1);
      expect(find.text("Quantity not allowed."), findsOneWidget);
      expect(
        tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey("item-quantity")),
                )
                .controller
                ?.text ??
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey("item-quantity")),
                )
                .initialValue,
        isNotNull,
      );
      expect(find.byType(VhcBoxEditor), findsOneWidget);
    },
  );

  testWidgets(
    "a conflict preserves edits and requires explicit reload before another save",
    (tester) async {
      final newer = {
        ...data(),
        "revision": 2,
        "items": [
          {
            ...(data()["items"] as List<dynamic>).single
                as Map<String, dynamic>,
            "quantity": "4.00000",
          },
        ],
      };
      final browser = VhcBrowser(
        request: (_, _) async => APIResponse(statusCode: 200, data: newer),
      );
      final revisions = <int>[];
      final writer = VhcBoxWriter(
        browser,
        request: (_, _, body) async {
          revisions.add(body["revision"] as int);
          return revisions.length == 1
              ? APIResponse(statusCode: 409, data: {"revision": "Conflict"})
              : APIResponse(statusCode: 200, data: {...newer, "revision": 3});
        },
      );
      await open(tester, browser, writer);
      await quantity(tester, "7.00000");
      await save(tester);
      expect(find.textContaining("Your draft is still here"), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == "Save",
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text("Reload latest box"));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, "Reload latest box"));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey("item-quantity")))
            .initialValue,
        "4.00000",
      );
      await save(tester);
      expect(revisions, [1, 2]);
      expect(find.byType(VhcBoxEditor), findsNothing);
    },
  );

  testWidgets(
    "replacing an existing part asks before deleting its linked stock",
    (tester) async {
      final browser = VhcBrowser();
      var calls = 0;
      final writer = VhcBoxWriter(
        browser,
        request: (_, _, body) async {
          calls++;
          return APIResponse(statusCode: 200, data: data());
        },
      );
      await open(tester, browser, writer);
      select(tester, "item-0-part", {"pk": 2, "name": "Gloves"});
      await tester.pump();
      await save(tester);
      expect(find.text("Remove linked stock?"), findsOneWidget);
      expect(find.textContaining("Bandages"), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.text("Cancel"));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await save(tester);
      await tester.tap(find.widgetWithText(FilledButton, "Save"));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets("a pending save cannot be submitted twice", (tester) async {
    final pending = Completer<APIResponse>();
    final browser = VhcBrowser();
    var calls = 0;
    final writer = VhcBoxWriter(
      browser,
      request: (_, _, _) {
        calls++;
        return pending.future;
      },
    );
    await open(tester, browser, writer);
    await tester.tap(find.byTooltip("Save"));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == "Save",
            ),
          )
          .onPressed,
      isNull,
    );
    pending.complete(APIResponse(statusCode: 200, data: data()));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets(
    "an uncertain create is not automatically or repeatedly submitted",
    (tester) async {
      final browser = VhcBrowser();
      var calls = 0;
      final writer = VhcBoxWriter(
        browser,
        request: (_, _, _) async {
          calls++;
          return APIResponse(statusCode: 503);
        },
      );
      await open(tester, browser, writer, creating: true);
      select(tester, "box-team", {"pk": 1, "name": "General"});
      await tester.pump();
      select(tester, "item-0-part", {"pk": 1, "name": "Bandages"});
      await tester.pump();
      await save(tester);
      expect(find.textContaining("server may have saved it"), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == "Save",
              ),
            )
            .onPressed,
        isNull,
      );
      expect(calls, 1);
    },
  );

  testWidgets("leaving a changed form offers to keep or discard the draft", (
    tester,
  ) async {
    final browser = VhcBrowser();
    final writer = VhcBoxWriter(browser);
    await open(tester, browser, writer);
    await quantity(tester, "3");
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text("Discard unsaved changes?"), findsOneWidget);
    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();
    expect(find.byType(VhcBoxEditor), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, "Discard"));
    await tester.pumpAndSettle();
    expect(find.byType(VhcBoxEditor), findsNothing);
  });

  testWidgets("sterility and expiry controls clear incompatible values", (
    tester,
  ) async {
    final browser = VhcBrowser();
    await open(tester, browser, VhcBoxWriter(browser));
    final labelFinder = find.byKey(const ValueKey("expiry::S"));
    tester.widget<DropdownButtonFormField<String>>(labelFinder).onChanged!(
      "ER",
    );
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey("item-date:1")))
          .initialValue,
      "",
    );
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey("sterile:S")),
        )
        .onChanged!("NS");
    await tester.pump();
    expect(find.byKey(const ValueKey("expiry::NS")), findsOneWidget);
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey("expiry::NS")),
        )
        .onChanged!("N/A");
    await tester.pump();
    expect(find.byKey(const ValueKey("expiry:N/A:NS")), findsOneWidget);
  });

  testWidgets("the editor remains usable at phone width with enlarged text", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final browser = VhcBrowser();
    await open(tester, browser, VhcBoxWriter(browser), phone: true);
    await quantity(tester, "9999999999.99999");
    await tester.ensureVisible(find.byKey(const ValueKey("box-note")));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("disconnect disables saving and hides the draft", (tester) async {
    final browser = VhcBrowser();
    await open(tester, browser, VhcBoxWriter(browser));
    InvenTreeAPI().disconnectFromServer();
    await tester.pumpAndSettle();
    expect(find.byTooltip("Save"), findsNothing);
    expect(find.textContaining("unavailable for this account"), findsOneWidget);
    expect(find.byKey(const ValueKey("item-quantity")), findsNothing);
  });
}
