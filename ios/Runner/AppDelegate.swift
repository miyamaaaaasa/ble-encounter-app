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
//
// 【ロック中の動作】Dart側の間欠サイクル（15秒ON/2分）はタイマー駆動のため、
// 画面ロックでアプリが停止すると一緒に止まる。そこで背面に入ったらネイティブ側が
// 引き継ぎ、①広告を出しっぱなしにし ②サービスUUID指定で常時スキャンする。
// 拾ったトークンは端末内に貯め、復帰時にDartが drainBackgroundTokens で回収して
// 通常の保留トークンと同じ経路（サーバー照合）に流す。CoreBluetoothのイベント駆動
// なので、iOSがBluetooth処理のためにアプリを起こしてくれる限り動き続ける。
final class BleAdvertiserPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate,
  CBCentralManagerDelegate, CBPeripheralDelegate
{
  // lib/core/constants.dart と一致させること
  static let serviceUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")
  static let tokenCharUUID = CBUUID(string: "A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2E")

  private var manager: CBPeripheralManager?
  private var token = Data()
  private var wantAdvertising = false
  private var serviceAdded = false

  // 背面スキャン用
  private var central: CBCentralManager?
  private var inBackground = false
  private var connecting: CBPeripheral?
  // peripheral.identifier → 最後に読めた時刻（同じ相手に何度も接続しない）
  private var lastRead: [UUID: Date] = [:]
  private let readInterval: TimeInterval = 10 * 60
  private static let storeKey = "bg_tokens_v1"
  private static let maxStored = 300

  override init() {
    super.init()
    let nc = NotificationCenter.default
    nc.addObserver(
      self, selector: #selector(didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    nc.addObserver(
      self, selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
  }

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
    case "drainBackgroundTokens":
      // [[token(hex), 検出時刻(ms)]] を返して消す
      let list = UserDefaults.standard.array(forKey: Self.storeKey) ?? []
      UserDefaults.standard.removeObject(forKey: Self.storeKey)
      result(list)
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
    // 背面ではDartのサイクルが止まるので、停止指示に関わらず出し続ける
    if wantAdvertising || (inBackground && !token.isEmpty) {
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

  // MARK: 背面の引き継ぎ

  @objc private func didEnterBackground() {
    inBackground = true
    ensureManager()
    applyState()
    if central == nil {
      central = CBCentralManager(delegate: self, queue: nil)  // poweredOnで開始
    } else {
      startBackgroundScan()
    }
  }

  @objc private func willEnterForeground() {
    inBackground = false
    central?.stopScan()
    if let p = connecting { central?.cancelPeripheralConnection(p) }
    connecting = nil
    applyState()  // Dartのサイクルの状態（wantAdvertising）に戻す
  }

  private func startBackgroundScan() {
    guard inBackground, let c = central, c.state == .poweredOn else { return }
    // 背面スキャンはサービスUUID指定が必須。重複通知はiOSがまとめるため、
    // 接続が終わるたびに張り直して新しく来た相手も拾えるようにする。
    c.stopScan()
    c.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
  }

  func centralManagerDidUpdateState(_ c: CBCentralManager) {
    if c.state == .poweredOn { startBackgroundScan() }
  }

  func centralManager(
    _ c: CBCentralManager, didDiscover p: CBPeripheral,
    advertisementData ad: [String: Any], rssi: NSNumber
  ) {
    guard inBackground else { return }
    // Android端末は電波にトークンを載せている（0xFFFF, 0xBE, 16バイト）
    if let md = ad[CBAdvertisementDataManufacturerDataKey] as? Data, md.count >= 19,
      md[md.startIndex] == 0xFF, md[md.startIndex + 1] == 0xFF,
      md[md.startIndex + 2] == 0xBE
    {
      store(md.subdata(in: (md.startIndex + 3)..<(md.startIndex + 19)))
      return
    }
    // iOS端末（またはスキャン応答が来ていないAndroid）はGATTで読む。同時に1台だけ
    if connecting != nil { return }
    if let t = lastRead[p.identifier], Date().timeIntervalSince(t) < readInterval { return }
    connecting = p
    p.delegate = self
    c.connect(p, options: nil)
  }

  func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
    p.discoverServices([Self.serviceUUID])
  }

  func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
    finish(p)
  }

  func centralManager(
    _ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?
  ) {
    if connecting == p { connecting = nil }
    startBackgroundScan()
  }

  func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
    guard let svc = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
      return finish(p)
    }
    p.discoverCharacteristics([Self.tokenCharUUID], for: svc)
  }

  func peripheral(
    _ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?
  ) {
    guard let ch = s.characteristics?.first(where: { $0.uuid == Self.tokenCharUUID }) else {
      return finish(p)
    }
    p.readValue(for: ch)
  }

  func peripheral(
    _ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?
  ) {
    if let v = ch.value, v.count >= 16 {
      store(v.prefix(16))
      lastRead[p.identifier] = Date()
    }
    finish(p)
  }

  private func finish(_ p: CBPeripheral) {
    central?.cancelPeripheralConnection(p)
    if connecting == p { connecting = nil }
    startBackgroundScan()
  }

  /// 拾ったトークンを端末内に保存する。自分自身のものと、直近の重複は除く。
  private func store(_ raw: Data) {
    let bytes = Data(raw)
    if bytes == token.prefix(16) { return }
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    var list = UserDefaults.standard.array(forKey: Self.storeKey) as? [[Any]] ?? []
    if list.contains(where: { ($0.first as? String) == hex }) { return }
    list.append([hex, Int(Date().timeIntervalSince1970 * 1000)])
    if list.count > Self.maxStored { list.removeFirst(list.count - Self.maxStored) }
    UserDefaults.standard.set(list, forKey: Self.storeKey)
    NSLog("[BleBg] token captured \(hex.suffix(4))")
  }
}
