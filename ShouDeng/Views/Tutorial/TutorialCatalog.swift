import SwiftUI

// MARK: - How-to guides: what each one shows
//
// Every screen here mirrors a real one (same labels, icons and order) as of the
// files named on each guide. When a real screen changes, change its guide too.
// Captions and titles: "tut.<guide>.*" in Localizable.strings.

enum TutorialCatalog {
    static func guides(for role: TutorialRole) -> [TutorialGuide] {
        all.filter { $0.roles.contains(role) }
    }

    static func guide(_ id: String) -> TutorialGuide? {
        all.first { $0.id == id }
    }

    static let all: [TutorialGuide] = [
        sosGuide, silentSOS, fall, duress, respond, crewSOS, crash, riderSOS, nearby,
        checkIn, fakeCall, location, shift, bike,
        inviteGuardian, addPerson, joinCode, crew,
        lockCard, medical, textSize,
    ]
}

private typealias I = MockItem
private let safe = SettingsTint.safe
private let sos = SettingsTint.sos
private let pro = SettingsTint.pro
private let amber = SettingsTint.amber
private let blue = SettingsTint.blue
private let gray = SettingsTint.gray
private let teal = Color(red: 47/255, green: 111/255, blue: 143/255)
private let indigo = Color(red: 74/255, green: 93/255, blue: 138/255)
private let navy = Color(red: 27/255, green: 54/255, blue: 93/255)
private let cream = Color.paper(251, 248, 241)
private let darkBg = Color(red: 0.07, green: 0.07, blue: 0.09)

/// Sample people (localized so the replay reads naturally in every language)
private let me: MT = "tut.sample.me"
private let family: MT = "tut.sample.family"
private let elder: MT = "tut.sample.elder"
private let mate: MT = "tut.sample.mate"
private let rider: MT = "tut.sample.rider"

private let simpleTabs = (icons: ["shield.fill", "heart.text.square", "gearshape"], selected: 0)
private let riderTabs = (icons: ["bicycle", "person.3.fill", "heart.text.square", "gearshape"], selected: 0)
private let guardianTabs = (icons: ["eye.fill", "bubble.left.and.bubble.right", "clock.arrow.circlepath", "gearshape"], selected: 0)

// MARK: Shared screens

/// Simple home (SimpleProtectedHomeView)
private func simpleHome(checked: Bool = false, home: Bool = false, noGuardian: Bool = false) -> MockScreen {
    var items: [MockItem] = [I("greet", .greeting(.f("simple.greeting.morning", me),
                                                   noGuardian ? nil : .f("simple.watching", family)))]
    if noGuardian { items.append(I("invite", .row("person.badge.plus", teal, "simple.noGuardian", nil, .chevron))) }
    items += [
        I("ok", .bigButton(checked ? "checkmark.circle.fill" : "checkmark.circle", checked ? "simple.checkedIn" : "simple.checkIn", safe)),
        I("home", .bigButton("house.fill", home ? "simple.homeSent" : "simple.home", teal)),
        I("call", .bigButton("phone.fill", .f("simple.call", family), indigo)),
        I("sos", .sos("simple.sosHold")),
    ]
    return MockScreen(background: cream, items: items, tabs: simpleTabs)
}

/// The cancel countdown (SOSCountdownOverlay)
private func countdown() -> MockScreen {
    MockScreen(chrome: .call, items: [
        I("icon", .card("sos.circle.fill", sos, "sos.pending.title", nil)),
        I("count", .countdown("sos.pending.subtitle", 5, .white)),
        I("cancel", .button("sos.pending.cancel", .white, filled: true)),
        I("now", .button("sos.pending.sendNow", sos, filled: true)),
    ])
}

/// The SOS screen (SOSActiveView)
private func sosScreen(sheet: (title: MT?, items: [MockItem])? = nil) -> MockScreen {
    MockScreen(title: "sosmode.title", tint: sos, items: [
        I("head", .card("exclamationmark.triangle.fill", sos, "sosmode.title", "tut.sample.sosTimer")),
        I("g1", .row("person.fill", safe, family, "tut.sample.notified", .check)),
        I("call", .button(.f("sosmode.call", family), safe, filled: true)),
        I("emergency", .button(.f("sosmode.callEmergency", .emergency), sos, filled: false)),
        I("map", .map([MockPin(initial: "tut.sample.meInitial", color: sos, x: 0.5, y: 0.5, alert: true)])),
        I("end", .button("sosmode.end", gray, filled: false)),
    ], sheet: sheet)
}

