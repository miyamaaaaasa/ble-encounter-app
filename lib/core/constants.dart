class Constants {
  // 0xFEAA は Android ブロックリスト(Eddystone)のため独自 128bit UUID を使用
  static const serviceUuid = 'A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D';

  /// iOS端末がトークンを渡すGATTのcharacteristic。
  /// iOSは電波にmanufacturer dataを載せられないため、サービスUUIDだけを流し、
  /// トークンは接続してこのcharacteristicから読む（ios/Runner/AppDelegate.swift）。
  static const tokenCharUuid = 'A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2E';

  /// Kotlin Platform Channel 名
  static const methodChannel = 'jp.hajimemashite.app/ble_advertiser';

  /// UI に表示する直近ログの最大件数
  static const maxDisplayLogs = 50;
}
