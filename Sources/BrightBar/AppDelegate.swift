import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var brightnessManager: BrightnessManager!
    private var keyInterceptor: MediaKeyInterceptor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        brightnessManager = BrightnessManager()
        statusBarController = StatusBarController(brightnessManager: brightnessManager)
        keyInterceptor = MediaKeyInterceptor(brightnessManager: brightnessManager)
        keyInterceptor.start()

        NSLog("[BrightBar] Launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyInterceptor.stop()
        NSLog("[BrightBar] Terminated")
    }
}