/// Lock screen with the everyday card (LockScreenCards.swift)
private func lockScreen(silent: MT = .w("la.silent.sos")) -> MockScreen {
    MockScreen(chrome: .lock, items: [
        I("card", .lockCard("tut.sample.appName", .f("simple.watching", family),
                            [.w("la.sos.button"), silent, .w("la.fake.call"), .w("la.checkin.button")])),
    ])
}

/// Rider home (RiderHomeView)
private func riderHome(alert: Bool = false, onShift: Bool = false) -> MockScreen {
    var items: [MockItem] = [I("title", .greeting("rider.title", rider))]
    if alert {
        items.append(I("alert", .card("exclamationmark.triangle.fill", sos, .f("rider.crewAlert.title", mate), "tut.sample.away")))
    }
    items.append(onShift
                 ? I("shift", .row("record.circle", safe, "rider.shift.on", .f("rider.watch.by", family), .value(.r("0:12"))))
                 : I("shift", .row("moon.zzz.fill", gray, "rider.shift.off", nil, .none)))
    if !onShift { items.append(I("start", .button("rider.shift.start", safe, filled: true))) }
    items += [
        I("sos", .sos("simple.sosHold")),
        I("crash", .row("car.side.rear.and.collision.and.car.side.front", sos, "rider.crash.title", "rider.crash.short", .chevron)),
        I("bike", .row("exclamationmark.shield", amber, "rider.bike.title", "rider.bike.short", .chevron)),
    ]
    return MockScreen(items: items, tabs: riderTabs)
}

/// Guardian home (GuardianHomeView)
private func guardianHome(empty: Bool = false) -> MockScreen {
    var items: [MockItem] = [
        I("pill", .chips([empty ? "guardian.home.add.person" : "tut.sample.guarding"], nil)),
        I("map", .map([MockPin(initial: "tut.sample.elderInitial", color: safe, x: 0.35, y: 0.45),
                       MockPin(initial: "tut.sample.meInitial", color: pro, x: 0.7, y: 0.65)])),
    ]
    if !empty {
        items.append(I("person", .row("person.crop.circle.fill", safe, elder, "tut.sample.checkedIn", .chevron)))
    }
    return MockScreen(title: "nav.title", tint: pro, items: items, tabs: guardianTabs)
}

/// Settings, featured part (ProtectedSettingsView / SettingsKit)
private func settings(lockOn: Bool = false) -> MockScreen {
    MockScreen(title: "tab.settings", background: Color(.systemGroupedBackground), items: [
        I("display", .row("textformat.size", blue, "settings.section.display", "tut.sample.displayLine", .chevron)),
        I("lock", .row("lock.rectangle.stack.fill", safe, "settings.lockscreen", "settings.lockscreen.desc", .toggle(lockOn))),
        I("customize", .row("paintbrush.fill", safe, "lsc.customize", nil, .chevron)),
        I("fake", .row("phone.arrow.down.left.fill", indigo, "settings.safetyTools.fakeCall", "settings.featured.fakeCall.desc", .chevron)),
        I("medical", .row("cross.case.fill", sos, "settings.safetyTools.medicalCard", nil, .chevron)),
    ], tabs: (simpleTabs.icons, 2))
}

// MARK: Emergency

private let sosGuide = TutorialGuide(
    id: "sos", icon: "sos.circle.fill", tint: sos, category: .emergency, roles: [.protected], action: .sos,
    steps: [
        TutorialStep(caption: "tut.sos.s1", screen: simpleHome(), gesture: .hold("sos", 3)),
        TutorialStep(caption: "tut.sos.s2", screen: countdown(), gesture: .none),
        TutorialStep(caption: "tut.sos.s3", screen: sosScreen(), gesture: .tap("call")),
        TutorialStep(caption: "tut.sos.s4", screen: sosScreen(), gesture: .tap("end")),
        TutorialStep(caption: "tut.sos.s5", screen: sosScreen(sheet: ("sosmode.end.title", [
            I("confirm", .button("sosmode.end.confirm", safe, filled: true)),
            I("code", .button("sosmode.end.useCode", gray, filled: false)),
        ])), gesture: .tap("confirm")),
    ])

