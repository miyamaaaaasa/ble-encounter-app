package com.example.ble_encounter

import android.bluetooth.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

class GattClientManager(private val context: Context) {

    private val tag = "GattClient"
    private val handler = Handler(Looper.getMainLooper())

    fun readProfile(macAddress: String, callback: (String?) -> Unit) {
        val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val device = try {
            btManager?.adapter?.getRemoteDevice(macAddress)
        } catch (e: Exception) {
            Log.w(tag, "Invalid MAC: $macAddress")
            callback(null)
            return
        } ?: run { callback(null); return }

        val done = AtomicBoolean(false)
        var gatt: BluetoothGatt? = null

        fun finish(result: String?) {
            if (done.compareAndSet(false, true)) {
                handler.post { callback(result) }
                try { gatt?.close() } catch (_: Exception) {}
            }
        }

        handler.postDelayed({ finish(null) }, 10_000)

        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                gatt = g
                when {
                    newState == BluetoothProfile.STATE_CONNECTED -> {
                        Log.d(tag, "Connected to $macAddress, requesting MTU")
                        try { g.requestMtu(512) } catch (e: SecurityException) { finish(null) }
                    }
                    status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.w(tag, "Connection failed: status=$status")
                        finish(null)
                    }
                }
            }

            override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
                Log.d(tag, "MTU=$mtu, discovering services")
                try { g.discoverServices() } catch (e: SecurityException) { finish(null) }
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                val char = g.getService(GattServerManager.SERVICE_UUID)
                    ?.getCharacteristic(GattServerManager.PROFILE_CHAR_UUID)
                if (char == null) {
                    Log.w(tag, "Profile service not found on $macAddress")
                    try { g.disconnect() } catch (_: Exception) {}
                    finish(null)
                    return
                }
                try { g.readCharacteristic(char) } catch (e: SecurityException) { finish(null) }
            }

            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(
                g: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                val value = try { characteristic.value } catch (_: Exception) { null }
                handleRead(g, value, status)
            }

            override fun onCharacteristicRead(
                g: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int
            ) {
                handleRead(g, value, status)
            }

            private fun handleRead(g: BluetoothGatt, value: ByteArray?, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS && value != null) {
                    val json = value.toString(Charsets.UTF_8)
                    Log.i(tag, "Profile from $macAddress: $json")
                    finish(json)
                } else {
                    finish(null)
                }
                try { g.disconnect() } catch (_: Exception) {}
            }
        }

        try {
            Log.i(tag, "connectGatt -> $macAddress")
            gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: SecurityException) {
            Log.e(tag, "SecurityException: ${e.message}")
            finish(null)
        }
    }
}
