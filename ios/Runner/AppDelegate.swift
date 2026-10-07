import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var backupResult: FlutterResult?
  private var exportingBackup = false
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DiligentBackup")!
    FlutterMethodChannel(name: "diligent_life/backup", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        guard self.backupResult == nil else {
          result(FlutterError(code: "busy", message: "Document picker is open", details: nil)); return
        }
        let picker: UIDocumentPickerViewController
        if call.method == "save", let args = call.arguments as? [String: Any], let path = args["path"] as? String {
          self.exportingBackup = true
          picker = UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: path)], asCopy: true)
        } else if call.method == "pick" {
          self.exportingBackup = false
          picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        } else { result(FlutterMethodNotImplemented); return }
        guard let root = self.window?.rootViewController else {
          result(FlutterError(code: "picker", message: "No view controller", details: nil)); return
        }
        self.backupResult = result
        picker.delegate = self
        picker.allowsMultipleSelection = false
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(picker, animated: true)
      }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    backupResult?(exportingBackup ? false : nil)
    backupResult = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = backupResult else { return }
    if exportingBackup { backupResult = nil; result(true); return }
    guard let source = urls.first else { backupResult = nil; result(nil); return }
    DispatchQueue.global(qos: .userInitiated).async {
      let access = source.startAccessingSecurityScopedResource()
      defer { if access { source.stopAccessingSecurityScopedResource() } }
      let target = FileManager.default.temporaryDirectory.appendingPathComponent("diligent-import-\(UUID().uuidString).diligent")
      do {
        try FileManager.default.copyItem(at: source, to: target)
        DispatchQueue.main.async { self.backupResult = nil; result(target.path) }
      } catch {
        try? FileManager.default.removeItem(at: target)
        DispatchQueue.main.async {
          self.backupResult = nil
          result(FlutterError(code: "file", message: "Cannot copy backup", details: nil))
        }
      }
    }
  }
}