private let silentSOS = TutorialGuide(
    id: "silentSOS", icon: "speaker.slash.fill", tint: indigo, category: .emergency, roles: [.protected, .rider],
    action: .lockScreenCard,
    steps: [
        TutorialStep(caption: "tut.silentSOS.s1", screen: lockScreen(), gesture: .tap("card.1")),
        TutorialStep(caption: "tut.silentSOS.s2", screen: lockScreen(silent: .w("la.silent.again")), gesture: .tap("card.1")),
        TutorialStep(caption: "tut.silentSOS.s3", screen: lockScreen(silent: .w("la.silent.sent")), gesture: .none),
    ])

private func fallScreen() -> MockScreen {
    MockScreen(chrome: .call, items: [
        I("icon", .card("figure.fall", amber, "autosos.fall.title", "autosos.fall.subtitle")),
        I("count", .countdown("fall.sos.countdown", 60, amber)),
        I("help", .button("autosos.sendNow", sos, filled: true)),
        I("fine", .button("fall.im.fine", .white, filled: true)),
    ])
}

private let fall = TutorialGuide(
    id: "fall", icon: "figure.fall", tint: amber, category: .emergency, roles: [.protected],
    steps: [
        TutorialStep(caption: "tut.fall.s1", screen: simpleHome(), gesture: .shake),
        TutorialStep(caption: "tut.fall.s2", screen: fallScreen(), gesture: .none),
        TutorialStep(caption: "tut.fall.s3", screen: fallScreen(), gesture: .tap("fine")),
        TutorialStep(caption: "tut.fall.s4", screen: fallScreen(), gesture: .tap("help")),
    ])

private let duress = TutorialGuide(
    id: "duress", icon: "exclamationmark.shield.fill", tint: navy, category: .emergency, roles: [.protected],
    action: .duressCode,
    steps: [
        TutorialStep(caption: "tut.duress.s1", screen: sosScreen(), gesture: .tap("end")),
        TutorialStep(caption: "tut.duress.s2", screen: sosScreen(sheet: ("sosmode.end.title", [
            I("confirm", .button("sosmode.end.confirm", safe, filled: true)),
            I("code", .button("sosmode.end.useCode", gray, filled: false)),
        ])), gesture: .tap("code")),
        TutorialStep(caption: "tut.duress.s3", screen: sosScreen(sheet: ("sosmode.end.useCode", [
            I("field", .field("lock.fill", "settings.security.duressCode", .r("••••"))),
            I("ok", .button("settings.action.confirm", safe, filled: true)),
        ])), gesture: .type("field")),
        TutorialStep(caption: "tut.duress.s4", screen: simpleHome(), gesture: .none),
    ])

private func alertScreen(handled: Bool = false) -> MockScreen {
    var items: [MockItem] = [
        I("head", .greeting(.f("guardian.alert.seeking.help", elder), "tut.sample.sosTimerGuardian")),
        I("map", .map([MockPin(initial: "tut.sample.elderInitial", color: sos, x: 0.5, y: 0.45, alert: true)])),
    ]
    if handled { items.append(I("handling", .card("person.fill.checkmark", safe, "guardian.alert.youAreHandling", nil))) }
    items += [
        I("call", .button("guardian.alert.call.now", sos, filled: true)),
        I("got", .button(handled ? "guardian.alert.acknowledged" : "guardian.alert.i.got.it", safe, filled: !handled)),
        I("safe", .button(.f("guardian.alert.markSafe", elder), safe, filled: false)),
    ]
    return MockScreen(title: "guardian.alert.title", tint: sos, items: items)
}

private let respond = TutorialGuide(
    id: "respond", icon: "bell.badge.fill", tint: sos, category: .emergency, roles: [.guardian],
    steps: [
        TutorialStep(caption: "tut.respond.s1", screen: {
            var s = lockScreen()
            s.items = []
            s.banner = MockBanner(id: "push", icon: "exclamationmark.triangle.fill", tint: sos,
                                  title: .f("guardian.alert.seeking.help", elder), body: "tut.sample.pushBody")
            return s
        }(), gesture: .tap("push")),
        TutorialStep(caption: "tut.respond.s2", screen: alertScreen(), gesture: .tap("call")),
        TutorialStep(caption: "tut.respond.s3", screen: alertScreen(), gesture: .tap("got")),
        TutorialStep(caption: "tut.respond.s4", screen: alertScreen(handled: true), gesture: .tap("safe")),
    ])

