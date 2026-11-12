import UIKit
import Flutter
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let visionChannel = FlutterMethodChannel(
        name: "com.appscan.offline/vision",
        binaryMessenger: controller.binaryMessenger
      )
      visionChannel.setMethodCallHandler { [weak self] (call, result) in
        guard call.method == "detectDocumentCorners" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Thiếu đường dẫn ảnh", details: nil))
          return
        }
        self?.detectRectangleWithVision(imagePath: imagePath, result: result)
      }

      let ocrChannel = FlutterMethodChannel(
        name: "com.appscan.offline/ocr",
        binaryMessenger: controller.binaryMessenger
      )
      ocrChannel.setMethodCallHandler { [weak self] (call, result) in
        guard call.method == "recognizeVietnameseOcr" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Thiếu đường dẫn ảnh", details: nil))
          return
        }
        self?.recognizeTextWithVision(imagePath: imagePath, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Chuẩn hóa hướng ảnh EXIF về `.up` để tọa độ Vision khớp 100% với ảnh hiển thị trên Flutter.
  private func loadNormalizedCGImage(from path: String) -> CGImage? {
    guard let uiImage = UIImage(contentsOfFile: path) else { return nil }
    if uiImage.imageOrientation == .up, let cg = uiImage.cgImage {
      return cg
    }
    UIGraphicsBeginImageContextWithOptions(uiImage.size, false, 1.0)
    uiImage.draw(in: CGRect(origin: .zero, size: uiImage.size))
    let normalized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return normalized?.cgImage ?? uiImage.cgImage
  }

  /// Kiểm tra tứ giác nhận diện được không bị dính sát 4 góc viền khung ảnh (tránh nhận nhầm sàn nhà).
  private func isValidDocumentObservation(_ obs: VNRectangleObservation) -> Bool {
    let pts = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
    var borderTouchCount = 0
    for p in pts {
      if p.x <= 0.015 || p.x >= 0.985 || p.y <= 0.015 || p.y >= 0.985 {
        borderTouchCount += 1
      }
    }
    if borderTouchCount >= 3 {
      return false
    }
    // Tính diện tích Shoelace
    let x0 = Double(obs.topLeft.x), y0 = Double(1.0 - obs.topLeft.y)
    let x1 = Double(obs.topRight.x), y1 = Double(1.0 - obs.topRight.y)
    let x2 = Double(obs.bottomRight.x), y2 = Double(1.0 - obs.bottomRight.y)
    let x3 = Double(obs.bottomLeft.x), y3 = Double(1.0 - obs.bottomLeft.y)
    let area = 0.5 * abs((x0*y1 - y0*x1) + (x1*y2 - y1*x2) + (x2*y3 - y2*x3) + (x3*y0 - y3*x0))
    return area >= 0.10 && area <= 0.93
  }

  private func observationToQuad(_ obs: VNRectangleObservation) -> [String: Any] {
    return [
      "detected": true,
      "topLeft": ["x": Double(obs.topLeft.x), "y": Double(1.0 - obs.topLeft.y)],
      "topRight": ["x": Double(obs.topRight.x), "y": Double(1.0 - obs.topRight.y)],
      "bottomRight": ["x": Double(obs.bottomRight.x), "y": Double(1.0 - obs.bottomRight.y)],
      "bottomLeft": ["x": Double(obs.bottomLeft.x), "y": Double(1.0 - obs.bottomLeft.y)]
    ]
  }

  /// Sử dụng kết hợp Apple Vision Neural Engine `VNDetectDocumentSegmentationRequest` (iOS 15+)
  /// và `VNDetectRectanglesRequest` đã chuẩn hóa EXIF để nhận diện 4 góc mép giấy chuẩn xác.
  private func detectRectangleWithVision(imagePath: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self,
            let cgImage = self.loadNormalizedCGImage(from: imagePath) else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

      // Bước 1: Dùng Neural Engine Document Segmentation (chuyên biệt cho giấy tờ trên nền sàn sáng/tối)
      if #available(iOS 15.0, *) {
        let docSegRequest = VNDetectDocumentSegmentationRequest()
        do {
          try handler.perform([docSegRequest])
          if let obs = docSegRequest.results?.first,
             obs.confidence >= 0.55,
             self.isValidDocumentObservation(obs) {
            let quad = self.observationToQuad(obs)
            DispatchQueue.main.async { result(quad) }
            return
          }
        } catch {
          // Tiếp tục thử VNDetectRectanglesRequest hoặc giải thuật cạnh nâng cao
        }
      }

      // Bước 2: Dùng VNDetectRectanglesRequest với lọc nhiều ứng viên tốt nhất
      let rectRequest = VNDetectRectanglesRequest()
      rectRequest.minimumAspectRatio = 0.25
      rectRequest.maximumAspectRatio = 1.0
      rectRequest.minimumSize = 0.15
      rectRequest.quadratureTolerance = 35.0
      rectRequest.minimumConfidence = 0.55
      rectRequest.maximumObservations = 5

      do {
        try handler.perform([rectRequest])
        if let candidates = rectRequest.results {
          for obs in candidates {
            if self.isValidDocumentObservation(obs) {
              let quad = self.observationToQuad(obs)
              DispatchQueue.main.async { result(quad) }
              return
            }
          }
        }
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async { result(nil) }
      }
    }
  }

  /// Sử dụng Apple Vision Neural Engine (VNRecognizeTextRequest) hỗ trợ Tiếng Việt ("vi-VT")
  /// và chữ viết tay trực tiếp trên thiết bị (không qua máy chủ bên thứ 3).
  private func recognizeTextWithVision(imagePath: String, result: @escaping FlutterResult) {
    let fileUrl = URL(fileURLWithPath: imagePath)
    let request = VNRecognizeTextRequest { req, err in
      if let err = err {
        result(FlutterError(code: "OCR_ERROR", message: err.localizedDescription, details: nil))
        return
      }
      guard let observations = req.results as? [VNRecognizedTextObservation] else {
        result(["fullText": "", "boxes": []])
        return
      }

      var lines: [String] = []
      var boxes: [[String: Any]] = []

      for obs in observations {
        guard let topCandidate = obs.topCandidates(1).first else { continue }
        let str = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.isEmpty { continue }
        lines.append(str)

        let bbox = obs.boundingBox
        let left = Double(max(0.0, min(1.0, bbox.origin.x)))
        let top = Double(max(0.0, min(1.0, 1.0 - (bbox.origin.y + bbox.size.height))))
        let right = Double(max(left + 0.002, min(1.0, bbox.origin.x + bbox.size.width)))
        let bottom = Double(max(top + 0.002, min(1.0, 1.0 - bbox.origin.y)))

        boxes.append([
          "text": str,
          "left": left,
          "top": top,
          "right": right,
          "bottom": bottom,
          "confidence": Double(topCandidate.confidence)
        ])
      }

      let payload: [String: Any] = [
        "fullText": lines.joined(separator: "\n"),
        "boxes": boxes
      ]
      result(payload)
    }

    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = true
    }
    request.recognitionLanguages = ["vi-VT", "en-US"]

    let handler = VNImageRequestHandler(url: fileUrl, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        result(FlutterError(code: "OCR_EXEC", message: error.localizedDescription, details: nil))
      }
    }
  }
}
