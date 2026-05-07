import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let headsetClient = SonyBluetoothClient()
    private var menuController: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = MenuController(client: headsetClient)
        headsetClient.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        headsetClient.disconnect()
    }
}
