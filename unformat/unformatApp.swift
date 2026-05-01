//
//  unformatApp.swift
//  unformat
//
//  Created by David Haukeness on 5/1/26.
//

import AppKit

@main
struct UnformatMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
