package com.example.ble_encounter

import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * BLE アドバタイズ。
 *
 * Primary advertisement: manufacturerID=0xFFFF, payload=[0xBE][peerId 16bytes]
 * Scan response:         manufacturerID=0xFEFF, payload=[0xBF][colorIdx][name UTF-8 ≤25bytes]
 *
 * connectable=true にすることでスキャン応答が有効になる。
 * スキャン側は両パケットを受け取り、GATT 接続なしでプロフィールを取得する。
 */
class BleAdvertiserChannel(private val context: Context) {

    private val tag = "BleAdvertiser"
    private val manufacturerIdPeer    = 0xFFFF
    private val manufacturerIdProfile = 0xFEFF
    private val magicPeer    = 0xBE.toByte()

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

        // Primary ad: [0xBE][peerId 16bytes] = 17 bytes
        val peerPayload = ByteArray(17)
        peerPayload[0] = magicPeer
        System.arraycopy(peerId, 0, peerPayload, 1, minOf(16, peerId.size))

        val advData = AdvertiseData.Builder()
            .addManufacturerData(manufacturerIdPeer, peerPayload)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        // Scan response: [0xBF][colorIdx][name UTF-8] ≤27 bytes
        val scanResponse = AdvertiseData.Builder()
            .addManufacturerData(manufacturerIdProfile, profilePayload)
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        val cb = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.i(tag, "Advertising started OK (connectable + scan response)")
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