private func crewAlertScreen() -> MockScreen {
    MockScreen(tint: sos, items: [
        I("head", .greeting(.f("rider.crewAlert.title", mate), "tut.sample.walk")),
        I("map", .map([MockPin(initial: "tut.sample.mateInitial", color: sos, x: 0.62, y: 0.4, alert: true),
                       MockPin(initial: "tut.sample.meInitial", color: safe, x: 0.3, y: 0.7)])),
        I("call", .button(.f("rider.crewAlert.callFirst", .emergency), sos, filled: true)),
        I("going", .button("rider.answer.goingButton", safe, filled: true)),
        I("cant", .button("rider.answer.cantButton", gray, filled: false)),
        I("nav", .button("sosmode.route.navigate", blue, filled: false)),
    ])
}

private let crewSOS = TutorialGuide(
    id: "crewSOS", icon: "person.3.fill", tint: sos, category: .emergency, roles: [.rider],
    steps: [
        TutorialStep(caption: "tut.crewSOS.s1", screen: riderHome(alert: true), gesture: .tap("alert")),
        TutorialStep(caption: "tut.crewSOS.s2", screen: crewAlertScreen(), gesture: .tap("call")),
        TutorialStep(caption: "tut.crewSOS.s3", screen: crewAlertScreen(), gesture: .tap("going")),
        TutorialStep(caption: "tut.crewSOS.s4", screen: crewAlertScreen(), gesture: .tap("nav")),
    ])

private func crashScreen() -> MockScreen {
    MockScreen(title: "rider.crash.title", tint: sos, items: [
        I("q", .greeting("rider.crash.question", nil)),
        I("hurt", .bigButton("cross.case.fill", "rider.crash.hurt", sos)),
        I("ok", .bigButton("checkmark.shield", "rider.crash.ok", safe)),
        I("call", .button(.f("rider.crash.call", .emergency), sos, filled: false)),
    ])
}

private let crash = TutorialGuide(
    id: "crash", icon: "car.side.rear.and.collision.and.car.side.front", tint: sos, category: .emergency, roles: [.rider],
    action: .crashReport,
    steps: [
        TutorialStep(caption: "tut.crash.s1", screen: riderHome(onShift: true), gesture: .tap("crash")),
        TutorialStep(caption: "tut.crash.s2", screen: crashScreen(), gesture: .tap("hurt")),
        TutorialStep(caption: "tut.crash.s3", screen: crashScreen(), gesture: .tap("ok")),
        TutorialStep(caption: "tut.crash.s4", screen: MockScreen(title: "rider.crash.title", tint: safe, items: [
            I("c1", .row("checkmark.square.fill", safe, "tut.crash.check1", nil, .none)),
            I("c2", .row("checkmark.square.fill", safe, "tut.crash.check2", nil, .none)),
            I("note", .field("square.and.pencil", "tut.crash.note", nil)),
            I("send", .button("rider.crash.send", safe, filled: true)),
        ]), gesture: .tap("send")),
    ])

private let riderSOS = TutorialGuide(
    id: "riderSOS", icon: "hand.raised.fill", tint: sos, category: .emergency, roles: [.rider], action: .handsFree,
    steps: [
        TutorialStep(caption: "tut.riderSOS.s1", screen: riderHome(onShift: true), gesture: .hold("sos", 3)),
        TutorialStep(caption: "tut.riderSOS.s2", screen: {
            var s = riderHome(onShift: true)
            s.sheet = ("rider.handsfree.title", [
                I("action", .row("button.horizontal.top.press", indigo, "rider.handsfree.action", nil, .none)),
                I("bar", .row("antenna.radiowaves.left.and.right", teal, "rider.handsfree.handlebar", nil, .none)),
                I("siri", .row("waveform", pro, "rider.handsfree.siri", nil, .none)),
            ])
            return s
        }(), gesture: .none),
        TutorialStep(caption: "tut.riderSOS.s3", screen: countdown(), gesture: .tap("cancel")),
    ])

