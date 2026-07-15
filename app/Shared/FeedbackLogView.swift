import SwiftUI

/// Full-screen reader for the latest Codex response. The compact status views
/// intentionally stay glanceable; this view keeps the complete text available.
struct FeedbackLogView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Latest response")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            ScrollView {
                Text(text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .padding()
    }
}
