import SwiftUI

struct CapturePaletteView: View {
    let fragmentStore: FragmentStore
    let onClose: () -> Void

    @State private var text = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Capture", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            TextField("Paste a thought, note, or URL", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...3)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Label(URLDetector.url(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) == nil ? "Text" : "URL", systemImage: URLDetector.url(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) == nil ? "text.alignleft" : "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Cancel") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 680)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }

    private func save() {
        do {
            try fragmentStore.capture(rawInput: text)
            text = ""
            errorMessage = nil
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
