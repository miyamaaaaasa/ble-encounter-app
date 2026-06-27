import Flutter
import CoreBluetooth

class GattPlugin: NSObject {
    init(messenger: FlutterBinaryMessenger) {
        super.init()
        let channel = FlutterMethodChannel(
            name: "com.example.ble_encounter/gatt",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { call, result in
            // TODO: 本実装。現在はスタブ。
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
}
