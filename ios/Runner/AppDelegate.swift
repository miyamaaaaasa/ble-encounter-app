import CoreBluetooth
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BleAdvertiserPlugin") {
      BleAdvertiserPlugin.register(with: registrar)
    }
  }
}

// MARK: - BLE アドバタイズ（iOS版）
//
// Android版 BleAdvertiserChannel.kt に相当する。Dart側の BleAdvertiser が
// 同じチャンネル名で呼び出す。
//
// iOSの制約: CoreBluetooth はアドバタイズに manufacturer data を載せられない
// （流せるのはサービスUUIDとローカル名だけ）。Android版はトークンを
// manufacturer data で流しているが、iOSではそれができない。
//
// そこで「サービスUUIDだけを流し、トークンはGATTのcharacteristicで渡す」。
// 受信側（lib/services/scanner.dart）は、サービスUUIDはあるのにトークンが
// 載っていない電波を見つけたら接続してこのcharacteristicを読む。
//
// 渡すのは24時間で入れ替わる使い捨てトークンのみで、Android版が電波で
// 流している内容と同じ。プロフィール等は一切渡さない（匿名性の維持）。
final class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {
  // lib/core/constants.dart と一致させること
  static let serviceUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")
  static let tokenCharUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2E")

  private var manager: CBPeripheralManager?
  private var token = Data()
  private var wantAdvertising = false
  private var serviceAdded = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "jp.hajimemashite.app/ble_advertiser",
      binaryMessenger: registrar.messenger())
    let instance = BleAdvertiserPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startAdvertise":
      if let args = call.arguments as? [String: Any],
        let peer = args["peerId"] as? FlutterStandardTypedData
      {
        token = peer.data
      }
      wantAdvertising = true
      ensureManager()
      applyState()
      result(nil)
    case "stopAdvertise":
      wantAdvertising = false
      manager?.stopAdvertising()
      result(nil)
    case "startForegroundService", "stopForegroundService":
      // iOSにフォアグラウンドサービスは無い。背面動作は Info.plist の
      // UIBackgroundModes(bluetooth-peripheral) で宣言済み。
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ensureManager() {
    if manager == nil {
      manager = CBPeripheralManager(delegate: self, queue: nil)
    }
  }

  /// Bluetoothの状態に合わせてサービス登録・広告開始/停止を行う。
  /// サービス追加は非同期（didAdd で完了）なので、完了後にもう一度呼ばれる。
  private func applyState() {
    guard let m = manager, m.state == .poweredOn else { return }
    if !serviceAdded {
      // value を nil にすると読み取りのたびに didReceiveRead が呼ばれ、
      // 24時間ごとに入れ替わる最新トークンを返せる。
      let characteristic = CBMutableCharacteristic(
        type: Self.tokenCharUUID, properties: [.read], value: nil, permissions: [.readable])
      let service = CBMutableService(type: Self.serviceUUID, primary: true)
      service.characteristics = [characteristic]
      m.add(service)
      serviceAdded = true
      return
    }
    if wantAdvertising {
      if !m.isAdvertising {
        // 背面ではAppleの独自領域に移るため、同じUUIDを指定してスキャンする
        // iOS端末からしか見えない（Androidからは見えない。サーバーの相互記録で補う）。
        m.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
      }
    } else {
      m.stopAdvertising()
    }
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state == .poweredOn {
      applyState()
    } else {
      // BTオフ等でサービスは破棄されるので、次にオンになったら登録し直す
      serviceAdded = false
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?
  ) {
    if let error = error {
      NSLog("[BleAdv] add service error: \(error)")
      serviceAdded = false
      return
    }
    applyState()
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if let error = error {
      NSLog("[BleAdv] start advertising error: \(error)")
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest)
  {
    guard request.characteristic.uuid == Self.tokenCharUUID else {
      peripheral.respond(to: request, withResult: .attributeNotFound)
      return
    }
    guard request.offset <= token.count else {
      peripheral.respond(to: request, withResult: .invalidOffset)
      return
    }
    request.value = token.subdata(in: request.offset..<token.count)
    peripheral.respond(to: request, withResult: .success)
  }
}
