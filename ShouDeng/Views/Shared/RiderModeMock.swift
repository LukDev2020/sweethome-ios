#if DEBUG
import SwiftUI
import AVFoundation

// MARK: - Rider mode — design mock (Debug only)
//
// Launch with `-rider-mock`. Static sample data, nothing is sent. Four screens:
// rider home (shift), rider SOS, what a nearby crew rider sees, bike-tampering report.
// For review before building the real feature.

struct RiderModeMock: View {
    enum Page: String, CaseIterable { case home = "Home", sos = "SOS", crew = "Crew alert", report = "Bike" }
    @State private var page: Page = .home

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.96))
            Group {
                switch page {
                case .home: RiderHomeMock(onSOS: { page = .sos }, onReport: { page = .report })
                case .sos: RiderSOSMock()
                case .crew: CrewAlertMock()
                case .report: BikeReportMock()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .preferredColorScheme(.light)
    }
}

private enum M {
    static let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    static let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    static let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    static let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    static let cream = Color(red: 251/255, green: 248/255, blue: 241/255)
    static let address = "Little Bourke St, near Russell St"
    static let suburb = "Melbourne VIC 3000"
}

// MARK: 1. Rider home

private struct RiderHomeMock: View {
    let onSOS: () -> Void
    let onReport: () -> Void
    @State private var onShift = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rider mode").font(.system(size: 26, weight: .bold)).foregroundStyle(M.ink)
                        Text("Kai · Melbourne CBD").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bicycle").font(.system(size: 28)).foregroundStyle(M.safe)
                }

                // Shift card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(onShift ? M.safe : .gray).frame(width: 10, height: 10)
                        Text(onShift ? "On shift · 2 h 14 min" : "Off shift").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: $onShift).labelsHidden().tint(M.safe)
                    }
                    if onShift {
                        Label("Sharing live location with Melbourne crew (3) and Wei (roommate)", systemImage: "location.fill")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Label("Shift ends 23:00 — we'll check you got home. No answer in 30 min → crew is alerted.", systemImage: "clock.badge.checkmark")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(M.cream))

                // SOS
                Button(action: onSOS) {
                    VStack(spacing: 6) {
                        Text("SOS").font(.system(size: 40, weight: .black))
                        Text("Hold 3 s · or press the handlebar button").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 130)
                    .background(RoundedRectangle(cornerRadius: 22).fill(M.alert))
                }
                .buttonStyle(.plain)

                // Ways to trigger without looking
                HStack(spacing: 8) {
                    trigger("button.horizontal.top.press", "Action button")
                    trigger("antenna.radiowaves.left.and.right", "Handlebar ✓")
                    trigger("waveform", "\"Lantern SOS\"")
                    trigger("applewatch", "Watch")
                }

                // Quick actions
                Text("Quick actions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
                action("exclamationmark.shield", "Bike tampered with?", "Don't confront — report it and call police", M.lamp, onReport)
                action("map", "Night caution spots", "2 flagged by your crew near you tonight", M.ink, {})
                action("person.2.badge.plus", "Add a contact in Melbourne", "Your family is in Guangzhou — add someone who can be there in minutes", M.safe, {})
            }
            .padding(16)
        }
    }

    private func trigger(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(M.ink)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
    }

    private func action(_ icon: String, _ title: String, _ detail: String, _ color: Color, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(M.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.97)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: 2. Rider SOS

private struct RiderSOSMock: View {
    @State private var speaking = false
    private let synth = AVSpeechSynthesizer()
    private let phrase = "Ambulance please. Someone is badly hurt and bleeding. We are at Little Bourke Street, near Russell Street, Melbourne. I speak Mandarin."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Label("SOS is on · 00:42", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text("Crew and Wei alerted · recording audio (your choice in settings)")
                        .font(.system(size: 12)).opacity(0.9)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(M.alert))

                // Address, big — to read out
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOU ARE AT").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    Text(M.address).font(.system(size: 22, weight: .bold)).foregroundStyle(M.ink)
                    Text("\(M.suburb) · ±8 m").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(M.cream))

                // 000
                Button {} label: {
                    Label("Call 000", systemImage: "phone.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 18).fill(M.alert))
                }
                .buttonStyle(.plain)

                // Speak for me
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Say this to 000").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            if speaking { synth.stopSpeaking(at: .immediate); speaking = false; return }
                            let u = AVSpeechUtterance(string: phrase)
                            u.voice = AVSpeechSynthesisVoice(language: "en-AU")
                            u.rate = 0.45
                            synth.speak(u); speaking = true
                        } label: {
                            Label(speaking ? "Stop" : "Speak for me", systemImage: speaking ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(M.ink)).foregroundStyle(.white)
                        }
                    }
                    Text("\"Ambulance. Someone is badly hurt and bleeding. We're at Little Bourke St, near Russell St. Mandarin interpreter, please.\"")
                        .font(.system(size: 17, weight: .medium)).foregroundStyle(M.ink)
                    Text("需要救护车。有人重伤流血。我们在 Little Bourke St，靠近 Russell St。请提供普通话翻译。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).stroke(M.ink.opacity(0.2)))

                // Bystander: bleeding control
                VStack(alignment: .leading, spacing: 8) {
                    Text("IF YOU ARE HELPING").font(.system(size: 11, weight: .bold)).foregroundStyle(M.alert)
                    step("1", "hand.raised.fill", "Press hard on the wound with cloth or your hands. Don't let go.")
                    step("2", "phone.fill", "Call 000 on speaker and keep pressing.")
                    step("3", "heart.fill", "Not breathing? Start CPR — 000 will guide you.")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(M.alert.opacity(0.08)))

                // Nearby crew
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEARBY CREW").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    crew("W", "Wei", "220 m", "On the way · called 000", M.safe)
                    crew("A", "Ahmed", "450 m", "Alerted", M.lamp)
                    crew("L", "Li Na", "1.2 km", "Alerted", .gray)
                    Text("Family in Guangzhou notified")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.97)))
            }
            .padding(16)
        }
    }

    private func step(_ n: String, _ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(M.alert))
            Image(systemName: icon).foregroundStyle(M.alert).frame(width: 20)
            Text(text).font(.system(size: 15)).foregroundStyle(M.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func crew(_ initial: String, _ name: String, _ distance: String, _ state: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(initial).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Circle().fill(color))
            Text(name).font(.system(size: 15, weight: .semibold))
            Text(distance).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(state).font(.system(size: 13, weight: .medium)).foregroundStyle(color)
        }
    }
}

