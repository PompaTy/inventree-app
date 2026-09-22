import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter_test/flutter_test.dart";
import "package:inventree/api.dart";
import "package:inventree/inventree/vhc.dart";
import "package:inventree/inventree/vhc_box_draft.dart";
import "package:inventree/inventree/vhc_box_writer.dart";
import "package:inventree/inventree/vhc_browser.dart";
import "package:inventree/user_profile.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures =
      jsonDecode(File("docs/vhc-api-examples.json").readAsStringSync())
          as Map<String, dynamic>;
  VhcBox box() => VhcBox.fromJson(
    jsonDecode(jsonEncode(fixtures["created_box"])) as Map<String, dynamic>,
  );
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
  VhcBoxDraft create() {
    final draft = VhcBoxDraft();
    draft.relations["team"] = {"pk": 1, "name": "General"};
    draft.items.single.partName = " New gloves ";
    draft.items.single.quantity = "9999999999.99999";
    return draft;
  }

  test(
    "creation retains decimal text and lets the server assign number and shipment",
    () {
      final payload = create().toJson();
      expect(payload["box_number"], "");
      expect(payload["shipment"], isNull);
      expect(payload.containsKey("revision"), isFalse);
      expect((payload["items"] as List<dynamic>).single, {
        "part_name": "New gloves",
        "quantity": "9999999999.99999",
        "size": "",
        "sterile": "",
        "expiry_date": null,
        "expiry_label": "",
      });
    },
  );

  test(
    "metadata edits omit unchanged items and preserve explicit null relationships",
    () {
      final source = box();
      final draft = VhcBoxDraft.fromBox(source);
      source.setValue("revision", 99);
      draft.number = "000007";
      draft.note = "Changed note";
      draft.otherTeam = "Medical team";
      draft.selectRelation("current_location", null);
      final payload = draft.toJson();
      expect(payload.containsKey("items"), isFalse);
      expect(payload["current_location"], isNull);
      expect(payload["box_number"], "000007");
      expect(payload["note"], "Changed note");
      expect(payload["other_team_description"], "Medical team");
      expect(draft.original!.revision, 1);
    },
  );

  test("legacy boxes with no structured items can still edit metadata", () {
    final source = box()..setValue("items", []);
    final draft = VhcBoxDraft.fromBox(source)..note = "Legacy note";
    expect(draft.validate(), isEmpty);
    expect(draft.toJson().containsKey("items"), isFalse);
  });

  test(
    "validation catches missing team, empty items, invalid dates and decimals",
    () {
      final draft = VhcBoxDraft();
      expect(draft.validate().keys, containsAll(["team", "items.0.part_name"]));
      draft.items.clear();
      expect(draft.validate().keys, contains("items"));
      final item = VhcItemDraft()..partName = "Gloves";
      for (final quantity in ["0", "-1", "0.000001", "10000000000", "NaN"]) {
        item.quantity = quantity;
        expect(item.validate().keys, contains("quantity"));
      }
      item.quantity = "0.00001";
      item.date = "2027-02-29";
      expect(item.validate().keys, contains("expiry_date"));
      item.date = "2028-02-29";
      expect(item.validate(), isEmpty);
    },
  );

  test(
    "expiry changes clear incompatible values and serialize explicit null",
    () {
      final draft = VhcBoxDraft.fromBox(box());
      final item = draft.items.single;
      item.setLabel("ER");
      expect(item.date, isNull);
      item.setSterile("NS");
      expect(item.label, "");
      item.setLabel("N/A");
      expect(item.validate(), isEmpty);
      expect(
        (draft.toJson()["items"] as List<dynamic>).single["expiry_date"],
        isNull,
      );
      item.setDate("2028-12-31");
      expect(item.label, "");
      expect(item.date, "2028-12-31");
    },
  );

  test(
    "duplicate parts are rejected but distinct selected parts can share a name",
    () {
      final draft = VhcBoxDraft.fromBox(box());
      final duplicate = VhcItemDraft.fromItem(box().items.single);
      draft.items.add(duplicate);
      expect(draft.validate().keys, contains("items.1.part_name"));
      duplicate.partId = 2;
      expect(draft.validate(), isEmpty);
      duplicate.partId = null;
      duplicate.partName = " bandages ";
      expect(draft.validate().keys, contains("items.1.part_name"));
    },
  );

  test(
    "changing shipment clears pallet; selecting pallet includes its shipment",
    () {
      final draft = create();
      draft.selectRelation("pallet", {
        "pk": 3,
        "shipment": 7,
        "shipment_detail": {"pk": 7, "reference": "Autumn"},
      });
      expect(draft.toJson()["shipment"], 7);
      draft.selectRelation("shipment", {"pk": 8});
      expect(draft.toJson()["pallet"], isNull);
      expect(draft.toJson()["shipment"], 8);
    },
  );

  test("removed and replaced parts are identified before saving", () {
    final draft = VhcBoxDraft.fromBox(box());
    expect(draft.removedStock, isEmpty);
    draft.items.single.partId = 123;
    draft.items.single.partName = "Other supply";
    expect(draft.removedStock, ["Bandages"]);
  });

  test("nested backend errors retain row and field paths", () {
    expect(
      vhcBoxErrors({
        "team": ["Required."],
        "items": [
          {},
          {
            "quantity": ["Too large."],
          },
        ],
      }),
      {"team": "Required.", "items.1.quantity": "Too large."},
    );
    expect(vhcBoxErrors({"items": "Duplicate item."}), {
      "items": "Duplicate item.",
    });
  });

  test(
    "writer posts new boxes and patches the original revision without retry",
    () async {
      final calls = <Map<String, dynamic>>[];
      final writer = VhcBoxWriter(
        VhcBrowser(),
        request: (path, method, body) async {
          calls.add({"path": path, "method": method, "body": body});
          return APIResponse(statusCode: 409, data: {"revision": "Conflict"});
        },
      );
      await writer.save(create());
      expect(calls.single["method"], "POST");
      expect(calls.single["path"], "vhc/box/");
      final response = await writer.save(
        VhcBoxDraft.fromBox(box())..note = "new",
      );
      expect(calls.last["method"], "PATCH");
      expect(calls.last["path"], "vhc/box/7/");
      expect(calls.last["body"]["revision"], 1);
      expect(response.statusCode, 409);
      expect(calls.length, 2);
    },
  );

  test(
    "permission or account changes block writes and stale success responses",
    () async {
      final pending = Completer<APIResponse>();
      var calls = 0;
      final writer = VhcBoxWriter(
        VhcBrowser(),
        request: (_, _, _) {
          calls++;
          return pending.future;
        },
      );
      final future = writer.save(create());
      final assertion = expectLater(future, throwsA(isA<VhcReadException>()));
      InvenTreeAPI().profile = UserProfile(
        server: "https://other.example",
        token: "other",
      );
      pending.complete(
        APIResponse(statusCode: 201, data: fixtures["created_box"]),
      );
      await assertion;
      await expectLater(
        writer.save(create()),
        throwsA(isA<VhcReadException>()),
      );
      expect(calls, 1);
    },
  );
}
