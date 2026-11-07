import SwiftUI
import QuickLook

// MARK: - Report for police (docs/police-incident-report.md)
//
// Pick who (a guardian with several people), why, which period and what to include;
// the server gathers and hashes the data, the phone draws the PDF / maps / GPX / CSV,
// and the files go out through the share sheet. The verify code lets police check
// any file. The person is told when a guardian makes one.

/// The row that opens the sheet (Records, the SOS alert screen).
struct IncidentReportButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    /// nil = choose (guardian); the person's own id for their own report
    var personId: String? = nil
    /// Start from the last 24 h ending now (an SOS in progress)
    var compact = false
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.scaled(size: 18))
                    .foregroundStyle(Color(red: 196/255, green: 69/255, blue: 60/255))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.localized("report.entry"))
                        .font(.scaled(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !compact {
                        Text(lang.localized("report.entry.subtitle"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("report.entry")
        .sheet(isPresented: $showSheet) {
            IncidentReportView(initialPersonId: personId)
                .environmentObject(coordinator)
        }
    }
}

struct IncidentReportView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lang = LanguageManager.shared

    let initialPersonId: String?

    enum WindowPreset: String, CaseIterable, Identifiable {
        case h6, h24, h72, d7, custom
        var id: String { rawValue }
        var hours: Double? { switch self { case .h6: 6; case .h24: 24; case .h72: 72; case .d7: 168; case .custom: nil } }
    }

    @State private var personId = ""
    @State private var purpose: IncidentReportPurpose = .missingPerson
    @State private var preset: WindowPreset = .h24
    @State private var customStart = Date().addingTimeInterval(-24 * 3600)
    @State private var customEnd = Date()
    @State private var caseNumber = ""
    @State private var sections = Set(IncidentReportSection.allCases)
    @State private var step: IncidentReportBuilder.Step?
    @State private var package: IncidentReportBuilder.Package?
    @State private var errorText: String?
    @State private var previewURL: URL?

    private var people: [(id: String, name: String)] {
        if coordinator.userRole == .guardian {
            return coordinator.protectedPersons.map { ($0.user.id, $0.user.displayName) }
        }
        let me = coordinator.currentUser
        return [(me?.id ?? coordinator.authManager.currentUserId ?? "", me?.displayName ?? "")]
    }

    private var window: (Date, Date) {
        if let h = preset.hours { return (Date().addingTimeInterval(-h * 3600), Date()) }
        return (min(customStart, customEnd), max(customStart, customEnd))
    }

    private var windowError: String? {
        let (s, e) = window
        if e.timeIntervalSince(s) > 7 * 24 * 3600 + 60 { return lang.localized("report.window.tooLong") }
        if e.timeIntervalSince(s) < 15 * 60 { return lang.localized("report.window.tooShort") }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let package {
                    done(package)
                } else {
                    form
                }
            }
            .navigationTitle(lang.localized("report.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.localized(package == nil ? "common.cancel" : "common.done")) { dismiss() }
                }
            }
            .quickLookPreview($previewURL)
        }
        .onAppear {
            if personId.isEmpty { personId = initialPersonId ?? people.first?.id ?? "" }
        }
        .interactiveDismissDisabled(step != nil)
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                Text(lang.localized("report.sheet.intro"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
            }
            if people.count > 1 {
                Section {
                    Picker(lang.localized("report.field.person"), selection: $personId) {
                        ForEach(people, id: \.id) { p in Text(p.name).tag(p.id) }
                    }
                }
            }
            Section {
                Picker(lang.localized("report.field.purpose"), selection: $purpose) {
                    ForEach(IncidentReportPurpose.allCases) { p in Text(lang.localized(p.titleKey)).tag(p) }
                }
                TextField(lang.localized("report.field.caseNumber.placeholder"), text: $caseNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section {
                Picker(lang.localized("report.field.window"), selection: $preset) {
                    ForEach(WindowPreset.allCases) { p in Text(lang.localized("report.window.\(p.rawValue)")).tag(p) }
                }
                if preset == .custom {
                    DatePicker(lang.localized("report.window.from"), selection: $customStart, in: ...Date())
                    DatePicker(lang.localized("report.window.to"), selection: $customEnd, in: ...Date())
                }
                if let windowError {
                    Text(windowError).font(.scaled(size: 12)).foregroundStyle(.red)
                }
            } footer: {
                Text(lang.localized("report.window.footer"))
            }
            Section {
                ForEach(IncidentReportSection.allCases) { s in
                    Toggle(lang.localized(s.titleKey), isOn: Binding(
                        get: { sections.contains(s) },
                        set: { on in if on { sections.insert(s) } else { sections.remove(s) } }
                    ))
                }
            } header: {
                Text(lang.localized("report.sections.title"))
            } footer: {
                Text(lang.localized(coordinator.userRole == .guardian ? "report.privacy.guardian" : "report.privacy.self"))
            }
            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Spacer()
                        if let step {
                            ProgressView().padding(.trailing, 6)
                            Text(lang.localized("report.step.\(step)"))
                        } else {
                            Text(lang.localized("report.create")).fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(step != nil || windowError != nil || personId.isEmpty || sections.isEmpty)
                .accessibilityIdentifier("report.create")
                if let errorText {
                    Text(errorText).font(.scaled(size: 12)).foregroundStyle(.red)
                }
            } footer: {
                Text(lang.localized("report.disclaimer"))
            }
        }
    }

    private func create() async {
        errorText = nil
        let (start, end) = window
        let request = IncidentReportRequest(
            personId: personId,
            windowStart: start,
            windowEnd: end,
            purpose: purpose.rawValue,
            caseNumber: caseNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : caseNumber,
            sections: IncidentReportSection.allCases.filter(sections.contains).map(\.rawValue)
        )
        step = .gathering
        do {
            let builder = IncidentReportBuilder(api: coordinator.apiClient)
            package = try await builder.build(request) { s in Task { @MainActor in step = s } }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? lang.localized("report.error.generic")
        }
        step = nil
    }

    // MARK: Done

    private func done(_ p: IncidentReportBuilder.Package) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(lang.localized("report.done.title"), systemImage: "checkmark.seal.fill")
                        .font(.scaled(size: 17, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(String(format: lang.localized("report.done.summary"),
                                p.data.summary.counts.points, p.data.summary.counts.sos, p.data.summary.counts.falls, p.data.gaps.count))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                HStack {
                    Text(lang.localized("report.verifyCode"))
                    Spacer()
                    Text(p.verifyCode)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
                HStack {
                    Text(lang.localized("report.field.reportId"))
                    Spacer()
                    Text(p.reportId).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                }
            } footer: {
                Text(lang.localized(p.sealed ? "report.done.verifyHint" : "report.done.notSealed"))
            }
            Section {
                Button { previewURL = p.pdf } label: {
                    Label(lang.localized("report.done.preview"), systemImage: "doc.richtext")
                }
                .accessibilityIdentifier("report.preview")
                Button { share(p.files) } label: {
                    Label(lang.localized("report.done.share"), systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("report.share")
            } footer: {
                Text(p.files.map(\.lastPathComponent).joined(separator: " · "))
                    .font(.scaled(size: 11))
            }
            Section {
                Text(lang.localized("report.done.policeTip"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func share(_ files: [URL]) {
        let ac = UIActivityViewController(activityItems: files, applicationActivities: nil)
        AppCoordinator.topViewController()?.present(ac, animated: true)
    }
}
