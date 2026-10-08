package com.measurereality

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.SizeF
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Reads the back camera's real field of view from the phone (Camera2 API),
 * so tapped points and drawn lines match the picture.
 *
 * Dart side: MethodChannel("measure_reality/camera_info").invokeMethod("getFovDeg")
 * Returns the angle in degrees as a Double, or null if the phone does not report it
 * (the app then keeps using the manual value from Settings).
 */
class CameraInfo(private val context: Context) {

    fun register(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "measure_reality/camera_info")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "getFovDeg") {
                result.success(backCameraFovDeg())
            } else {
                result.notImplemented()
            }
        }
    }

    /** Field of view along the sensor's long side (= the vertical view in portrait). */
    private fun backCameraFovDeg(): Double? {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return null
        val ids: Array<String> = try {
            manager.cameraIdList
        } catch (e: Exception) {
            return null
        }

        for (id in ids) {
            try {
                val ch: CameraCharacteristics = manager.getCameraCharacteristics(id)

                val facing: Int? = ch.get(CameraCharacteristics.LENS_FACING)
                if (facing != CameraCharacteristics.LENS_FACING_BACK) continue

                val focalLengths: FloatArray? = ch.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                val sensorSize: SizeF? = ch.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                if (focalLengths == null || focalLengths.isEmpty() || sensorSize == null) continue

                val focal: Double = focalLengths[0].toDouble()
                val longSide: Double = Math.max(sensorSize.width, sensorSize.height).toDouble()
                if (focal <= 0.0 || longSide <= 0.0) continue

                return Math.toDegrees(2.0 * Math.atan(longSide / (2.0 * focal)))
            } catch (e: Exception) {
                // this camera could not be read: try the next one
            }
        }
        return null
    }
}
