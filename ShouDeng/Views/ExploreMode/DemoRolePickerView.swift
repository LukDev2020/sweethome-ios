import SwiftUI
import Combine

// MARK: - "Meet the Chen family" — pick whose phone to see

struct DemoRolePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    /// The phone being opened: preparing the sample family takes a few seconds
    @State private var starting: DemoRole?
    nonisolated(unsafe) private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        let lm = LanguageManager.shared
        let t = DemoText(language: lm.current)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(lm.localized("explore.picker.eyebrow").uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(lamp)
                Text(lm.localized("explore.picker.title"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Text(lm.localized("explore.picker.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    member(AvatarInitial.make(for: t.momName), lm.localized("explore.member.mom"), t.chengdu, "Asia/Shanghai", lamp)
                    member(AvatarInitial.make(for: t.sarahName), t.sarahName.components(separatedBy: " ").first ?? t.sarahName, t.toronto, "America/Toronto", safe)
                    member(AvatarInitial.make(for: t.kevinName), t.kevinName.components(separatedBy: " ").first ?? t.kevinName, t.shanghai, "Asia/Shanghai", safe)
                    member(AvatarInitial.make(for: t.lucyName), t.lucyName.components(separatedBy: " ").first ?? t.lucyName, t.paris, "Europe/Paris", safe)
                }

                Text(lm.localized("explore.picker.question"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(.top, 4)

                roleButton(.mom, icon: "shield.lefthalf.filled", title: lm.localized("explore.phone.mom"),
                           detail: lm.localized("explore.picker.mom.detail"))
                roleButton(.sarah, icon: "eye", title: lm.localized("explore.phone.sarah"),
                           detail: lm.localized("explore.picker.sarah.detail"))

                Text(lm.localized("explore.picker.footnote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(22)
        }
        .onReceive(timer) { now = $0 }
        .presentationDetents([.large])
    }

    private func member(_ initial: String, _ name: String, _ city: String, _ tz: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Circle().fill(color).frame(width: 30, height: 30)
                .overlay(Text(initial).font(.footnote.weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.4).padding(2))
                .accessibilityHidden(true)
            Text(name).font(.footnote.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
            Text(city).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(localTime(tz)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.4)))
        .accessibilityElement(children: .combine)
    }

    private func localTime(_ tz: String) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = "HH:mm"
        return f.string(from: now)
    }

    private func roleButton(_ role: DemoRole, icon: String, title: String, detail: String) -> some View {
        Button {
            guard starting == nil else { return }
            // Show the spinner first, then build the demo behind the sheet and close it
            // when ready — closing first left the login screen frozen for seconds.
            starting = role
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ExploreModeController.shared.start(role: role)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(role == .mom ? lamp : safe)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill((role == .mom ? lamp : safe).opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(ink)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                if starting == role {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .padding(14)
            // The whole card is the button — it is only outlined, so without a shape
            // only the icon and text took taps
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .background(RoundedRectangle(cornerRadius: 14).stroke(role == .mom ? lamp : Color(.separator), lineWidth: role == .mom ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
