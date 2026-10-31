import Foundation
import CoreLocation

// MARK: - Demo Dataset (the Chen family)
//
// Built with the app's own models, every timestamp relative to `now`, names and
// texts in the current app language. Ported from
// docs/explore-mode/tools/gen_demo_family.swift (design branch).
//
//   Mom   (protected) — Chengdu
//   Dad   (protected) — Chengdu (low battery, check-in due)
//   Sarah (guardian)  — Toronto
//   Kevin (guardian)  — Shanghai
//   Lucy  (guardian)  — Paris

enum DemoRole: String, CaseIterable, Identifiable {
    case mom      // protected person's phone
    case sarah    // guardian's phone

    var id: String { rawValue }
    var userId: String { self == .mom ? DemoDataset.momId : DemoDataset.sarahId }
    var userRole: UserRole { self == .mom ? .protected_ : .guardian }
    var other: DemoRole { self == .mom ? .sarah : .mom }
    /// Where the persona's phone "is" (Chengdu / Toronto) — the demo never reads GPS.
    var homeCoordinate: CLLocationCoordinate2D {
        self == .mom ? CLLocationCoordinate2D(latitude: 30.6586, longitude: 104.0647)
                     : CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832)
    }
}

struct DemoDataset {
    static let momId = "demo_mom"
    static let dadId = "demo_dad"
    static let sarahId = "demo_sarah"
    static let kevinId = "demo_kevin"
    static let lucyId = "demo_lucy"

    let now: Date
    let mom: User
    let dad: User
    let sarah: User
    let kevin: User
    let lucy: User
    let guardiansOfMom: [Guardian]
    let guardiansOfDad: [Guardian]
    var momPerson: ProtectedPerson
    var dadPerson: ProtectedPerson
    var posts: [FamilyPost]
    var timelines: [String: [TimelineEntry]]
    let safeZones: [SafeZone]

    var users: [User] { [mom, dad, sarah, kevin, lucy] }

    func user(_ id: String) -> User? { users.first { $0.id == id } }

