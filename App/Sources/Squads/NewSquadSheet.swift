import API
import Creature
import DesignSystem
import Model
import Paywall
import Social
import SwiftUI

/// A new squad: your Lockling with the squad's egg, a name, and Create. Hitting the free plan's
/// one squad opens the paywall (SPEC.md §2, paywall moment 2).
struct NewSquadSheet: View {
    let squads: SquadsStore
    let plus: PlusStore
    let avatar: AvatarCode
    let focusesField: Bool
    /// Runs with the new squad once the sheet has closed: the Friends screen opens it, where the
    /// invite is.
    let onCreated: (Squad) -> Void

    @State private var name: String
    @State private var isCreating = false
    @State private var problem: String? = nil
    @State private var showsPaywall = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private static let maxLength = LiveActivityLimits.maxSquadNameLength

    init(
        squads: SquadsStore,
        plus: PlusStore,
        avatar: AvatarCode,
        name: String = "",
        focusesField: Bool = true,
        onCreated: @escaping (Squad) -> Void
    ) {
        self.squads = squads
        self.plus = plus
        self.avatar = avatar
        self.focusesField = focusesField
        self.onCreated = onCreated
        _name = State(initialValue: name)
    }

    private var verdict: Moderation.Verdict {
        Moderation.checkName(name, maxLength: Self.maxLength)
    }

    private var canCreate: Bool {
        verdict == .ok && !isCreating
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: LKSpacing.l) {
                    Spacer(minLength: LKSpacing.s)
                    SquadHatchery(avatar: avatar, size: min(240, max(160, proxy.size.height * 0.36)))
                    Spacer(minLength: LKSpacing.s)
                    nameField
                    Text(message ?? " ")
                        .font(LKFont.footnote)
                        .foregroundStyle(LKColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: LKSpacing.l)
                    createButton
                }
                .padding(.horizontal, LKSpacing.xl)
                .padding(.bottom, LKSpacing.l)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .navigationTitle("New squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .interactiveDismissDisabled(isCreating)
        .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: avatar)
        .task {
            guard focusesField else { return }
            try? await Task.sleep(for: .milliseconds(450))
            fieldFocused = true
        }
    }

    private var nameField: some View {
        TextField("Squad name", text: $name)
            .font(.title2.weight(.semibold))
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .focused($fieldFocused)
            .onSubmit(create)
            .padding(.vertical, LKSpacing.l)
            .padding(.horizontal, LKSpacing.m)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .disabled(isCreating)
            .onChange(of: name) {
                problem = nil
            }
    }

    private var createButton: some View {
        Button(action: create) {
            ZStack {
                Text("Create")
                    .opacity(isCreating ? 0 : 1)
                if isCreating {
                    ProgressView()
                }
            }
            .font(LKFont.headline)
            .frame(maxWidth: .infinity)
        }
        .lkProminentButton()
        .controlSize(.large)
        .disabled(!canCreate)
    }

    /// Why the name won't do, once there's something to say. Empty says nothing: the disabled
    /// button is enough.
    private var message: String? {
        if let problem {
            return problem
        }
        guard !Moderation.trimmed(name).isEmpty else { return nil }
        switch verdict {
        case .ok: return nil
        case .invalid: return "Up to \(Self.maxLength) characters"
        case .notAllowed: return "Please pick another name"
        }
    }

    private func create() {
        guard canCreate else { return }
        isCreating = true
        problem = nil
        let chosen = Moderation.trimmed(name)
        Task {
            defer { isCreating = false }
            do {
                let squad = try await squads.create(name: chosen)
                fieldFocused = false
                dismiss()
                onCreated(squad)
            } catch is CancellationError {
                return
            } catch {
                if error.hitsFreeLimit {
                    fieldFocused = false
                    showsPaywall = true
                } else {
                    problem = error.squadMessage
                }
            }
        }
    }
}
