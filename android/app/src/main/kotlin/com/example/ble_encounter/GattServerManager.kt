package com.example.ble_encounter

import android.bluetooth.*
import android.content.Context
import android.util.Log
import java.util.UUID

class GattServerManager(private val context: Context) {

    private val tag = "GattServer"

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("A7B3C9D2-E5F0-4A2B-8C6D-9E1F3A5B7C2D")
        val PROFILE_CHAR_UUID: UUID = UUID.fromString("A7B3C9D3-E5F0-4A2B-8C6D-9E1F3A5B7C2D")
    }

    private var gattServer: BluetoothGattServer? = null
    @Volatile private var profileBytes: ByteArray = "{}".toByteArray(Charsets.UTF_8)

    fun start(profileJson: String) {
        profileBytes = profileJson.toByteArray(Charsets.UTF_8)
        if (gattServer != null) return

        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return

        val char = BluetoothGattCharacteristic(
            PROFILE_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(char)

        try {
            gattServer = manager.openGattServer(context, serverCallback)
            gattServer?.addService(service)
            Log.i(tag, "GATT server started")
        } catch (e: SecurityException) {
            Log.e(tag, "openGattServer failed: ${e.message}")
        }
    }

    fun updateProfile(profileJson: String) {
        profileBytes = profileJson.toByteArray(Charsets.UTF_8)
    }

    fun stop() {
        try { gattServer?.close() } catch (_: Exception) {}
        gattServer = null
        Log.i(tag, "GATT server stopped")
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            Log.d(tag, "${device.address} newState=$newState")
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid != PROFILE_CHAR_UUID) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                return
            }
            val data = if (offset < profileBytes.size)
                profileBytes.copyOfRange(offset, profileBytes.size)
            else
                ByteArray(0)
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, data)
        }
    }
}
