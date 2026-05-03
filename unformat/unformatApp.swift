import AppKit
import SwiftUI

@main
struct UnformatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenuContent(appDelegate: appDelegate)
        } label: {
            if let menuBarIconImage {
                Image(nsImage: menuBarIconImage)
            } else {
                Text("U")
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIconImage: NSImage? {
        guard let image = NSImage(named: "MenuBarIcon") else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