private func fullMap(typed: Bool = false, result: Bool = false) -> MockScreen {
    var items: [MockItem] = [
        I("search", .field("magnifyingglass", "map.search.placeholder", typed ? "tut.nearby.query" : nil)),
        I("chips", .chips(["map.search.hospital", "map.search.police", "map.search.pharmacy"], result ? 0 : nil)),
        I("map", .map([MockPin(initial: "tut.sample.meInitial", color: blue, x: 0.4, y: 0.6),
                       MockPin(initial: .r("H"), color: sos, x: 0.7, y: 0.3),
                       MockPin(initial: .r("H"), color: sos, x: 0.2, y: 0.25)])),
    ]
    if result {
        items += [
            I("place", .row("cross.case.fill", sos, "tut.sample.hospital", "tut.sample.hospitalLine", .none)),
            I("navigate", .button("map.route.navigate", blue, filled: true)),
            I("callPlace", .button("map.place.call", safe, filled: false)),
        ]
    }
    return MockScreen(tint: blue, items: items)
}

private let nearby = TutorialGuide(
    id: "nearby", icon: "magnifyingglass", tint: blue, category: .emergency, roles: [.protected, .guardian],
    action: .emergencyNumbers,
    steps: [
        TutorialStep(caption: "tut.nearby.s1", screen: MockScreen(title: "nav.title", items: [
            I("map", .map([MockPin(initial: "tut.sample.meInitial", color: safe, x: 0.45, y: 0.5)])),
            I("expand", .row("arrow.up.left.and.arrow.down.right", blue, "location.expandMap", nil, .chevron)),
        ]), gesture: .tap("expand")),
        TutorialStep(caption: "tut.nearby.s2", screen: fullMap(), gesture: .tap("chips.0")),
        TutorialStep(caption: "tut.nearby.s3", screen: fullMap(), gesture: .type("search")),
        TutorialStep(caption: "tut.nearby.s4", screen: fullMap(typed: true, result: true), gesture: .tap("navigate")),
    ])

// MARK: Everyday

private let checkIn = TutorialGuide(
    id: "checkIn", icon: "checkmark.circle.fill", tint: safe, category: .everyday, roles: [.protected], action: .checkIn,
    steps: [
        TutorialStep(caption: "tut.checkIn.s1", screen: simpleHome(), gesture: .tap("ok")),
        TutorialStep(caption: "tut.checkIn.s2", screen: simpleHome(checked: true), gesture: .tap("home")),
        TutorialStep(caption: "tut.checkIn.s3", screen: {
            var s = guardianHome()
            s.banner = MockBanner(id: "push", icon: "house.fill", tint: safe, title: "tut.checkIn.push", body: nil)
            return s
        }(), gesture: .none),
    ])

private func fakeCallSettings() -> MockScreen {
    MockScreen(title: "settings.safetyTools.fakeCall", tint: safe, items: [
        I("name", .field("person.fill", "fakecall.caller.name", family)),
        I("delayLabel", .note("fakecall.delay")),
        I("delay", .chips([.r("0 s"), .r("5 s"), .r("15 s"), .r("30 s")], 2)),
        I("auto", .row("sos", sos, "fakecall.autoSOS", nil, .toggle(false))),
        I("go", .button("fakecall.trigger", safe, filled: true)),
    ])
}

private let fakeCall = TutorialGuide(
    id: "fakeCall", icon: "phone.arrow.down.left.fill", tint: indigo, category: .everyday, roles: [.protected],
    action: .fakeCall,
    steps: [
        TutorialStep(caption: "tut.fakeCall.s1", screen: settings(), gesture: .tap("fake")),
        TutorialStep(caption: "tut.fakeCall.s2", screen: fakeCallSettings(), gesture: .tap("delay.2")),
        TutorialStep(caption: "tut.fakeCall.s3", screen: fakeCallSettings(), gesture: .tap("go")),
        TutorialStep(caption: "tut.fakeCall.s4", screen: MockScreen(chrome: .call, items: [
            I("caller", .greeting(family, "tut.sample.mobile")),
            I("spacer", .note(.r(" "))),
            I("answer", .rounds([.init(icon: "phone.down.fill", color: sos, label: "tut.call.decline"),
                                 .init(icon: "phone.fill", color: safe, label: "tut.call.accept")])),
        ]), gesture: .tap("answer.1")),
    ])

