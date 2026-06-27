import Flutter
import CoreBluetooth

class GattPlugin: NSObject {

    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.example.ble_encounter/gatt",
            binaryMessenger: messenger
        )
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startGattServer", "stopGattServer",
             "updateProfile", "showEncounterNotification":
            result(nil)
        case "readPeerProfile":
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
