package com.example.ble_encounter

import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * BLE アドバタイズ。
 *
 * Primary advertisement: Service UUID A7B3C9D1-... (18 bytes)
 *   — iOS バックグラウンドが scanForPeripherals(withServices:) で検知できるよう UUID を主パケットに配置。
 *
 * Scan response: manufacturerID=0xFFFF,
 *   payload=[0xBE][peerId 16bytes][0xBF][colorIdx][name ASCII ≤8bytes]
 *   — 最大 27 bytes ペイロード → オーバーヘッド 4 bytes = 31 bytes 以内 ✓
 *   — スキャナー FULL2 ブランチ (payload[17]==0xBF) で解釈される。
 *
 * connectable=true にすることでスキャン応答が有効になる。
 */
class BleAdvertiserChannel(private val context: Context) {

    private val tag = "BleAdvertiser"
    private val manufacturerIdPeer = 0xFFFF
    private val magicPeer    = 0xBE.toByte()

    // iOS バックグラウンドスキャン対応 Service UUID
    private val serviceUuid = ParcelUuid.fromString("A7B3C9D1-E5F0-4A2B-8C6D-9E1F3A5B7C2D")

    private var advertiser: BluetoothLeAdvertiser? = null
    private var activeCallback: AdvertiseCallback? = null

    fun startAdvertise(peerId: ByteArray, profilePayload: ByteArray, result: MethodChannel.Result) {
        if (activeCallback != null) stopInternal()

        val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val btAdapter = btManager?.adapter
        if (btAdapter == null || !btAdapter.isEnabled) {
            result.error("BT_DISABLED", "Bluetooth が無効です", null)
            return
        }

        advertiser = btAdapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            result.error("NO_ADVERTISER", "BLE アドバタイズ非対応", null)
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)   // scan response のために connectable=true
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        // Primary ad: Service UUID のみ (18 bytes) — iOS バックグラウンド検知用
        val advData = AdvertiseData.Builder()
            .addServiceUuid(serviceUuid)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        // Scan response: [0xBE][peerId 16bytes][0xBF][colorIdx][name ASCII ≤8bytes]
        // profilePayload format: [0xBF][colorIdx][name ASCII ≤10][0x00][template 4bytes]
        val colorIdx = profilePayload.getOrElse(1) { 0.toByte() }
        var nameLen = 0
        for (j in 2 until profilePayload.size) {
            if (profilePayload[j] == 0x00.toByte()) break
            if (nameLen >= 8) break
            nameLen++
        }

        val peerProfilePayload = ByteArray(19 + nameLen)
        peerProfilePayload[0] = magicPeer
        System.arraycopy(peerId, 0, peerProfilePayload, 1, minOf(16, peerId.size))
        peerProfilePayload[17] = 0xBF.toByte()
        peerProfilePayload[18] = colorIdx
        if (nameLen > 0) {
            System.arraycopy(profilePayload, 2, peerProfilePayload, 19, nameLen)
        }

        val scanResponse = AdvertiseData.Builder()
            .addManufacturerData(manufacturerIdPeer, peerProfilePayload)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        val cb = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.i(tag, "Advertising OK (UUID primary ${peerProfilePayload.size}B scan response)")
            }
            override fun onStartFailure(errorCode: Int) {
                Log.e(tag, "Advertising FAILED errorCode=$errorCode")
            }
        }
        activeCallback = cb

        try {
            advertiser!!.startAdvertising(settings, advData, scanResponse, cb)
            result.success(null)
        } catch (e: SecurityException) {
            activeCallback = null
            result.error("PERMISSION", e.message, null)
        } catch (e: Exception) {
            activeCallback = null
            result.error("ADVERTISE_ERROR", e.message, null)
        }
    }

    fun stopAdvertise(result: MethodChannel.Result) {
        stopInternal()
        result.success(null)
    }

    private fun stopInternal() {
        try {
            activeCallback?.let { advertiser?.stopAdvertising(it) }
        } catch (e: Exception) {
            Log.w(tag, "stopAdvertising failed: ${e.message}")
        } finally {
            activeCallback = null
        }
    }
}
