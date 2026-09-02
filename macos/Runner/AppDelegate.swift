import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Paths from application(_:openFile[s]:) that arrived before the Flutter
  /// engine was ready to receive them. Flushed on didFinishLaunching.
  private var pendingFiles: [String] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if !pendingFiles.isEmpty {
      sendFiles(pendingFiles)
      pendingFiles.removeAll()
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    forwardFiles([filename])
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    forwardFiles(filenames)
    sender.reply(toOpenOrPrint: .success)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func forwardFiles(_ files: [String]) {
    guard let window = mainFlutterWindow else { return }
    if window.contentViewController is FlutterViewController {
      sendFiles(files)
    } else {
      pendingFiles.append(contentsOf: files)
    }
  }

  /// Delivers each file to the Dart side's FileOpenService method channel.
  private func sendFiles(_ files: [String]) {
    guard
      let window = mainFlutterWindow,
      let controller = window.contentViewController as? FlutterViewController
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "solutionscribe/file_open",
      binaryMessenger: controller.engine.binaryMessenger)
    for path in files {
      channel.invokeMethod("openFile", arguments: path)
    }
  }
}