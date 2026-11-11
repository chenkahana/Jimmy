import SwiftUI

/// The assistant chat screen — reached from Settings ("Assistant"). Builds its view model once
/// the environment's `AppModel` is available; shows a plain unavailable message (with Apple's
/// reason) instead of the chat when `SystemLanguageModel.default.availability` isn't `.available`.
struct AssistantView: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: AssistantViewModel?
    @State private var draftText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        content
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel == nil {
                    viewModel = Self.makeViewModel(appModel: appModel)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            switch viewModel.availability {
            case .available:
                chat(viewModel)
            case .unavailable(let reason):
                unavailableView(reason: reason)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func unavailableView(reason: String) -> some View {
        ContentUnavailableView {
            Label("Assistant Unavailable", systemImage: "sparkles")
        } description: {
            Text(reason)
        }
    }

    private func chat(_ viewModel: AssistantViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.messages.isEmpty {
                            Text("Ask me to play, queue, search, subscribe, or set a sleep timer.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                        }
                        ForEach(viewModel.messages) { message in
                            AssistantMessageRow(message: message)
                                .id(message.id)
                        }
                        if let pending = viewModel.confirmations.pending {
                            AssistantConfirmationRow(
                                action: pending,
                                onConfirm: { Task { await viewModel.confirmPending() } },
                                onCancel: { viewModel.confirmations.dismissPending() }
                            )
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.last?.text) { _, _ in
                    guard let lastID = viewModel.messages.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Jimmy…", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit { send(using: viewModel) }

                if viewModel.isResponding {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Button {
                        send(using: viewModel)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
    }

    private func send(using viewModel: AssistantViewModel) {
        guard !viewModel.isResponding else { return }
        let text = draftText
        draftText = ""
        Task { await viewModel.send(text) }
    }

    @MainActor
    private static func makeViewModel(appModel: AppModel) -> AssistantViewModel {
        let availability = AssistantAvailability.current()
        guard case .available = availability else {
            return AssistantViewModel(
                actions: appModel,
                availability: availability,
                session: nil,
                confirmations: AssistantConfirmationBroker()
            )
        }
        let confirmations = AssistantConfirmationBroker()
        let tools = AssistantFactory.makeTools(actions: appModel, confirmations: confirmations)
        let session = FoundationModelsAssistantSession(tools: tools, instructions: AssistantFactory.instructions)
        return AssistantViewModel(actions: appModel, availability: availability, session: session, confirmations: confirmations)
    }
}

private struct AssistantMessageRow: View {
    let message: AssistantMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 32) }
            Text(message.text.isEmpty ? " " : message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }
}

private struct AssistantConfirmationRow: View {
    let action: AssistantPendingAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.confirmationPrompt)
                .font(.subheadline.weight(.medium))
            HStack {
                Button("Confirm", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        AssistantView()
    }
}