    static func build(now: Date = Date(), language: AppLanguage = LanguageManager.shared.current) -> DemoDataset {
        let t = DemoText(language: language)
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        func user(_ id: String, _ name: String, _ role: UserRole, _ tz: String, _ cc: String, _ city: String, _ phone: String) -> User {
            User(id: id, displayName: name, role: role, avatarInitial: String(name.prefix(1)), avatarLocalPath: nil,
                 phone: phone, email: nil, timeZone: TimeZone(identifier: tz)!, countryCode: cc,
                 cityName: city, createdAt: ago(60 * 24 * 90))
        }

        let mom   = user(momId,   t.momName,   .protected_, "Asia/Shanghai",   "CN", t.chengdu,  "+8613800000001")
        let dad   = user(dadId,   t.dadName,   .protected_, "Asia/Shanghai",   "CN", t.chengdu,  "+8613800000002")
        let sarah = user(sarahId, t.sarahName, .guardian,   "America/Toronto", "CA", t.toronto,  "+14165550101")
        let kevin = user(kevinId, t.kevinName, .guardian,   "Asia/Shanghai",   "CN", t.shanghai, "+8613900000003")
        let lucy  = user(lucyId,  t.lucyName,  .guardian,   "Europe/Paris",    "FR", t.paris,    "+33600000004")

        // Duty hours are in the protected person's (Chengdu) time zone
        func guardian(_ u: User, slots: [(Int, Int)], rt: Double) -> Guardian {
            Guardian(id: u.id, user: u, permissions: .defaultPermissions, isOnDuty: false,
                     dutySchedule: DutySchedule(guardianId: u.id,
                                                slots: slots.map { DutySlot(startHour: $0.0, endHour: $0.1, dayOfWeek: [], isConfirmed: true) }),
                     averageResponseTime: rt, linkedSince: ago(60 * 24 * 80))
        }
        // Sarah covers Toronto daytime (20:00–08:00 Chengdu), Kevin 08–20,
        // Lucy 15–23 — leaving a visible coverage gap for the checklist step.
        var gSarah = guardian(sarah, slots: [(20, 24), (0, 7)], rt: 95)
        var gKevin = guardian(kevin, slots: [(8, 20)], rt: 40)
        var gLucy  = guardian(lucy,  slots: [(15, 23)], rt: 180)
        let chengduHour = Calendar.current.dateComponents(in: mom.timeZone, from: now).hour ?? 12
        gSarah.isOnDuty = chengduHour >= 20 || chengduHour < 7
        gKevin.isOnDuty = (8..<20).contains(chengduHour)
        gLucy.isOnDuty = (15..<23).contains(chengduHour)
        let guardiansOfMom = [gSarah, gKevin, gLucy]
        let guardiansOfDad = [gSarah, gKevin]

        func loc(_ lat: Double, _ lng: Double, _ minAgo: Double, _ addr: String, zone: String? = nil,
                 act: Location.ActivityType = .stationary) -> Location {
            Location(latitude: lat, longitude: lng, accuracy: 12, altitude: nil, speed: nil,
                     timestamp: ago(minAgo), address: addr, isInSafeZone: zone != nil,
                     safeZoneName: zone, activityType: act)
        }

        let momPerson = ProtectedPerson(
            id: mom.id, user: mom, guardians: guardiansOfMom, protectionLayers: 3,
            lastCheckIn: ago(38), lastKnownLocation: loc(30.6586, 104.0647, 6, t.momAddress, zone: t.home),
            batteryLevel: 0.82, batteryState: .unplugged, lastPhoneActivity: ago(4), status: .normal)
        let dadPerson = ProtectedPerson(
            id: dad.id, user: dad, guardians: guardiansOfDad, protectionLayers: 2,
            lastCheckIn: ago(60 * 3.5), lastKnownLocation: loc(30.6705, 104.0435, 22, t.dadAddress, act: .walking),
            batteryLevel: 0.17, batteryState: .unplugged, lastPhoneActivity: ago(22), status: .pendingCheckIn)

        func entry(_ m: Double, _ type: TimelineEntryType, _ d: String, _ detail: String? = nil) -> TimelineEntry {
            TimelineEntry(id: "demo-\(type.rawValue)-\(Int(m))", timestamp: ago(m), type: type, description: d, detail: detail)
        }
        func comment(_ id: String, _ u: User, _ text: String, _ m: Double) -> FamilyComment {
            FamilyComment(id: id, authorId: u.id, authorName: u.displayName, authorInitial: u.avatarInitial,
                          authorAvatarPath: nil, text: text, createdAt: ago(m))
        }
        let posts: [FamilyPost] = [
            FamilyPost(id: "demo-p1", authorId: mom.id, authorName: mom.displayName, authorInitial: mom.avatarInitial,
                       authorAvatarPath: nil, text: t.post1, mediaURLs: [], createdAt: ago(55),
                       comments: [comment("demo-c1", sarah, t.comment1, 40), comment("demo-c2", lucy, t.comment2, 31)],
                       commentCount: 2, latitude: 30.6586, longitude: 104.0647, locationName: t.chengdu),
            FamilyPost(id: "demo-p2", authorId: lucy.id, authorName: lucy.displayName, authorInitial: lucy.avatarInitial,
                       authorAvatarPath: nil, text: t.post2, mediaURLs: [], createdAt: ago(60 * 5),
                       comments: [], commentCount: 0, latitude: nil, longitude: nil, locationName: t.paris),
            FamilyPost(id: "demo-p3", authorId: kevin.id, authorName: kevin.displayName, authorInitial: kevin.avatarInitial,
                       authorAvatarPath: nil, text: t.post3, mediaURLs: [], createdAt: ago(60 * 26),
                       comments: [], commentCount: 0, latitude: nil, longitude: nil, locationName: t.shanghai),
        ]

        let timelines: [String: [TimelineEntry]] = [
            sarah.id: [
                entry(6, .enteredSafeZone, t.tlMomHome, t.momAddress),
                entry(38, .checkIn, t.tlMomCheckedIn),
                entry(60 * 2, .batteryLow, t.tlDadBattery),
                entry(60 * 3.5, .checkIn, t.tlDadCheckedIn),
            ],
            mom.id: [
                entry(6, .enteredSafeZone, t.tlArrivedHome),
                entry(38, .checkIn, t.tlCheckedIn),
                entry(60 * 5, .homeTimerDismissed, t.tlTimerDone),
                entry(60 * 26, .arrivalReport, t.tlArrival, t.station),
            ],
        ]

        let safeZones = [SafeZone(id: "demo-z1", name: t.home, latitude: 30.6586, longitude: 104.0647, radius: 150,
                                  isAutoSuggested: false, visitFrequency: 30, typicalHours: 19...23)]

        return DemoDataset(now: now, mom: mom, dad: dad, sarah: sarah, kevin: kevin, lucy: lucy,
                           guardiansOfMom: guardiansOfMom, guardiansOfDad: guardiansOfDad,
                           momPerson: momPerson, dadPerson: dadPerson, posts: posts,
                           timelines: timelines, safeZones: safeZones)
    }
}

