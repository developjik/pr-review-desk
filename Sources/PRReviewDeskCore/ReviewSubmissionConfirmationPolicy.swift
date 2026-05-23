import Foundation

public enum ReviewSubmissionConfirmationPolicy {
    public static func requiresConfirmation(for event: ReviewEvent) -> Bool {
        switch event {
        case .comment, .approve, .requestChanges:
            return true
        }
    }
}
