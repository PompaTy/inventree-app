import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:dropdown_search/dropdown_search.dart";
import "package:datetime_picker_formfield/datetime_picker_formfield.dart";
import "package:flutter_test/flutter_test.dart";
import "package:inventree/api.dart";
import "package:inventree/api_form.dart";
import "package:inventree/inventree/stock.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_api.dart";
import "package:inventree/inventree/vhc_capabilities.dart";
import "package:inventree/user_profile.dart";
import "package:inventree/widget/stock/vhc_stock_form.dart";
import "package:inventree/widget/stock/vhc_stock_info.dart";
import "package:inventree/widget/stock/stock_list.dart";

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = InvenTreeAPI();
  final fixtures =
      jsonDecode(File("docs/vhc-api-examples.json").readAsStringSync())
          as Map<String, dynamic>;
  final staff = fixtures["capabilities_staff"] as Map<String, dynamic>;

  Future<void> capabilities([int status = 200, dynamic data]) async {
    await api.refreshVhcCapabilities(
      loader: () async => APIResponse(statusCode: status, data: data ?? staff),
    );
  }

  setUp(() {
    api.profile = UserProfile(
      server: "https://inventory.example",
      token: "test",
    );
  });

  test("discovery distinguishes unsupported, unauthorized and unavailable", () {
    for (final entry in {
      404: VhcAvailability.unsupported,
      401: VhcAvailability.unauthorized,
      403: VhcAvailability.unauthorized,
      500: VhcAvailability.unavailable,
      -1: VhcAvailability.unavailable,
    }.entries) {
      expect(
        VhcCapabilities.fromResponse(entry.key, {}).availability,
        entry.value,
      );
    }
    expect(
      VhcCapabilities.fromResponse(200, "html").availability,
      VhcAvailability.unavailable,
    );
    expect(
      VhcCapabilities.fromResponse(200, {"version": 2}).availability,
      VhcAvailability.unsupported,
    );
    final operator = VhcCapabilities.fromResponse(
      200,
      fixtures["capabilities_operator"],
    );
    expect(operator.allows("edit_box"), isTrue);
    expect(operator.allows("manage_teams"), isFalse);
    expect(operator.supports("boxes"), isTrue);
    expect(operator.hasStockField("size"), isTrue);
  });

  test(
    "optional HTTP discovery handles HTML errors without parsing dialogs",
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = HttpClient();
        final subscription = server.listen((request) async {
          request.response.statusCode = int.parse(
            request.uri.path.substring(1),
          );
          request.response.write("<html>Unavailable</html>");
          await request.response.close();
        });
        try {
          for (final status in [404, 403, 503, 200]) {
            final request = await client.getUrl(
              Uri.parse("http://127.0.0.1:${server.port}/$status"),
            );
            final response = await api.completeRequest(request, optional: true);
            expect(response.statusCode, status);
            expect(
              VhcCapabilities.fromResponse(status, response.data).available,
              isFalse,
            );
            if (status == 200) expect(response.error, isNotEmpty);
          }
        } finally {
          client.close(force: true);
          await subscription.cancel();
          await server.close(force: true);
        }
      }, RealHttpOverrides());
    },
  );

  test(
    "capabilities cannot leak across accounts, servers or changed tokens",
    () async {
      await capabilities();
      expect(api.vhcCapabilities.available, isTrue);
      api.profile!.token = "different";
      expect(api.vhcCapabilities.available, isFalse);
      await capabilities();
      api.profile!.server = "https://another.example";
      expect(api.vhcCapabilities.available, isFalse);
      await capabilities();
      api.profile = UserProfile(
        server: "https://another.example",
        token: "different",
      );
      expect(api.vhcCapabilities.available, isFalse);
    },
  );

  test(
    "late discovery and failed refresh cannot restore old capabilities",
    () async {
      final pending = Completer<APIResponse>();
      final old = api.refreshVhcCapabilities(loader: () => pending.future);
      api.profile = UserProfile(
        server: "https://standard.example",
        token: "other",
      );
      await capabilities(404);
      pending.complete(APIResponse(statusCode: 200, data: staff));
      await old;
      expect(api.vhcCapabilities.availability, VhcAvailability.unsupported);
      await api.refreshVhcCapabilities(
        loader: () => Future.error(const SocketException("offline")),
      );
      expect(api.vhcCapabilities.availability, VhcAvailability.unavailable);
    },
  );

  test("box and line models parse the saved backend response", () {
    final box = VhcBox.fromJson(
      fixtures["created_box"] as Map<String, dynamic>,
    );
    expect(box.revision, 1);
    expect(box.team!.name, "General Medicine");
    expect(box.shipment, isNull);
    expect(box.palletId, isNull);
    expect(box.items.single.quantity, "12.00000");
    expect(box.items.single.toWriteJson(), {
      "part": 1,
      "quantity": "12.00000",
      "size": "Large",
      "sterile": "S",
      "expiry_date": "2027-06-30",
      "expiry_label": "",
    });
    final minimal = VhcBox.fromJson({"pk": 12, "box_number": "000012"});
    expect(minimal.boxNumber, "000012");
    expect(minimal.team, isNull);
    expect(minimal.items, isEmpty);
    expect(minimal.webUrl, "https://inventory.example/web/boxes/12/");
  });

  test("quantities preserve precision and enforce the backend limits", () {
    for (final value in ["0.00001", "9999999999.99999", "12.00000", "12"]) {
      expect(vhcQuantity(value), value);
    }
    expect(vhcQuantity(12.25), "12.25");
    for (final value in [
      "0",
      "0.00000",
      "-1",
      "0.000001",
      "10000000000",
      "NaN",
      null,
    ]) {
      expect(() => vhcQuantity(value), throwsFormatException);
    }
  });

  test("calendar dates remain unchanged and reject impossible dates", () {
    expect(vhcCalendarDate("2028-02-29"), "2028-02-29");
    expect(vhcCalendarDate("2027-02-29"), isNull);
    expect(vhcCalendarDate("2027-06-30T23:00:00Z"), isNull);
    final shipment = VhcShipment.fromJson({"departure_date": "2026-11-01"});
    expect(shipment.departureDate, "2026-11-01");
    final window = VhcShipmentWindow.fromJson({
      "start_date": "2026-03-08",
      "shipment": null,
    });
    expect(window.startDate, "2026-03-08");
    expect(window.shipment, isNull);
    expect(VhcPallet.fromJson({"shipment": null}).shipmentId, isNull);
  });

  test("expiry labels follow sterility and cannot accompany a date", () {
    expect(VhcExpiry.valid("S", null, "ER"), isTrue);
    expect(VhcExpiry.valid("NS", null, "N/A"), isTrue);
    expect(VhcExpiry.valid("", "2027-01-01", ""), isTrue);
    expect(VhcExpiry.valid("NS", null, "ER"), isFalse);
    expect(VhcExpiry.valid("S", "2027-01-01", "ER"), isFalse);
    expect(
      () => VhcBoxItem.fromJson({
        "part": 1,
        "quantity": "1",
        "sterile": "NS",
        "expiry_label": "ER",
      }).toWriteJson(),
      throwsFormatException,
    );
  });

  test("history retains both legacy summaries and structured item changes", () {
    for (final changes in <Map<String, dynamic>>[
      {
        "items": {"from": "Gloves (2)", "to": "Gloves (3)"},
      },
      {
        "items": {
          "from": [
            {"quantity": "2.00000"},
          ],
          "to": [
            {"quantity": "3.00000"},
          ],
        },
      },
    ]) {
      expect(VhcBoxEvent.fromJson({"changes": changes}).changes, changes);
    }
    expect(VhcBoxEvent.fromJson({}).changes, isEmpty);
  });

  test("write payloads require revisions for every box", () {
    final box = VhcBox.fromJson({"pk": 7, "revision": 2});
    expect(VhcApi.revisionBody(box, {"revision": 99, "note": "new"}), {
      "revision": 2,
      "note": "new",
    });
    expect(VhcApi.bulkMoveBody([box], 4), {
      "boxes": [7],
      "revisions": {"7": 2},
      "location": 4,
      "notes": "",
    });
    expect(() => VhcApi.bulkMoveBody([box, box], 4), throwsArgumentError);
    expect(
      () => VhcApi.revisionBody(VhcBox.fromJson({"pk": 1}), {}),
      throwsStateError,
    );
    expect(() => VhcApi().move(box, 4), throwsStateError);
  });

  test(
    "standard servers omit custom fields; owned stock omits owned edits",
    () async {
      await capabilities(404);
      final list = const PaginatedStockItemList({}).createState();
      expect(list.orderingOptions.keys, isNot(contains("box")));
      expect(
        InvenTreeStockItem().formFields().keys,
        isNot(contains("sterile")),
      );
      expect(InvenTreeStockItem().formHandler, isNull);
      await capabilities();
      expect(list.orderingOptions.keys, containsAll(["box", "team"]));
      expect(
        InvenTreeStockItem().formFields().keys,
        containsAll(["size", "sterile", "expiry_date", "expiry_label"]),
      );
      final owned = InvenTreeStockItem.fromJson({
        "vhc_box": {"pk": 7, "box_number": "000007"},
      });
      expect(owned.isBoxed, isTrue);
      expect(
        owned.formFields().keys,
        isNot(
          anyOf(contains("size"), contains("location"), contains("quantity")),
        ),
      );
      expect(owned.formFields().keys, contains("batch"));
      expect(await owned.adjustStock("stock/add/", 1), isFalse);
      expect(InvenTreeStockItem.fromJson({}).vhcBox, isNull);
    },
  );

  test("clearing expiry does not resurrect the existing date or default", () {
    final fields = [
      APIFormField("sterile", {"value": "S"}),
      APIFormField("expiry_date", {
        "instance_value": "2027-01-01",
        "default": "2028-01-01",
      }),
      APIFormField("expiry_label", {"value": "ER"}),
    ];
    updateVhcExpiryFields(fields, "expiry_label");
    expect(fields[1].value, isNull);
    fields[0].setFieldValue("NS");
    updateVhcExpiryFields(fields, "sterile");
    expect(fields[2].value, "");
    fields[2].setFieldValue("N/A");
    updateVhcExpiryFields(fields, "expiry_label");
    fields[1].setFieldValue("2027-12-31");
    updateVhcExpiryFields(fields, "expiry_date");
    expect(fields[2].value, "");
    fields[0].setFieldValue(null);
    updateVhcExpiryFields(fields, "sterile");
    expect(fields[0].value, "");
  });

  testWidgets(
    "stock info shows box, team and special expiry only on VHC servers",
    (tester) async {
      await capabilities();
      final item = InvenTreeStockItem.fromJson({
        "size": "Large",
        "sterile": "S",
        "expiry_label": "ER",
        "vhc_box": {
          "pk": 7,
          "box_number": "000007",
          "team_detail": {"name": "Surgery"},
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VhcStockInfo(item, showOwnershipHint: true)),
        ),
      );
      expect(find.textContaining("000007"), findsOneWidget);
      expect(find.textContaining("Surgery"), findsOneWidget);
      expect(find.textContaining("ER"), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      await capabilities(404);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: VhcStockInfo(item))),
      );
      expect(find.textContaining("000007"), findsNothing);
      expect(find.textContaining("Large"), findsNothing);
    },
  );

  testWidgets(
    "expiry choices update immediately and submit an explicit null date",
    (tester) async {
      final fields = [
        APIFormField("sterile", {
          "type": "choice",
          "reactive": true,
          "value": "S",
          "choices": [
            {"value": "S", "display_name": "S"},
            {"value": "NS", "display_name": "NS"},
          ],
        }),
        APIFormField("expiry_date", {
          "type": "date",
          "reactive": true,
          "value": "2027-01-01",
          "instance_value": "2027-01-01",
        }),
        APIFormField("expiry_label", {
          "type": "choice",
          "reactive": true,
          "value": "",
        }),
      ];
      Map<String, dynamic>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: APIFormWidget(
            "Stock",
            "",
            fields,
            "PATCH",
            state: VhcStockFormState(),
            validate: (data) {
              submitted = data;
              return false;
            },
          ),
        ),
      );
      DropdownSearch<dynamic> choice(int index) =>
          tester.widget<DropdownSearch<dynamic>>(
            find.byType(DropdownSearch<dynamic>).at(index),
          );
      expect(
        choice(1).items,
        contains(equals({"value": "ER", "display_name": "ER"})),
      );
      choice(1).onChanged!({"value": "ER", "display_name": "ER"});
      await tester.pump();
      expect(
        tester.widget<DateTimeField>(find.byType(DateTimeField)).initialValue,
        isNull,
      );
      choice(0).onChanged!({"value": "NS", "display_name": "NS"});
      await tester.pump();
      expect(fields[2].value, "");
      expect(
        choice(1).items,
        contains(equals({"value": "N/A", "display_name": "N/A"})),
      );
      choice(1).onChanged!({"value": "N/A", "display_name": "N/A"});
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();
      expect(submitted, {
        "sterile": "NS",
        "expiry_date": null,
        "expiry_label": "N/A",
      });
      expect(tester.takeException(), isNull);
    },
  );
}
