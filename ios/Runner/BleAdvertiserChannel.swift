import Flutter
import CoreBluetooth

class BleAdvertiserChannel: NSObject, CBPeripheralManagerDelegate {

    private let methodChannel: FlutterMethodChannel
    private var peripheralManager: CBPeripheralManager?
    private var pendingResult: FlutterResult?
    private var pendingPeerId: Data?
    private var pendingProfile: Data?
    private var isAdvertising = false

    static let restoreIdentifier = "com.example.ble_encounter.peripheral"
    static let serviceUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.example.ble_encounter/ble_advertiser",
            binaryMessenger: messenger
        )
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertise":
            guard let args = call.arguments as? [String: Any],
                  let peerTyped = args["peerId"] as? FlutterStandardTypedData,
                  let profileTyped = args["profilePayload"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "peerId and profilePayload required", details: nil))
                return
            }
            startAdvertise(peerId: peerTyped.data, profile: profileTyped.data, result: result)

        case "stopAdvertise":
            stopAdvertise()
            result(nil)

        case "startForegroundService", "stopForegroundService":
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
            CBPeripheralManagerOptionRestoreIdentifierKey: BleAdvertiserChannel.restoreIdentifier,
            CBPeripheralManagerOptionShowPowerAlertKey: false
        ]
        // nil queue = main thread; Flutter result callbacks must run on main thread
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: options)
    }

    private func stopAdvertise() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
        }
        peripheralManager?.delegate = nil
        peripheralManager = nil
        pendingPeerId = nil
        pendingProfile = nil
        // Don't nil out pendingResult here to avoid leaking unanswered calls
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            guard let profile = pendingProfile else {
                pendingResult?(nil)
                pendingResult = nil
                return
            }
            startAdvertisingWithProfile(profile, on: peripheral)

        case .poweredOff, .unauthorized, .unsupported:
            let code = peripheral.state == .poweredOff ? "BT_OFF" :
                       peripheral.state == .unauthorized ? "BT_UNAUTHORIZED" : "BT_UNSUPPORTED"
            pendingResult?(FlutterError(code: code, message: "Bluetooth state: \(peripheral.state.rawValue)", details: nil))
            pendingResult = nil

        case .resetting, .unknown:
            break

        @unknown default:
            break
        }
    }

    private func startAdvertisingWithProfile(_ profile: Data, on peripheral: CBPeripheralManager) {
        let nameStart = 3
        let nameData = profile.count > nameStart
            ? profile.subdata(in: nameStart..<min(profile.count, nameStart + 7))
            : Data()
        let nameStr = String(data: nameData, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters) ?? ""

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BleAdvertiserChannel.serviceUUID],
            CBAdvertisementDataLocalNameKey: nameStr.isEmpty ? "hello" : String(nameStr.prefix(8)),
        ]
        peripheral.startAdvertising(advertisementData)
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("[BleAdv] startAdvertising error: \(error)")
            pendingResult?(FlutterError(code: "ADV_FAILED", message: error.localizedDescription, details: nil))
        } else {
            isAdvertising = true
            pendingResult?(nil)
        }
        pendingResult = nil
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        print("[BleAdv] willRestoreState")
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            for service in services {
                peripheral.add(service)
            }
        }
    }
}
