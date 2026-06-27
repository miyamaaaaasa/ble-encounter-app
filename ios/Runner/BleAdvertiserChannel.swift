import Flutter
import CoreBluetooth

class BleAdvertiserChannel: NSObject, CBPeripheralManagerDelegate {

    private let methodChannel: FlutterMethodChannel
    private var peripheralManager: CBPeripheralManager?
    private var pendingResult: FlutterResult?
    private var pendingPeerId: Data?
    private var pendingProfile: Data?

    static let restoreIdentifier = "com.example.ble_encounter.peripheral"
    static let serviceUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.example.ble_encounter/ble_advertiser",
            binaryMessenger: messenger
        )
        super.init()
        methodChannel.setMethodCallHandler(handleMethodCall)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertise":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "args required", details: nil))
                return
            }
            let peerId = (args["peerId"] as! FlutterStandardTypedData).data
            let profile = (args["profilePayload"] as! FlutterStandardTypedData).data
            startAdvertise(peerId: peerId, profile: profile, result: result)

        case "stopAdvertise":
            stopAdvertise()
            result(nil)

        case "startForegroundService", "stopForegroundService":
            // iOS にフォアグラウンドサービスは存在しない。no-op。
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startAdvertise(peerId: Data, profile: Data, result: @escaping FlutterResult) {
        stopAdvertise()
        pendingPeerId = peerId
        pendingProfile = profile
        pendingResult = result

        let options: [String: Any] = [
            CBPeripheralManagerOptionRestoreIdentifierKey: BleAdvertiserChannel.restoreIdentifier
        ]
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: options)
    }

    private func stopAdvertise() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
        pendingPeerId = nil
        pendingProfile = nil
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            if peripheral.state == .poweredOff {
                pendingResult?(FlutterError(code: "BT_OFF", message: "Bluetooth is off", details: nil))
                pendingResult = nil
            }
            return
        }
        guard let profile = pendingProfile else { return }

        // localName: profilePayload の name フィールドから取得
        // フォーマット: [0xBF][colorIdx][prefecture][name ASCII ≤7B]
        let nameStart = 3
        let nameData = profile.count > nameStart
            ? profile.subdata(in: nameStart..<min(profile.count, nameStart + 7))
            : Data()
        let nameStr = String(data: nameData, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BleAdvertiserChannel.serviceUUID],
            CBAdvertisementDataLocalNameKey: nameStr.isEmpty ? "hello" : nameStr,
        ]

        peripheral.startAdvertising(advertisementData)
        pendingResult?(nil)
        pendingResult = nil
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("[BleAdv] startAdvertising error: \(error)")
        } else {
            print("[BleAdv] advertising started")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        print("[BleAdv] willRestoreState")
    }
}