/// Localized demo copy (names stay recognisable across languages).
struct DemoText {
    let language: AppLanguage
    private var zh: Bool { language.isChinese }
    private var fr: Bool { language == .french }
    private func pick(_ en: String, _ zh: String, _ fr: String) -> String {
        guard self.zh else { return self.fr ? fr : en }
        return language == .traditionalChinese
            ? (zh.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zh) : zh
    }

    var momName: String { pick("Xiulan Chen", "陈秀兰", "Xiulan Chen") }
    var dadName: String { pick("Jianguo Chen", "陈建国", "Jianguo Chen") }
    var sarahName: String { pick("Sarah Chen", "陈思雅", "Sarah Chen") }
    var kevinName: String { pick("Kevin Chen", "陈凯文", "Kevin Chen") }
    var lucyName: String { pick("Lucy Chen", "陈露西", "Lucy Chen") }
    var chengdu: String { pick("Chengdu", "成都", "Chengdu") }
    var toronto: String { pick("Toronto", "多伦多", "Toronto") }
    var shanghai: String { pick("Shanghai", "上海", "Shanghai") }
    var paris: String { pick("Paris", "巴黎", "Paris") }
    var home: String { pick("Home", "家", "Maison") }
    var momAddress: String { pick("Jinjiang District, Chengdu", "成都市锦江区", "District de Jinjiang, Chengdu") }
    var dadAddress: String { pick("People's Park, Chengdu", "成都人民公园", "Parc du Peuple, Chengdu") }
    var station: String { pick("Chengdu East Station", "成都东站", "Gare de Chengdu-Est") }
    var post1: String { pick("Morning tai chi done ☀️ The plum blossoms by the river are out.", "晨练太极打完了 ☀️ 河边的梅花开了。", "Tai-chi du matin fait ☀️ Les pruniers sont en fleurs au bord de la rivière.") }
    var comment1: String { pick("So pretty! Don't forget your jacket, Mom.", "好美！妈，记得穿外套。", "Magnifique ! N'oublie pas ta veste, maman.") }
    var comment2: String { pick("Miss you Grandma 💛", "想你了奶奶 💛", "Tu me manques mamie 💛") }
    var post2: String { pick("Exam week in Paris 📚 Video call this Sunday?", "巴黎考试周 📚 周日视频？", "Semaine d'examens à Paris 📚 Appel vidéo dimanche ?") }
    var post3: String { pick("Booked the train to Chengdu for the holiday — home on the 1st!", "订好了回成都的火车票——1 号到家！", "Train pour Chengdu réservé — à la maison le 1er !") }
    var tlMomHome: String { pick("Mom arrived home", "妈妈到家了", "Maman est rentrée") }
    var tlMomCheckedIn: String { pick("Mom checked in · I'm safe", "妈妈报了平安", "Maman a donné des nouvelles") }
    var tlDadBattery: String { pick("Dad's battery is at 17%", "爸爸手机电量 17%", "Batterie de papa à 17 %") }
    var tlDadCheckedIn: String { pick("Dad checked in", "爸爸报了平安", "Papa a donné des nouvelles") }
    var tlArrivedHome: String { pick("Arrived home", "到家了", "Arrivée à la maison") }
    var tlCheckedIn: String { pick("Checked in · I'm safe", "报平安", "Nouvelles données") }
    var tlTimerDone: String { pick("Home timer completed", "回家计时已完成", "Minuteur de retour terminé") }
    var tlArrival: String { pick("Arrival reported", "已报到达", "Arrivée signalée") }
}
