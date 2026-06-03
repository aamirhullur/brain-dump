import SwiftUI

@main
struct BrainDumpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appStore: AppStore
    @State private var showPaletteAtLaunch: Bool
    @State private var shortcutService: GlobalShortcutService?
    @State private var capturePaletteController: CapturePaletteController?

    init() {
        let store = AppStore()
        if let smokeCapture = Self.smokeCaptureArgument() {
            do {
                try store.fragmentStore.capture(rawInput: smokeCapture)
                Foundation.exit(0)
            } catch {
                fputs("Smoke capture failed: \(error.localizedDescription)\n", stderr)
                Foundation.exit(1)
            }
        }
        _appStore = State(initialValue: store)
        _showPaletteAtLaunch = State(initialValue: CommandLine.arguments.contains("--show-palette"))
    }

    var body: some Scene {
        WindowGroup("Brain Dump", id: "main") {
            ContentView(appStore: appStore)
                .frame(minWidth: 980, minHeight: 600)
                .task {
                    configurePlatformServices()
                    if showPaletteAtLaunch {
                        showPaletteAtLaunch = false
                        appStore.showCapturePalette()
                    }
                }
                .onChange(of: appStore.isCapturePalettePresented) { _, isPresented in
                    if isPresented {
                        capturePaletteController?.show()
                    } else {
                        capturePaletteController?.hide()
                    }
                }
        }
        .defaultSize(width: 1080, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Capture Fragment") {
                    appStore.showCapturePalette()
                }
                .keyboardShortcut(.space, modifiers: [.option])
            }
        }

        Settings {
            SettingsView(appStore: appStore)
        }
    }

    @MainActor
    private func configurePlatformServices() {
        guard shortcutService == nil else { return }
        let paletteController = CapturePaletteController(appStore: appStore)
        capturePaletteController = paletteController

        let shortcutService = GlobalShortcutService {
            appStore.showCapturePalette()
        }
        shortcutService.register()
        self.shortcutService = shortcutService
    }

    private static func smokeCaptureArgument() -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--smoke-capture") else {
            return nil
        }
        let valueIndex = CommandLine.arguments.index(after: index)
        guard valueIndex < CommandLine.arguments.endIndex else {
            return ""
        }
        return CommandLine.arguments[valueIndex]
    }
}
