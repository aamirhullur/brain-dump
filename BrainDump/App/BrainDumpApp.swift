import AppKit
import SwiftUI

@main
struct BrainDumpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appStore: AppStore
    @State private var showMemoryInletAtLaunch: Bool
    @State private var shortcutService: GlobalShortcutService?
    @State private var memoryInletController: MemoryInletController?

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
        _showMemoryInletAtLaunch = State(initialValue: Self.shouldShowMemoryInletAtLaunch())
    }

    var body: some Scene {
        WindowGroup("Brain Dump", id: "main") {
            ContentView(appStore: appStore)
                .frame(minWidth: 1180, minHeight: 680)
                .task {
                    configurePlatformServices()
                    if showMemoryInletAtLaunch {
                        showMemoryInletAtLaunch = false
                        appStore.showMemoryInlet()
                    }
                }
                .onChange(of: appStore.isMemoryInletPresented) { _, isPresented in
                    if !isPresented {
                        memoryInletController?.hide()
                    }
                }
                .onChange(of: appStore.memoryInletRequestCount) { _, _ in
                    memoryInletController?.show()
                }
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Capture Fragment") {
                    appStore.showMemoryInlet()
                }
            }
        }

        Settings {
            SettingsView(appStore: appStore)
        }
    }

    @MainActor
    private func configurePlatformServices() {
        guard shortcutService == nil else { return }
        let inletController = MemoryInletController(appStore: appStore)
        memoryInletController = inletController

        let shortcutService = GlobalShortcutService(
            onShortcut: {
                // Double-` is reserved for the future overlay feature.
            },
            onPaletteShortcut: {
                appStore.showMemoryInlet()
            },
            onScreenshotShortcut: {
                appStore.captureScreenshot()
            }
        )
        shortcutService.register()
        self.shortcutService = shortcutService
        inletController.installDormant()
    }

    private static func shouldShowMemoryInletAtLaunch() -> Bool {
        CommandLine.arguments.contains("--show-memory-inlet")
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
