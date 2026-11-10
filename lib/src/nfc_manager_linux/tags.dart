import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:nfc_manager/src/nfc_manager/nfc_manager.dart';

enum TagProtocol { felica, mifare, jewel, isoDep, nfcDep }

final class NdefLinux {
  const NdefLinux._({
    required this.type,
    required this.protocol,
    required this.isWritable,
    required this.adapterDbusObjectPath,
    required this.dbusObjectPath,
    required this.uid,
  });

  final String type;
  final TagProtocol protocol;
  final bool isWritable;
  final String adapterDbusObjectPath;
  final String dbusObjectPath;
  final Uint8List uid;

  static NdefLinux? from(NfcTag tag) {
    // ignore: invalid_use_of_protected_member
    final data = tag.data as Map<String, DBusValue>?;
    if (data == null) return null;

    final type = data["Type"]!.asString();
    final protocol = data["Protocol"]!.asString();
    final isReadOnly = data["ReadOnly"]!.asBoolean();
    final adapter = data["Adapter"]!.asObjectPath();
    final uid = data["Uid"]!.asByteArray();
    final tagPath = data["Tag"]!.asObjectPath();

    final parsedProtocol = switch (protocol) {
      "Felica" => TagProtocol.felica,
      "MIFARE" => TagProtocol.mifare,
      "Jewel" => TagProtocol.jewel,
      "ISO-DEP" => TagProtocol.isoDep,
      "NFC-DEP" => TagProtocol.nfcDep,
      _ => null,
    };

    if (parsedProtocol == null) return null;

    return NdefLinux._(
      type: type,
      protocol: parsedProtocol,
      isWritable: !isReadOnly,
      adapterDbusObjectPath: adapter.value,
      dbusObjectPath: tagPath.value,
      uid: Uint8List.fromList([...uid]),
    );
  }

  Future<Uint8List> write(Uint8List bytes) async {
    final tagObject = DBusRemoteObject(
      DBusClient.system(),
      name: "org.neard",
      path: DBusObjectPath(dbusObjectPath),
    );

    // final result = await tagObject.callMethod(
    //   "org.freedesktop.DBus.Introspectable",
    //   "Introspect",
    //   [],
    // );

    final result = await tagObject.callMethod("org.neard.Tag", "Write", [
      // DBusArray(.dict(.string, .variant), [
      DBusDict.stringVariant({
        "Type": DBusString("MIME"),
        "MIME": DBusString("application/octet-stream"),
        "MIMEPayload": DBusArray.byte(bytes),
        // "Records": DBusArray(.dict(.string, .variant), [
        //   DBusDict.stringVariant({
        //     "Type": DBusString("MIME"),
        //     "MIMEPayload": DBusArray.byte(bytes),
        //   }),
        // ]),
      }),

      // ]),
    ]);

    print("Response of trying to write to tag: $result");

    return Uint8List.fromList([]);
  }
}
