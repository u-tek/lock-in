import API
import DesignSystem
import Social
import SwiftUI

extension ReportReason {
    var title: String {
        switch self {
        case .name: "Their name"
        case .spam: "Spam"
        case .harassment: "Bullying or harassment"
        case .other: "Something else"
        }
    }
}

/// Report someone to the Lockin team (SPEC.md §7): pick a reason, send.
struct ReportSheet: View {
    @ObservedObject var friends: FriendsStore
    let person: Friend

    @State private var reason: ReportReason? = nil
    @State private var isSending = false
    @State private var failure: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ReportReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(LKColor.textPrimary)
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark")
                                        .font(LKFont.body.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(reason == option ? .isSelected : [])
                    }
                } header: {
                    HStack(spacing: LKSpacing.s) {
                        FriendAvatar(avatar: person.avatar, size: 28)
                        Text(person.name)
                    }
                    .textCase(nil)
                } footer: {
                    Text("They won't be told who reported them.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send", action: send)
                            .disabled(reason == nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .errorAlert("Couldn't send", message: $failure)
    }

    private func send() {
        guard let reason, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await friends.report(userId: person.id, reason: reason)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// Settings › Blocked people: everyone you've blocked, each with Unblock.
struct BlockedScreen: View {
    @ObservedObject var friends: FriendsStore

    @State private var hasLoaded = false
    @State private var failure: String? = nil

    var body: some View {
        List {
            ForEach(friends.blocked) { person in
                HStack {
                    FriendRow(friend: person)
                    Spacer(minLength: LKSpacing.s)
                    Button("Unblock") {
                        unblock(person)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if hasLoaded, friends.blocked.isEmpty {
                ContentUnavailableView("No one blocked", systemImage: "hand.raised")
            }
        }
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await friends.refreshBlocked()
            hasLoaded = true
        }
        .errorAlert("Couldn't unblock", message: $failure)
    }

    private func unblock(_ person: Friend) {
        Task {
            do {
                try await friends.unblock(person)
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