private let location = TutorialGuide(
    id: "location", icon: "location.fill", tint: pro, category: .everyday, roles: [.guardian],
    steps: [
        TutorialStep(caption: "tut.location.s1", screen: guardianHome(), gesture: .tap("person")),
        TutorialStep(caption: "tut.location.s2", screen: MockScreen(title: "guardian.member.detail.title", tint: pro, items: [
            I("map", .map([MockPin(initial: "tut.sample.elderInitial", color: safe, x: 0.5, y: 0.5)])),
            I("live", .row("location.north.line.fill", safe, "live.title", "guardian.member.liveTrack.off", .chevron)),
            I("trips", .row("clock.arrow.circlepath", pro, "trip.history.title", nil, .chevron)),
            I("call", .button("guardian.member.call", safe, filled: true)),
        ]), gesture: .tap("trips")),
        TutorialStep(caption: "tut.location.s3", screen: MockScreen(title: "trip.history.title", tint: pro, items: [
            I("t1", .row("figure.walk", safe, "tut.sample.trip1", "tut.sample.trip1Line", .chevron)),
            I("t2", .row("bus.fill", blue, "tut.sample.trip2", "tut.sample.trip2Line", .chevron)),
        ]), gesture: .tap("t1")),
    ])

private func shiftSheet() -> MockScreen {
    var s = riderHome()
    s.sheet = (nil, [
        I("crew", .row("person.3.fill", safe, "rider.watch.colleagues", mate, .check)),
        I("family", .row("house.fill", teal, "rider.watch.family", family, .check)),
        I("end", .row("clock.badge.checkmark", amber, "rider.shift.plannedEnd", nil, .value(.r("18:00")))),
        I("go", .button("rider.shift.go", safe, filled: true)),
    ])
    return s
}

private let shift = TutorialGuide(
    id: "shift", icon: "play.circle.fill", tint: safe, category: .everyday, roles: [.rider], action: .startShift,
    steps: [
        TutorialStep(caption: "tut.shift.s1", screen: riderHome(), gesture: .tap("start")),
        TutorialStep(caption: "tut.shift.s2", screen: shiftSheet(), gesture: .tap("go")),
        TutorialStep(caption: "tut.shift.s3", screen: riderHome(onShift: true), gesture: .tap("shift")),
        TutorialStep(caption: "tut.shift.s4", screen: {
            var s = riderHome(onShift: true)
            s.sheet = ("rider.shift.endConfirm", [I("end", .button("rider.shift.end", sos, filled: true))])
            return s
        }(), gesture: .tap("end")),
    ])

private let bike = TutorialGuide(
    id: "bike", icon: "exclamationmark.shield", tint: amber, category: .everyday, roles: [.rider], action: .bikeReport,
    steps: [
        TutorialStep(caption: "tut.bike.s1", screen: riderHome(onShift: true), gesture: .tap("bike")),
        TutorialStep(caption: "tut.bike.s2", screen: MockScreen(title: "rider.bike.title", tint: amber, items: [
            I("log", .row("mappin.and.ellipse", amber, "rider.bike.log", nil, .chevron)),
            I("photo", .row("camera.fill", blue, "rider.bike.photo", nil, .chevron)),
            I("police", .row("shield.fill", indigo, .f("rider.bike.police", .police), nil, .chevron)),
            I("threat", .row("exclamationmark.triangle.fill", sos, .f("rider.bike.threat", .emergency), nil, .chevron)),
        ]), gesture: .tap("log")),
    ])

// MARK: People

private let inviteGuardian = TutorialGuide(
    id: "inviteGuardian", icon: "person.badge.plus", tint: teal, category: .people, roles: [.protected, .rider],
    action: .inviteGuardian,
    steps: [
        TutorialStep(caption: "tut.inviteGuardian.s1", screen: simpleHome(noGuardian: true), gesture: .tap("invite")),
        TutorialStep(caption: "tut.inviteGuardian.s2", screen: {
            var s = simpleHome(noGuardian: true)
            s.sheet = ("invite.sheet.title", [
                I("phone", .field("phone.fill", "invite.sheet.phone", .r("+1 416 555 0134"))),
                I("method", .note("invite.sheet.method")),
                I("sms", .row("message.fill", safe, "invite.method.sms", nil, .chevron)),
                I("other", .row("square.and.arrow.up", blue, "invite.method.wechat", nil, .chevron)),
                I("link", .row("link", gray, "invite.method.link", nil, .chevron)),
            ])
            return s
        }(), gesture: .type("phone")),
        TutorialStep(caption: "tut.inviteGuardian.s3", screen: {
            var s = simpleHome(noGuardian: true)
            s.sheet = ("invite.sheet.title", [
                I("phone", .field("phone.fill", "invite.sheet.phone", .r("+1 416 555 0134"))),
                I("method", .note("invite.sheet.method")),
                I("sms", .row("message.fill", safe, "invite.method.sms", nil, .chevron)),
                I("other", .row("square.and.arrow.up", blue, "invite.method.wechat", nil, .chevron)),
                I("link", .row("link", gray, "invite.method.link", nil, .chevron)),
            ])
            return s
        }(), gesture: .tap("sms")),
        TutorialStep(caption: "tut.inviteGuardian.s4", screen: simpleHome(), gesture: .none),
    ])