// MARK: 3. What a nearby crew rider sees

private struct CrewAlertMock: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 14) {
                // Critical alert banner as it arrives (breaks through silent / Focus)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(M.alert).font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CRITICAL · LANTERN CARE").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        Text("Kai needs help — 220 m away").font(.system(size: 16, weight: .bold))
                        Text("\(M.address) · SOS 40 s ago").font(.system(size: 13))
                    }
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThickMaterial))
                .padding(.top, 30)

                // Opened
                VStack(alignment: .leading, spacing: 12) {
                    Text("Kai needs help").font(.system(size: 24, weight: .bold)).foregroundStyle(M.ink)
                    HStack {
                        Image(systemName: "figure.walk").foregroundStyle(M.safe)
                        Text("220 m · about 3 min on foot").font(.system(size: 15))
                    }
                    RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.9, green: 0.93, blue: 0.9))
                        .frame(height: 140)
                        .overlay(
                            ZStack {
                                Path { p in p.move(to: CGPoint(x: 60, y: 110)); p.addLine(to: CGPoint(x: 160, y: 70)); p.addLine(to: CGPoint(x: 250, y: 40)) }
                                    .stroke(M.safe, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                Circle().fill(M.alert).frame(width: 18, height: 18).position(x: 250, y: 40)
                                Circle().fill(.blue).frame(width: 14, height: 14).position(x: 60, y: 110)
                            }
                        )
                    Button {} label: {
                        Label("Call 000 first", systemImage: "phone.fill")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(M.alert))
                    }.buttonStyle(.plain)
                    HStack(spacing: 8) {
                        pill("I'm going", M.safe)
                        pill("Can't help", .gray)
                    }
                    Label("Only go if it's safe. Don't confront anyone — press on the wound and wait for 000.", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
                Spacer()
            }
            .padding(.horizontal, 14)
        }
    }

    private func pill(_ title: String, _ color: Color) -> some View {
        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 14).stroke(color, lineWidth: 1.5))
    }
}

// MARK: 4. Bike tampered with

private struct BikeReportMock: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Bike tampered with?").font(.system(size: 26, weight: .bold)).foregroundStyle(M.ink)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.slash.fill").font(.system(size: 22)).foregroundStyle(M.alert)
                    Text("Don't confront them. A bike can be replaced — you can't. Step back to a lit, busy spot first.")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(M.alert)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(M.alert.opacity(0.08)))

                row("camera.fill", "Take a photo from a distance", "Saved with time and place for police and insurance")
                row("phone.fill", "Call police assistance 131 444", "Non-urgent. If anyone threatens you, call 000")
                row("person.3.fill", "Tell your crew", "Riders nearby see a caution at this spot for tonight")
                row("antenna.radiowaves.left.and.right", "Bike tag", "Your tag warns you when the bike moves — before you walk back")

                VStack(alignment: .leading, spacing: 6) {
                    Text("LOGGED").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    Text("20:10 · \(M.address)").font(.system(size: 15, weight: .medium))
                    Text("1 photo · shared with crew").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(M.cream))
            }
            .padding(16)
        }
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(M.ink).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(M.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.97)))
    }
}
#endif
