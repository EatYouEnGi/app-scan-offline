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
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Sử dụng Apple Vision Framework (VNDetectRectanglesRequest) trên iOS 16+
  /// để nhận diện nhanh 4 góc tài liệu ngoại tuyến.
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
      // Chuyển hệ trục tọa độ gốc dưới-trái của Vision sang gốc trên-trái [0..1] của Flutter.
      let quad: [String: [String: Double]] = [
        "topLeft": ["x": Double(obs.topLeft.x), "y": Double(1.0 - obs.topLeft.y)],
        "topRight": ["x": Double(obs.topRight.x), "y": Double(1.0 - obs.topRight.y)],
        "bottomRight": ["x": Double(obs.bottomRight.x), "y": Double(1.0 - obs.bottomRight.y)],
        "bottomLeft": ["x": Double(obs.bottomLeft.x), "y": Double(1.0 - obs.bottomLeft.y)]
      ]
      result(quad)
    }
    request.minimumAspectRatio = 0.25
    request.maximumAspectRatio = 1.0
    request.minimumSize = 0.15
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
}

