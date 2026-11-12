package com.appscan.offline

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * MainActivity cung cấp 2 cầu nối AI chạy trực tiếp trên thiết bị (không qua máy chủ bên thứ 3):
 * 1. `com.appscan.offline/vision`: Nhận diện mép giấy & 4 góc tài liệu tự động.
 * 2. `com.appscan.offline/ocr`: Nhận dạng chữ Tiếng Việt có dấu & chữ viết tay bằng mô hình
 *    Neural LSTM Tesseract 5 (`vie.traineddata` đóng gói sẵn trong ứng dụng).
 */
class MainActivity : FlutterFragmentActivity() {
    private val visionChannelName = "com.appscan.offline/vision"
    private val ocrChannelName = "com.appscan.offline/ocr"
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, visionChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectDocumentCorners" -> {
                        val imagePath = call.argument<String>("imagePath")
                        if (imagePath.isNullOrEmpty() || !File(imagePath).exists()) {
                            result.error("INVALID_PATH", "Đường dẫn ảnh không hợp lệ", null)
                            return@setMethodCallHandler
                        }
                        executor.execute {
                            try {
                                val quad = detectCornersNative(imagePath)
                                mainHandler.post { result.success(quad) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("VISION_ERR", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ocrChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognizeVietnameseOcr" -> {
                        val imagePath = call.argument<String>("imagePath")
                        val enhanceHandwriting = call.argument<Boolean>("enhanceHandwriting") ?: true
                        if (imagePath.isNullOrEmpty() || !File(imagePath).exists()) {
                            result.error("INVALID_PATH", "Đường dẫn ảnh không hợp lệ", null)
                            return@setMethodCallHandler
                        }
                        executor.execute {
                            try {
                                val ocrMap = runTesseractVietnameseOcr(imagePath, enhanceHandwriting)
                                mainHandler.post { result.success(ocrMap) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("OCR_ERR", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Sao chép mô hình `vie.traineddata` từ Flutter assets ra thư mục riêng của ứng dụng
     * trong lần chạy đầu tiên để TessBaseAPI đọc trực tiếp ngoại tuyến.
     */
    private fun ensureTessDataReady(): String {
        val baseDir = File(filesDir, "tesseract")
        val tessDataDir = File(baseDir, "tessdata")
        if (!tessDataDir.exists()) {
            tessDataDir.mkdirs()
        }
        val targetFile = File(tessDataDir, "vie.traineddata")
        if (!targetFile.exists() || targetFile.length() < 100_000L) {
            val loader = FlutterInjector.instance().flutterLoader()
            val assetKey = loader.getLookupKeyForAsset("assets/tessdata/vie.traineddata")
            assets.open(assetKey).use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
        }
        return baseDir.absolutePath
    }

    /**
     * Chạy nhận dạng Tiếng Việt (chữ in & chữ viết tay) bằng mô hình Neural LSTM của Tesseract 5.
     */
    private fun runTesseractVietnameseOcr(
        imagePath: String,
        enhanceHandwriting: Boolean
    ): Map<String, Any> {
        val dataPath = ensureTessDataReady()
        val rawBitmap = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalStateException("Không thể đọc Bitmap từ $imagePath")

        val processedBitmap = if (enhanceHandwriting) {
            enhanceBitmapForVietnameseAndHandwriting(rawBitmap)
        } else {
            rawBitmap
        }

        val tess = TessBaseAPI()
        try {
            val initialized = tess.init(
                dataPath,
                "vie",
                TessBaseAPI.OEM_LSTM_ONLY
            )
            if (!initialized) {
                throw IllegalStateException("Không thể khởi tạo mô hình OCR Tiếng Việt (vie)")
            }

            tess.pageSegMode = TessBaseAPI.PageSegMode.PSM_AUTO
            tess.setImage(processedBitmap)

            val fullText = tess.utF8Text?.trim() ?: ""
            val imgW = max(1, processedBitmap.width).toDouble()
            val imgH = max(1, processedBitmap.height).toDouble()

            val boxes = mutableListOf<Map<String, Any>>()
            val words = tess.words
            if (words != null) {
                for (rect in words.boxRects) {
                    val left = (rect.left / imgW).coerceIn(0.0, 1.0)
                    val top = (rect.top / imgH).coerceIn(0.0, 1.0)
                    val right = (rect.right / imgW).coerceIn(left + 0.002, 1.0)
                    val bottom = (rect.bottom / imgH).coerceIn(top + 0.002, 1.0)
                    boxes.add(
                        mapOf(
                            "text" to "",
                            "left" to left,
                            "top" to top,
                            "right" to right,
                            "bottom" to bottom,
                            "confidence" to (tess.meanConfidence() / 100.0).coerceIn(0.0, 1.0)
                        )
                    )
                }
            }

            return mapOf(
                "fullText" to fullText,
                "boxes" to boxes,
                "confidence" to (tess.meanConfidence() / 100.0).coerceIn(0.0, 1.0)
            )
        } finally {
            tess.recycle()
            if (processedBitmap !== rawBitmap) {
                processedBitmap.recycle()
            }
            rawBitmap.recycle()
        }
    }

    /**
     * Tiền xử lý ảnh thông minh giúp làm rõ dấu thanh Tiếng Việt (sắc, huyền, hỏi, ngã, nặng)
     * và nét bút chữ viết tay trước khi đưa vào mạng LSTM.
     */
    private fun enhanceBitmapForVietnameseAndHandwriting(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        var minLuma = 255
        var maxLuma = 0
        val luma = IntArray(w * h)

        for (i in pixels.indices) {
            val c = pixels[i]
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            val y = (r * 77 + g * 150 + b * 29) shr 8
            luma[i] = y
            if (y < minLuma) minLuma = y
            if (y > maxLuma) maxLuma = y
        }

        val range = max(1, maxLuma - minLuma)
        for (i in pixels.indices) {
            val stretched = ((luma[i] - minLuma) * 255 / range).coerceIn(0, 255)
            // Làm đậm nét mực mảnh (chữ viết tay và dấu tiếng Việt) và làm sạch nền giấy
            val enhanced = when {
                stretched > 200 -> 255
                stretched < 145 -> (stretched * 0.65).toInt().coerceIn(0, 255)
                else -> stretched
            }
            pixels[i] = (0xFF shl 24) or (enhanced shl 16) or (enhanced shl 8) or enhanced
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(pixels, 0, w, 0, 0, w, h)
        return out
    }

    private fun detectCornersNative(imagePath: String): Map<String, Any> {
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

        var edgePixels = 0
        val marginX = max(2, (w * 0.015).toInt())
        val marginY = max(2, (h * 0.015).toInt())

        for (y in marginY until (h - marginY)) {
            for (x in marginX until (w - marginX)) {
                val idx = y * w + x
                if (luma[idx] >= threshold) {
                    val gx = abs(luma[idx + 1] - luma[idx - 1])
                    val gy = abs(luma[idx + w] - luma[idx - w])
                    val isEdge = (gx + gy) > 20 ||
                        luma[idx - 1] < threshold ||
                        luma[idx + 1] < threshold ||
                        luma[idx - w] < threshold ||
                        luma[idx + w] < threshold
                    if (isEdge) {
                        edgePixels++
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
            "detected" to (edgePixels > 24),
            "topLeft" to mapOf("x" to tl.first, "y" to tl.second),
            "topRight" to mapOf("x" to tr.first, "y" to tr.second),
            "bottomRight" to mapOf("x" to br.first, "y" to br.second),
            "bottomLeft" to mapOf("x" to bl.first, "y" to bl.second)
        )
    }
}
