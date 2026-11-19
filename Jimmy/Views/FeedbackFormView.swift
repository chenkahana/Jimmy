import SwiftUI

/// Simple form for submitting feedback or bug reports.
struct FeedbackFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Your Name")) {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }

                Section(header: Text("Suggestion or Bug")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                if let statusMessage = statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button("Submit") {
                        submitFeedback()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              notes.trimmingCharacters(in: .whitespaces).isEmpty ||
                              isSubmitting)
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func submitFeedback() {
        isSubmitting = true
        statusMessage = nil
        FeedbackService.shared.submit(name: name, notes: notes) { success, message in
            isSubmitting = false
            if success {
                // Close as soon as the send completes; VoiceOver hears the outcome the screen no longer shows.
                AccessibilityService.shared.announce("Feedback sent")
                dismiss()
            } else {
                if let message = message, !message.isEmpty {
                    statusMessage = "Error: \(message)"
                } else {
                    statusMessage = "Submission failed. Please try again."
                }
            }
        }
    }
}
