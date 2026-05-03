import ServiceManagement

/// Manages whether the app is registered to launch automatically at login.
struct LoginManager {
    /// The current login-item registration state for the main app.
    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers the main app to launch automatically when the user logs in.
    func enableLaunchAtLogin() throws {
        try SMAppService.mainApp.register()
    }

    /// Removes the main app from the user's login items.
    func disableLaunchAtLogin() throws {
        try SMAppService.mainApp.unregister()
    }

    /// Updates login-item registration to match the requested state.
    func setLaunchAtLogin(desiredState: Bool) throws {
        guard isLaunchAtLoginEnabled != desiredState else {
            return
        }

        if desiredState {
            try enableLaunchAtLogin()
        } else {
            try disableLaunchAtLogin()
        }
    }
}
