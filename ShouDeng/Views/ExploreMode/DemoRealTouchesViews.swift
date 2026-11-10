import SwiftUI
import UIKit

// MARK: - Explore Mode: real touches
//
// Opt-ins that make the demo feel like the person's own, all kept on the phone:
//   • DemoLocationPrompt — explains, then asks for one real fix (weather / own pin)
//   • DemoRealLocationRow — "Show me where I really am" under Mom's map
//   • DemoAddMemberView — "Add a family member" joins the sample family, then
//     "Ready to invite your real family?" leaves for the real sign-up

enum DemoLocationPrompt: String, Identifiable {
    case weather, map
    var id: String { rawValue }
    var titleKey: String { "explore.location.\(rawValue).title" }
    var bodyKey: String { "explore.location.\(rawValue).body" }
}

/// Explain first; only after "Continue" does iOS ask for permission and the phone take one fix.
private struct DemoLocationConsent: ViewModifier {
    @Binding var prompt: DemoLocationPrompt?
    @ObservedObject private var explore = ExploreModeController.shared
    @ObservedObject private var lang = LanguageManager.shared
    @State private var failure: DemoLocateError?
    @State private var showFailure = false

    func body(content: Content) -> some View {
        content
            .alert(lang.localized(prompt?.titleKey ?? "explore.location.map.title"),
                   isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                   presenting: prompt) { which in
                Button(lang.localized("explore.location.continue")) {
                    Task {
                        let error = which == .weather
                            ? await explore.useMyLocationForWeather()
                            : await explore.showRealLocation()
                        if let error, explore.isActive {
                            failure = error
                            showFailure = true
                        }
                    }
                }
                Button(lang.localized("explore.location.notNow"), role: .cancel) {}
            } message: { which in
                Text(lang.localized(which.bodyKey))
            }
            .alert(lang.localized(failure == .denied ? "explore.location.denied.title" : "explore.location.failed.title"),
                   isPresented: $showFailure) {
                if failure == .denied {
                    Button(lang.localized("explore.location.openSettings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button(lang.localized("common.ok"), role: .cancel) {}
            } message: {
                Text(lang.localized(failure == .denied ? "explore.location.denied.body" : "explore.location.failed.body"))
            }
    }
}

extension View {
    func demoLocationConsent(_ prompt: Binding<DemoLocationPrompt?>) -> some View {
        modifier(DemoLocationConsent(prompt: prompt))
    }
}

// MARK: - "Show me where I really am"

struct DemoRealLocationRow: View {
    @ObservedObject private var explore = ExploreModeController.shared
    @ObservedObject private var lang = LanguageManager.shared
    @State private var prompt: DemoLocationPrompt?
    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)

    var body: some View {
        let t = DemoText(language: lang.current)
        HStack(spacing: 8) {
            Image(systemName: explore.realLocation == nil ? "location.circle" : "location.fill")
                .foregroundStyle(navy)
            if explore.realLocation == nil {
                Button(lang.localized("explore.realLocation.show")) { prompt = .map }
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(navy)
                    .accessibilityIdentifier("explore.realLocation.show")
                Spacer(minLength: 0)
            } else {
                Text(lang.localized("explore.realLocation.on"))
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(Color.appInk)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(String(format: lang.localized("explore.realLocation.off"), t.chengdu)) { explore.stopRealLocation() }
                    .font(.scaled(size: 12, weight: .semibold))
                    .foregroundStyle(navy)
                    .lineLimit(1)
                    .accessibilityIdentifier("explore.realLocation.off")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(navy.opacity(0.06)))
        .demoLocationConsent($prompt)
    }
}

// MARK: - "Add a family member" in the demo

struct DemoAddMemberView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var explore = ExploreModeController.shared
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    /// The side the new person gets unless the person picks the other one
    let defaultRole: UserRole

    @State private var name = ""
    @State private var role: UserRole?
    @State private var lastAdded: DemoStore.AddedMember?
    @FocusState private var nameFocused: Bool

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    private var pickedRole: UserRole { role ?? defaultRole }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFull: Bool { explore.addedMembers.count >= DemoStore.maxAddedMembers }

    var body: some View {
        let t = DemoText(language: lang.current)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.scaled(size: 36))
                            .foregroundStyle(safe)
                        Text(lang.localized("explore.member.title"))
                            .font(.scaled(size: 20, weight: .bold))
                        Text(lang.localized("explore.member.subtitle"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    form(t)

                    if let lastAdded { addedCard(lastAdded, t) }

                    if !explore.addedMembers.isEmpty { bridgeCard }

                    Label(lang.localized("explore.member.nothingSent"), systemImage: "lock.shield")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.localized("common.close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func form(_ t: DemoText) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(lang.localized("explore.member.namePlaceholder"), text: $name)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit(add)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                .accessibilityIdentifier("explore.member.name")

            Picker(lang.localized("explore.member.role"), selection: Binding(get: { pickedRole }, set: { role = $0 })) {
                Text(lang.localized("signup.role.guardian")).tag(UserRole.guardian)
                Text(lang.localized("signup.role.protected")).tag(UserRole.protected_)
            }
            .pickerStyle(.segmented)

            Text(pickedRole == .guardian
                 ? String(format: lang.localized("explore.member.role.guardianHint"), t.momName)
                 : String(format: lang.localized("explore.member.role.protectedHint"), t.sarahName))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            Button(action: add) {
                Text(lang.localized("explore.member.add"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(trimmed.isEmpty || isFull ? Color.gray.opacity(0.5) : safe))
            }
            .disabled(trimmed.isEmpty || isFull)
            .accessibilityIdentifier("explore.member.add")
        }
    }

    private func addedCard(_ member: DemoStore.AddedMember, _ t: DemoText) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(format: lang.localized("explore.member.added"), member.name), systemImage: "checkmark.circle.fill")
                .font(.scaled(size: 15, weight: .semibold))
                .foregroundStyle(safe)
            Text(member.role == .guardian
                 ? String(format: lang.localized("explore.member.added.guardian"), member.name, t.momName)
                 : String(format: lang.localized("explore.member.added.protected"), member.name, t.sarahName, t.chengdu))
                .font(.scaled(size: 13))
                .foregroundStyle(Color.appInk)
                .fixedSize(horizontal: false, vertical: true)
            // On Sarah's phone: the new person can send a practice SOS she receives
            if member.role == .protected_ && explore.role == .sarah {
                Button {
                    dismiss()
                    let id = member.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { explore.practiceSOS(from: id) }
                } label: {
                    Label(String(format: lang.localized("explore.member.practiceSOS"), member.name), systemImage: "sos")
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 196/255, green: 69/255, blue: 60/255))
                }
                .accessibilityIdentifier("explore.member.practiceSOS")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(safe.opacity(0.08)))
    }

    /// "Ready to invite your real family?" → leaves the demo for the real sign-up;
    /// the wizard's invite step will have these names ready.
    private var bridgeCard: some View {
        let names = explore.addedMembers.map(\.name)
        let list = ListFormatter.localizedString(byJoining: names)
        return VStack(alignment: .leading, spacing: 10) {
            Text(lang.localized("explore.bridge.title"))
                .font(.scaled(size: 17, weight: .bold))
                .foregroundStyle(cream)
            Text(String(format: lang.localized("explore.bridge.body"), list))
                .font(.scaled(size: 13))
                .foregroundStyle(cream.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { explore.inviteRealFamily() }
            } label: {
                Text(lang.localized("explore.checklist.setup"))
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(cream))
            }
            .accessibilityIdentifier("explore.bridge.setup")
            Button(lang.localized("explore.bridge.later")) { dismiss() }
                .font(.scaled(size: 13, weight: .medium))
                .foregroundStyle(cream.opacity(0.85))
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(navy))
    }

    private func add() {
        guard !trimmed.isEmpty, !isFull else { return }
        if let member = explore.addMember(name: trimmed, role: pickedRole) {
            withAnimation { lastAdded = member }
            name = ""
            nameFocused = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
