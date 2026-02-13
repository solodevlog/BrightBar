import AppKit
import DonateKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!
    private var brightnessManager: BrightnessManager!
    private var keyInterceptor: MediaKeyInterceptor!
    let donate = DonateKit(appName: "BrightBar")

    func applicationDidFinishLaunching(_ notification: Notification) {
        brightnessManager = BrightnessManager()
        statusBarController = StatusBarController(brightnessManager: brightnessManager, donate: donate)
        keyInterceptor = MediaKeyInterceptor(brightnessManager: brightnessManager)
        keyInterceptor.start()

        // Check for gentle one-time donate nudge after 14 days
        donate.checkNudge()

        NSLog("[BrightBar] Launched successfully")
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyInterceptor.stop()
        NSLog("[BrightBar] Terminated")
    }
}
