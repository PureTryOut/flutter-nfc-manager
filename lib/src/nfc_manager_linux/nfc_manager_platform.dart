import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:nfc_manager/src/nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/src/nfc_manager_ios/nfc_manager.dart';

final class NfcManagerLinuxPlatform implements NfcManager {
  NfcManagerLinuxPlatform() : _client = DBusClient.system();

  final DBusClient _client;
  StreamSubscription<DBusSignal>? _deviceAddedSignal;
  StreamSubscription<DBusSignal>? _deviceRemovedSignal;

  @override
  Future<NfcAvailability> checkAvailability() async {
    final object = DBusRemoteObject(
      _client,
      name: "org.neard",
      path: DBusObjectPath("/org/neard/nfc0"),
    );

    try {
      // The "/org/neard/nfc0" path will only be available if there is a NFC adapter.
      // The only way to verify its existence is trying to call a property on it.
      await object
          .getProperty("org.neard.Adapter", "Powered")
          .timeout(const Duration(seconds: 1));
    } on DBusUnknownObjectException {
      // No NFC adapter available
      return .unsupported;
    } on DBusServiceUnknownException {
      // No neard service available, probably not installed or running
      return .unsupported;
    } on TimeoutException {
      // The NFC adapter might be available but something unexpected went wrong
      return .unsupported;
    }

    // Neard has no "disabled" state
    return .enabled;
  }

  @override
  Future<bool> isAvailable() async {
    final availability = await checkAvailability();

    return switch (availability) {
      NfcAvailability.enabled => true,
      NfcAvailability.disabled || NfcAvailability.unsupported => false,
    };
  }

  @override
  Future<void> startSession({
    required Set<NfcPollingOption> pollingOptions,
    required void Function(NfcTag tag) onDiscovered,
    String? alertMessageIos,
    bool invalidateAfterFirstReadIos = true,
    void Function(NfcReaderSessionErrorIos)? onSessionErrorIos,
    bool noPlatformSoundsAndroid = false,
  }) async {
    final adapterObject = DBusRemoteObject(
      _client,
      name: "org.neard",
      path: DBusObjectPath("/org/neard/nfc0"),
    );

    final isPoweredValue = await adapterObject.getProperty(
      "org.neard.Adapter",
      "Powered",
    );
    final isPowered = isPoweredValue.asBoolean();

    if (!isPowered) {
      await adapterObject.setProperty(
        "org.neard.Adapter",
        "Powered",
        DBusBoolean(true),
      );
    }

    await adapterObject.callMethod("org.neard.Adapter", "StartPollLoop", [
      DBusString("Initiator"),
    ]);

    final rootObject = DBusRemoteObject(
      _client,
      name: "org.neard",
      path: DBusObjectPath("/"),
    );
    final deviceAddedSignal = DBusRemoteObjectSignalStream(
      object: rootObject,
      interface: "org.freedesktop.DBus.ObjectManager",
      name: "InterfacesAdded",
    );

    _deviceAddedSignal = deviceAddedSignal.listen((signal) {
      Map<String, DBusValue> tagData = {};
      for (final value in signal.values) {
        if (value.signature == .dict(.string, .dict(.string, .variant))) {
          final dict = value.asDict();
          final data = dict[DBusString("org.neard.Tag")]?.asStringVariantDict();
          if (data == null) continue;
          tagData.addAll(data);
        }

        if (value.signature == .objectPath) {
          final tagPath = value.asObjectPath();
          tagData["Tag"] = tagPath;
        }
      }

      if (tagData.isEmpty) return;

      // ignore: invalid_use_of_visible_for_testing_member
      final tag = NfcTag(data: tagData);
      onDiscovered(tag);
    });
  }

  @override
  Future<void> stopSession({
    String? alertMessageIos,
    String? errorMessageIos,
  }) async {
    final adapterObject = DBusRemoteObject(
      _client,
      name: "org.neard",
      path: DBusObjectPath("/org/neard/nfc0"),
    );

    try {
      await adapterObject.callMethod("org.neard.Adapter", "StopPollLoop", []);
    } on DBusMethodResponseException {
      // Wasn't polling, no need to do anything
    }

    try {
      await adapterObject.setProperty(
        "org.neard.Adapter",
        "Powered",
        DBusBoolean(false),
      );
    } on DBusMethodResponseException {
      // Failed to poweroff, assume it's already off
    }

    await _deviceAddedSignal?.cancel();
    await _deviceRemovedSignal?.cancel();
  }
}
