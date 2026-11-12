package com.appscan.offline

import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.max
import kotlin.math.min

/**
 * MainActivity kế thừa FlutterFragmentActivity (cần thiết cho local_auth sinh trắc học Android)
 * và cung cấp cầu nối native `com.appscan.offline/vision` để nhận diện nhanh 4 góc tài liệu.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.appscan.offline/vision"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectDocumentCorners" -> {
                        val imagePath = call.argument<String>("imagePath")
                        if (imagePath.isNullOrEmpty() || !File(imagePath).exists()) {
                            result.error("INVALID_PATH", "Đường dẫn ảnh không hợp lệ", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val quad = detectCornersNative(imagePath)
                            result.success(quad)
                        } catch (e: Exception) {
                            result.error("VISION_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun detectCornersNative(imagePath: String): Map<String, Map<String, Double>> {
        val opts = BitmapFactory.Options().apply {
            inSampleSize = 4
        }
        val bmp = BitmapFactory.decodeFile(imagePath, opts)
            ?: throw IllegalStateException("Không thể giải mã Bitmap")

        val w = bmp.width
        val h = bmp.height
        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        bmp.recycle()

        val luma = IntArray(w * h)
        val hist = IntArray(256)
        for (i in pixels.indices) {
            val c = pixels[i]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            val y = (r * 77 + g * 150 + b * 29) shr 8
            luma[i] = y
            hist[y]++
        }

        // Tính ngưỡng Otsu tách nền giấy sáng.
        var sum = 0.0
        for (t in 0..255) sum += t * hist[t]
        var sumB = 0.0
        var wB = 0
        var varMax = 0.0
        var threshold = 140
        val total = w * h

        for (t in 0..255) {
            wB += hist[t]
            if (wB == 0) continue
            val wF = total - wB
            if (wF == 0) break
            sumB += (t * hist[t]).toDouble()
            val mB = sumB / wB
            val mF = (sum - sumB) / wF
            val between = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF)
            if (between > varMax) {
                varMax = between
                threshold = t
            }
        }
        threshold = min(220, max(70, threshold))

        var minSum = Double.MAX_VALUE
        var maxSum = -Double.MAX_VALUE
        var minDiff = Double.MAX_VALUE
        var maxDiff = -Double.MAX_VALUE

        var tl = Pair(0.06, 0.06)
        var tr = Pair(0.94, 0.06)
        var br = Pair(0.94, 0.94)
        var bl = Pair(0.06, 0.94)

        val marginX = max(2, (w * 0.015).toInt())
        val marginY = max(2, (h * 0.015).toInt())

        for (y in marginY until (h - marginY)) {
            for (x in marginX until (w - marginX)) {
                val idx = y * w + x
                if (luma[idx] >= threshold) {
                    val isEdge = luma[idx - 1] < threshold ||
                        luma[idx + 1] < threshold ||
                        luma[idx - w] < threshold ||
                        luma[idx + w] < threshold
                    if (isEdge) {
                        val nx = x.toDouble() / (w - 1).toDouble()
                        val ny = y.toDouble() / (h - 1).toDouble()
                        val s = nx + ny
                        val d = nx - ny
                        if (s < minSum) {
                            minSum = s
                            tl = Pair(nx, ny)
                        }
                        if (s > maxSum) {
                            maxSum = s
                            br = Pair(nx, ny)
                        }
                        if (d > maxDiff) {
                            maxDiff = d
                            tr = Pair(nx, ny)
                        }
                        if (d < minDiff) {
                            minDiff = d
                            bl = Pair(nx, ny)
                        }
                    }
                }
            }
        }

        return mapOf(
            "topLeft" to mapOf("x" to tl.first, "y" to tl.second),
            "topRight" to mapOf("x" to tr.first, "y" to tr.second),
            "bottomRight" to mapOf("x" to br.first, "y" to br.second),
            "bottomLeft" to mapOf("x" to bl.first, "y" to bl.second)
        )
    }
}

