import SwiftUI

struct FragmentDetailView: View {
    let fragment: Fragment
    let fragmentStore: FragmentStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(fragment.displayTitle)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        Text(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(fragment.status.rawValue.capitalized, systemImage: "circle.dotted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Captured Text")
                        .font(.headline)
                    Text(fragment.userNote ?? "")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 16) {
                    LabeledContent("Source", value: fragment.sourceType.rawValue.uppercased())
                    LabeledContent("Jobs", value: "\(fragmentStore.jobCount(for: fragment.id))")
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(fragment.displayTitle)
    }
}
