import SwiftUI
import PRReviewDeskCore

struct PrivateRepositoryConsentSheet: View {
    let request: PrivateRepositoryConsentRequest
    let onCancel: () -> Void
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(AppL10n.string("Private Repository"), systemImage: "lock.shield")
                .font(.title3)
                .fontWeight(.semibold)

            Text(request.repositoryFullName)
                .font(.headline)
                .textSelection(.enabled)

            Text(AppL10n.string("Before Codex generates an AI review draft, this app will send the following private repository context to Codex and OpenAI:"))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(request.outboundDataDescriptions, id: \.self) { description in
                    Label(AppL10n.string(description), systemImage: "arrow.up.forward.app")
                        .font(.subheadline)
                }
            }

            Text(AppL10n.string("This acknowledgement is remembered only for this repository. You can clear remembered private repository consent in Settings."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label(AppL10n.string("Cancel"), systemImage: "xmark")
                }
                .accessibilityHint(AppL10n.string("Closes this consent sheet without generating a review draft."))

                Spacer()

                Button {
                    onAcknowledge()
                } label: {
                    Label(AppL10n.string("Allow and Continue"), systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(AppL10n.string("Allows this private repository context to be used for review drafts."))
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