private func familySheet() -> MockScreen {
    var s = guardianHome(empty: true)
    s.sheet = ("guardian.family.title", [
        I("add", .row("person.badge.plus", safe, "guardian.home.add.person", "guardian.family.invite.sub", .chevron)),
        I("join", .row("key.fill", navy, "settings.joinFamily", nil, .chevron)),
    ])
    return s
}

private let addPerson = TutorialGuide(
    id: "addPerson", icon: "person.badge.plus", tint: pro, category: .people, roles: [.guardian], action: .invitePerson,
    steps: [
        TutorialStep(caption: "tut.addPerson.s1", screen: guardianHome(empty: true), gesture: .tap("pill.0")),
        TutorialStep(caption: "tut.addPerson.s2", screen: familySheet(), gesture: .tap("add")),
        TutorialStep(caption: "tut.addPerson.s3", screen: MockScreen(title: "invite.title", tint: pro, items: [
            I("gen", .button("invite.generate", safe, filled: true)),
        ]), gesture: .tap("gen")),
        TutorialStep(caption: "tut.addPerson.s4", screen: MockScreen(title: "invite.title", tint: pro, items: [
            I("label", .note("invite.codeLabel")),
            I("code", .code(.r("K7Q29M"))),
            I("copy", .button("invite.copy", gray, filled: false)),
            I("share", .button("invite.share", safe, filled: true)),
        ]), gesture: .tap("share")),
    ])

private func acceptScreen(found: Bool) -> MockScreen {
    var items: [MockItem] = [I("code", .field("key.fill", "wizard.invite.codePlaceholder", .r("K7Q29M")))]
    if found {
        items += [
            I("who", .card("person.crop.circle.fill", pro, .f("tut.joinCode.from", elder), nil)),
            I("accept", .button("invite.accept.accept", safe, filled: true)),
            I("decline", .button("invite.accept.decline", gray, filled: false)),
        ]
    } else {
        items.append(I("view", .button("invite.accept.view", navy, filled: true)))
    }
    return MockScreen(title: "settings.joinFamily", tint: navy, items: items)
}

private let joinCode = TutorialGuide(
    id: "joinCode", icon: "key.fill", tint: navy, category: .people, roles: [.guardian], action: .joinWithCode,
    steps: [
        TutorialStep(caption: "tut.joinCode.s1", screen: familySheet(), gesture: .tap("join")),
        TutorialStep(caption: "tut.joinCode.s2", screen: acceptScreen(found: false), gesture: .type("code")),
        TutorialStep(caption: "tut.joinCode.s3", screen: acceptScreen(found: false), gesture: .tap("view")),
        TutorialStep(caption: "tut.joinCode.s4", screen: acceptScreen(found: true), gesture: .tap("accept")),
    ])

private func crewScreen(joined: Bool) -> MockScreen {
    let items: [MockItem] = joined
        ? [
            I("name", .greeting("tut.sample.crewName", "tut.sample.crewLine")),
            I("m1", .row("person.fill", safe, mate, "tut.sample.onShift", .none)),
            I("m2", .row("person.fill", blue, "tut.sample.mate2", "tut.sample.offShift", .none)),
            I("invite", .button("rider.crew.invite", safe, filled: true)),
        ]
        : [
            I("createLabel", .note("rider.crew.create")),
            I("crewName", .field("person.3.fill", "rider.crew.namePlaceholder", nil)),
            I("create", .button("rider.crew.createButton", safe, filled: false)),
            I("joinLabel", .note("rider.crew.join")),
            I("code", .field("key.fill", .r("ABC123"), .r("R4D9XK"))),
            I("join", .button("rider.crew.joinButton", safe, filled: true)),
        ]
    return MockScreen(title: "rider.tab.crew", items: items, tabs: (riderTabs.icons, 1))
}

