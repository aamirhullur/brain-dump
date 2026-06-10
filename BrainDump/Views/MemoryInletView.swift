import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MemoryInletView: View {
    let model: MemoryInletModel
    let fragmentStore: FragmentStore
    var collapsedSize = CGSize(width: 184, height: 36)
    var isNotchBacked = false
    let onClose: () -> Void
    let onPreferredSizeChange: (CGSize) -> Void
    var onScreenshotCapture: () -> Void = {}

    @State private var inputText = ""
    @State private var feedback = "Ready"
    @State private var lastSavedTitle: String?
    @State private var errorMessage: String?
    @State private var isHovering = false
    @State private var clipboardText: String?
    @State private var savedConfirmation: String?
    @FocusState private var isInputFocused: Bool

    private var processingCount: Int {
        fragmentStore.processingCount
    }

    private let progressSize = CGSize(width: 360, height: 118)
    private let awakeSize = CGSize(width: 520, height: 118)
    private let captureSize = CGSize(width: 560, height: 154)

    var body: some View {
        inletBody
            .frame(width: preferredSize.width, height: preferredSize.height)
            .background {
                MemoryInletShape(topRadius: isFlushWithNotch ? 0 : 6)
                    .fill(.black)
                    .shadow(
                        color: .black.opacity(isFlushWithNotch ? 0 : (model.state == .dormant ? 0.25 : 0.42)),
                        radius: model.state == .dormant ? 5 : 14,
                        y: 8
                    )
            }
            .overlay {
                if !isFlushWithNotch {
                    MemoryInletShape()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
            }
            .preferredColorScheme(.dark)
            .animation(.interactiveSpring(response: 0.36, dampingFraction: 0.86), value: model.state)
            .animation(.smooth(duration: 0.18), value: isHovering)
            .onAppear {
                detectClipboard()
                updatePreferredSize()
                focusIfNeeded()
            }
            .onChange(of: model.state) { _, _ in
                detectClipboard()
                updatePreferredSize()
                focusIfNeeded()
            }
            .onChange(of: fragmentStore.processingCount) { _, newCount in
                if newCount == 0 {
                    feedback = "Ready for review"
                }
            }
            .onExitCommand {
                collapse()
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering, model.state == .dormant, processingCount > 0 {
                    model.state = .progress
                } else if !hovering, model.state == .progress {
                    model.collapse()
                }
            }
            .onTapGesture {
                if model.state == .dormant || model.state == .progress {
                    model.wake()
                }
            }
            .onDrop(of: [.fileURL, .image, .png, .tiff], isTargeted: Binding(
                get: { false },
                set: { targeted in
                    if targeted, model.state == .dormant || model.state == .progress {
                        model.wake()
                    }
                }
            )) { providers in
                handleImageDrop(providers)
            }
    }

    @ViewBuilder
    private var inletBody: some View {
        switch model.state {
        case .dormant:
            dormantBody
        case .awake:
            awakeBody
        case .capture(let intent):
            captureBody(intent)
        case .progress:
            progressBody
        }
    }

    private var isFlushWithNotch: Bool {
        isNotchBacked && model.state == .dormant
    }

    @ViewBuilder
    private var dormantBody: some View {
        if isNotchBacked {
            // Anything centered here would sit behind the camera housing.
            VStack {
                Spacer()
                Capsule()
                    .fill(processingCount > 0 ? Color.blue : (savedConfirmation != nil ? Color.green : Color.clear))
                    .frame(width: 28, height: 3)
                    .padding(.bottom, 2)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: dormantSystemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dormantIconColor)
                Text(dormantTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 5)
        }
    }

    private var awakeBody: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Capture intent", systemImage: "sparkle.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                if let clipboardText {
                    Label(clipboardLabel(for: clipboardText), systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.06), in: Capsule())
                }
                Button {
                    collapse()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                ForEach(CaptureIntent.allCases) { intent in
                    Button {
                        select(intent)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: intent.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                            Text(intent.title)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.06))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func captureBody(_ intent: CaptureIntent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(intent.prompt, systemImage: intent.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button("Back") {
                    model.wake()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                Button {
                    collapse()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if intent == .screenshot {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Select a screen region to capture.")
                            .font(.callout.weight(.medium))
                        Text("Or press \(ScreenshotShortcutDetector.shortcutDescription) anywhere to save instantly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Capture") {
                        model.collapse()
                        onScreenshotCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else {
                TextField(intent.prompt, text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .onSubmit {
                        save(intent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Collapse happens immediately after capture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save") {
                        save(intent)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var progressBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Background memory", systemImage: "circle.dotted")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Spacer()
                Button("Open app") {
                    onClose()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            HStack(spacing: 10) {
                StatusDot()
                VStack(alignment: .leading, spacing: 3) {
                    Text(lastSavedTitle ?? "No recent capture")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(processingCount > 0 ? "\(processingCount)" : "0")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.07), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var preferredSize: CGSize {
        switch model.state {
        case .dormant:
            return collapsedSize
        case .awake:
            return awakeSize
        case .capture:
            return captureSize
        case .progress:
            return progressSize
        }
    }

    private var dormantSystemImage: String {
        if savedConfirmation != nil {
            return "checkmark.circle.fill"
        }
        return processingCount > 0 ? "circle.dotted" : "brain.head.profile"
    }

    private var dormantIconColor: Color {
        if savedConfirmation != nil {
            return .green
        }
        return processingCount > 0 ? .blue : .secondary
    }

    private var dormantTitle: String {
        if let savedConfirmation {
            return savedConfirmation
        }
        return processingCount > 0 ? "\(processingCount) processing" : "Brain Dump"
    }

    private func select(_ intent: CaptureIntent) {
        errorMessage = nil
        if intent == .paste {
            if let image = ImageIngest.clipboardImage() {
                saveImages([image], sourceType: .image)
                return
            }
            if let clipboard = clipboardText {
                inputText = clipboard
            }
        }
        model.state = .capture(intent)
    }

    private func save(_ intent: CaptureIntent) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try fragmentStore.capture(rawInput: trimmed)
            lastSavedTitle = title(for: trimmed, intent: intent)
            feedback = "Saved, queued for interpretation"
            savedConfirmation = "Saved"
            inputText = ""
            errorMessage = nil
            model.collapse()
            clearSavedConfirmationSoon()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            let images = await ImageIngest.images(from: providers)
            guard !images.isEmpty else {
                errorMessage = "Only image drops are supported right now."
                feedback = "Drop was not saved"
                model.wake()
                return
            }
            saveImages(images, sourceType: .image)
        }
        return true
    }

    private func saveImages(_ images: [IngestableImage], sourceType: SourceType) {
        do {
            for image in images {
                try fragmentStore.captureImage(
                    image.data,
                    sourceType: sourceType,
                    originalFilename: image.originalFilename,
                    mimeType: image.mimeType,
                    fileExtension: image.fileExtension
                )
            }
            lastSavedTitle = images.first?.originalFilename ?? (images.count == 1 ? "Image" : "\(images.count) images")
            feedback = "Saved, queued for interpretation"
            savedConfirmation = "Saved"
            errorMessage = nil
            model.collapse()
            clearSavedConfirmationSoon()
        } catch {
            errorMessage = error.localizedDescription
            model.wake()
        }
    }

    private func collapse() {
        errorMessage = nil
        model.collapse()
    }

    private func updatePreferredSize() {
        onPreferredSizeChange(preferredSize)
    }

    private func focusIfNeeded() {
        guard case .capture(let intent) = model.state, intent != .screenshot else { return }
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    private func detectClipboard() {
        let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        clipboardText = clipboard?.isEmpty == false ? clipboard : nil
    }

    private func clipboardLabel(for value: String) -> String {
        if ImageIngest.clipboardImage() != nil {
            return "Image ready"
        }
        if URLDetector.url(from: value) != nil {
            return "URL ready"
        }
        return "Clipboard ready"
    }

    private func clearSavedConfirmationSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.15))
            savedConfirmation = nil
        }
    }

    private func title(for value: String, intent: CaptureIntent) -> String {
        if intent == .url, let url = URLDetector.url(from: value), let host = url.host {
            return host
        }
        return String(value.prefix(48))
    }
}

private struct StatusDot: View {
    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .stroke(.blue.opacity(0.32), lineWidth: 5)
            }
    }
}

private struct MemoryInletShape: Shape {
    var topRadius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let bottomRadius: CGFloat = 18
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}
