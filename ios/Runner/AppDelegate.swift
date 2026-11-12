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

  /// Sử dụng Apple Vision Framework (VNDetectRectanglesRequest) trên iOS 16+
  /// để nhận diện 4 góc tài liệu tự động bằng AI trên thiết bị.
  private func detectRectangleWithVision(imagePath: String, result: @escaping FlutterResult) {
    let fileUrl = URL(fileURLWithPath: imagePath)
    let request = VNDetectRectanglesRequest { req, err in
      if let err = err {
        result(FlutterError(code: "VISION_ERROR", message: err.localizedDescription, details: nil))
        return
      }
      guard let obs = (req.results as? [VNRectangleObservation])?.first else {
        result(nil)
        return
      }
      let quad: [String: Any] = [
        "detected": true,
        "topLeft": ["x": Double(obs.topLeft.x), "y": Double(1.0 - obs.topLeft.y)],
        "topRight": ["x": Double(obs.topRight.x), "y": Double(1.0 - obs.topRight.y)],
        "bottomRight": ["x": Double(obs.bottomRight.x), "y": Double(1.0 - obs.bottomRight.y)],
        "bottomLeft": ["x": Double(obs.bottomLeft.x), "y": Double(1.0 - obs.bottomLeft.y)]
      ]
      result(quad)
    }
    request.minimumAspectRatio = 0.2
    request.maximumAspectRatio = 1.0
    request.minimumSize = 0.12
    request.maximumObservations = 1

    let handler = VNImageRequestHandler(url: fileUrl, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        result(FlutterError(code: "VISION_EXEC", message: error.localizedDescription, details: nil))
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
