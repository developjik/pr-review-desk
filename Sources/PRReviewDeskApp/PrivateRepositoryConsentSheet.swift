import SwiftUI
import PRReviewDeskCore

struct PrivateRepositoryConsentSheet: View {
    let request: PrivateRepositoryConsentRequest
    let onCancel: () -> Void
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Private Repository", systemImage: "lock.shield")
                .font(.title3)
                .fontWeight(.semibold)

            Text(request.repositoryFullName)
                .font(.headline)
                .textSelection(.enabled)

            Text("Before Codex generates a review, this app will send the following private repository context to Codex and OpenAI:")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(request.outboundDataDescriptions, id: \.self) { description in
                    Label(description, systemImage: "arrow.up.forward.app")
                        .font(.subheadline)
                }
            }

            Text("This acknowledgement is remembered only for this repository. You can clear remembered private repository consent in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }

                Spacer()

                Button {
                    onAcknowledge()
                } label: {
                    Label("Acknowledge", systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