private let crew = TutorialGuide(
    id: "crew", icon: "person.3.fill", tint: safe, category: .people, roles: [.rider],
    steps: [
        TutorialStep(caption: "tut.crew.s1", screen: riderHome(), gesture: .tap("tab.1")),
        TutorialStep(caption: "tut.crew.s2", screen: crewScreen(joined: false), gesture: .type("code")),
        TutorialStep(caption: "tut.crew.s3", screen: crewScreen(joined: false), gesture: .tap("join")),
        TutorialStep(caption: "tut.crew.s4", screen: crewScreen(joined: true), gesture: .tap("invite")),
    ])

// MARK: Setup

private let lockCard = TutorialGuide(
    id: "lockCard", icon: "lock.rectangle.stack.fill", tint: safe, category: .setup, roles: [.protected, .rider],
    action: .lockScreenCard,
    steps: [
        TutorialStep(caption: "tut.lockCard.s1", screen: settings(), gesture: .tap("lock")),
        TutorialStep(caption: "tut.lockCard.s2", screen: settings(lockOn: true), gesture: .tap("customize")),
        TutorialStep(caption: "tut.lockCard.s3", screen: lockScreen(), gesture: .none),
        TutorialStep(caption: "tut.lockCard.s4", screen: lockScreen(), gesture: .tap("card.3")),
    ])

private let medical = TutorialGuide(
    id: "medical", icon: "cross.case.fill", tint: sos, category: .setup, roles: [.protected, .rider], action: .medicalCard,
    steps: [
        TutorialStep(caption: "tut.medical.s1", screen: settings(), gesture: .tap("medical")),
        TutorialStep(caption: "tut.medical.s2", screen: MockScreen(title: "medical.title", tint: sos, items: [
            I("blood", .field("drop.fill", "tut.medical.blood", .r("O+"))),
            I("allergy", .field("allergens", "tut.medical.allergy", "tut.medical.allergyValue")),
            I("preview", .button("medical.preview", blue, filled: false)),
            I("save", .button("medical.save", safe, filled: true)),
        ]), gesture: .type("allergy")),
        TutorialStep(caption: "tut.medical.s3", screen: MockScreen(title: "medical.title", tint: sos, items: [
            I("blood", .field("drop.fill", "tut.medical.blood", .r("O+"))),
            I("allergy", .field("allergens", "tut.medical.allergy", "tut.medical.allergyValue")),
            I("preview", .button("medical.preview", blue, filled: false)),
            I("save", .button("medical.save", safe, filled: true)),
        ]), gesture: .tap("save")),
        TutorialStep(caption: "tut.medical.s4", screen: MockScreen(title: "medical.emergencyInfo", tint: sos, items: [
            I("card", .card("staroflife.fill", sos, "medical.emergencyInfo", "tut.medical.summary")),
        ]), gesture: .none),
    ])

private func displayScreen(size: Int?, lang: Int?) -> MockScreen {
    MockScreen(title: "settings.section.display", tint: blue, background: Color(.systemGroupedBackground), items: [
        I("langs", .chips([.r("English"), .r("简体中文"), .r("繁體中文"), .r("Français")], lang)),
        I("sizes", .chips([.r("Aa"), .r("Aa+"), .r("Aa++"), .r("Aa+++")], size)),
        I("dark", .row("moon.fill", indigo, "tut.textSize.dark", nil, .toggle(false))),
    ], tabs: (simpleTabs.icons, 2))
}

private let textSize = TutorialGuide(
    id: "textSize", icon: "textformat.size", tint: blue, category: .setup, roles: [.protected, .guardian, .rider],
    action: .textSize,
    steps: [
        TutorialStep(caption: "tut.textSize.s1", screen: settings(), gesture: .tap("display")),
        TutorialStep(caption: "tut.textSize.s2", screen: displayScreen(size: 0, lang: nil), gesture: .tap("sizes.3")),
        TutorialStep(caption: "tut.textSize.s3", screen: displayScreen(size: 3, lang: nil), gesture: .tap("langs.1")),
    ])
