import SwiftUI
import ContactsUI

// MARK: - Emergency Contacts View
//
// Shows regional emergency numbers based on the protected person's location,
// and allows pre-entering custom local emergency contacts.
// Accessible from the guardian home / member detail.

struct EmergencyContactsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared

    let personName: String
    let countryCode: String  // ISO 3166-1 alpha-2 (e.g. "UA", "CN", "CA")

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @AppStorage("custom_emergency_contacts") private var customContactsData: Data = Data()
    @State private var showAddContact = false
    @State private var customContacts: [LocalEmergencyContact] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "phone.arrow.up.right.fill")
                        .font(.scaled(size: 28))
                        .foregroundStyle(alert)
                    Text(langManager.localized("emergency.contacts.title"))
                        .font(.scaled(size: 18, weight: .bold))
                    Text(String(format: langManager.localized("emergency.contacts.regionInfo"), personName, regionInfo.regionName))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Regional emergency numbers
                regionalNumbersPanel

                // Custom local contacts
                localContactsPanel

                // Tip
                Text(langManager.localized("emergency.contacts.tip"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle(langManager.localized("emergency.contacts.navTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddContact = true
                } label: {
                    Label(LanguageManager.shared.localized("emergency.contacts.add"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddEmergencyContactView(contacts: $customContacts, countryCode: countryCode)
        }
        .onAppear {
            loadCustomContacts()
            Task {
                let serverContacts = await coordinator.fetchEmergencyContacts()
                if !serverContacts.isEmpty { customContacts = serverContacts }
            }
        }
        .onChange(of: customContacts) {
            saveCustomContacts()
            Task { await coordinator.saveEmergencyContacts(customContacts) }
        }
    }

    private var regionInfo: RegionalEmergencyInfo {
        RegionalEmergencyInfo.forCountry(countryCode)
    }

    // MARK: - Regional Numbers Panel

    private var regionalNumbersPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(langManager.localized("emergency.contacts.localNumbers"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: langManager.localized("emergency.contacts.areaCode"), regionInfo.areaCode))
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(ink)
            }

            ForEach(regionInfo.numbers, id: \.label) { number in
                emergencyNumberRow(
                    icon: number.icon,
                    iconColor: number.color,
                    label: number.label,
                    number: number.number,
                    note: number.note
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(alert.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(alert.opacity(0.2), lineWidth: 1)
        )
    }

    private func emergencyNumberRow(icon: String, iconColor: Color, label: String, number: String, note: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.scaled(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.scaled(size: 13, weight: .medium))
                if let note {
                    Text(note)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                callNumber(number)
            } label: {
                Text(number)
                    .font(.scaled(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(alert)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Local Contacts Panel

    private var localContactsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(langManager.localized("emergency.contacts.customContacts"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddContact = true
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus.circle")
                            .font(.scaled(size: 12))
                        Text(langManager.localized("emergency.contacts.add"))
                            .font(.scaled(size: 12))
                    }
                    .foregroundStyle(safe)
                }
            }

            if customContacts.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.scaled(size: 24))
                            .foregroundStyle(.tertiary)
                        Text(langManager.localized("emergency.contacts.noContacts"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.tertiary)
                        Text(langManager.localized("emergency.contacts.noContactsHint"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ForEach(Array(customContacts.enumerated()), id: \.element.id) { index, contact in
                    localContactRow(contact: contact, index: index)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func localContactRow(contact: LocalEmergencyContact, index: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(safe.opacity(0.12))
                    .frame(width: 32, height: 32)
                Text(AvatarInitial.make(for: contact.name))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(safe)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.scaled(size: 13, weight: .medium))
                Text(contact.relationship)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                if !contact.address.isEmpty {
                    Text(contact.address)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if !contact.phone.isEmpty {
                    Button { callNumber(contact.phone) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "phone.fill")
                                .font(.scaled(size: 10))
                            Text(contact.phone)
                                .font(.scaled(size: 12, design: .monospaced))
                        }
                        .foregroundStyle(safe)
                    }
                }
                if !contact.email.isEmpty {
                    Text(contact.email)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                customContacts.remove(at: index)
            } label: {
                Label(langManager.localized("emergency.contacts.delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func callNumber(_ number: String) {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "tel://\(cleaned)") {
            ExternalURL.open(url)
        }
    }

    private func loadCustomContacts() {
        if let decoded = try? JSONDecoder().decode([LocalEmergencyContact].self, from: customContactsData) {
            customContacts = decoded
        }
    }

    private func saveCustomContacts() {
        if let encoded = try? JSONEncoder().encode(customContacts) {
            customContactsData = encoded
        }
    }
}

// MARK: - Add Emergency Contact Sheet

struct AddEmergencyContactView: View {
    @Binding var contacts: [LocalEmergencyContact]
    let countryCode: String
    @Environment(\.dismiss) var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    @State private var name = ""
    @State private var relationship = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var showContactPicker = false

    private var relationshipOptions: [String] {
        [
            LanguageManager.shared.localized("emergency.contacts.rel.neighbor"),
            LanguageManager.shared.localized("emergency.contacts.rel.community"),
            LanguageManager.shared.localized("emergency.contacts.rel.hospital"),
            LanguageManager.shared.localized("emergency.contacts.rel.friend"),
            LanguageManager.shared.localized("emergency.contacts.rel.landlord"),
            LanguageManager.shared.localized("emergency.contacts.rel.colleague"),
            LanguageManager.shared.localized("emergency.contacts.rel.other"),
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                // Import from contacts
                Section {
                    Button {
                        showContactPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.scaled(size: 18))
                            Text(LanguageManager.shared.localized("emergency.contacts.fromContacts"))
                                .font(.scaled(size: 14, weight: .medium))
                        }
                        .foregroundStyle(safe)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }

                Section(LanguageManager.shared.localized("emergency.contacts.basicInfo")) {
                    TextField(LanguageManager.shared.localized("emergency.contacts.name"), text: $name)
                    Picker(LanguageManager.shared.localized("emergency.contacts.relationship"), selection: $relationship) {
                        Text(LanguageManager.shared.localized("emergency.contacts.selectRelation")).tag("")
                        ForEach(relationshipOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                }
                Section(LanguageManager.shared.localized("emergency.contacts.contactInfo")) {
                    TextField(LanguageManager.shared.localized("emergency.contacts.phone"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(LanguageManager.shared.localized("emergency.contacts.email"), text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section(LanguageManager.shared.localized("emergency.contacts.addressSection")) {
                    TextField(LanguageManager.shared.localized("emergency.contacts.address"), text: $address)
                }
            }
            .navigationTitle(LanguageManager.shared.localized("emergency.contacts.addTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label(LanguageManager.shared.localized("emergency.contacts.cancel"), systemImage: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let contact = LocalEmergencyContact(
                            id: UUID().uuidString,
                            name: name,
                            relationship: relationship.isEmpty ? LanguageManager.shared.localized("emergency.contacts.rel.other") : relationship,
                            phone: phone,
                            email: email,
                            address: address,
                            countryCode: countryCode
                        )
                        contacts.append(contact)
                        dismiss()
                    } label: {
                        Label(LanguageManager.shared.localized("emergency.contacts.save"), systemImage: "checkmark")
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(safe)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPicker { contact in
                    populateFromContact(contact)
                }
            }
        }
    }

    private func populateFromContact(_ contact: CNContact) {
        name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        if let phoneValue = contact.phoneNumbers.first?.value {
            phone = phoneValue.stringValue
        }
        if let emailValue = contact.emailAddresses.first?.value {
            email = emailValue as String
        }
        if let postal = contact.postalAddresses.first?.value {
            let parts = [postal.street, postal.city, postal.state, postal.postalCode, postal.country]
            address = parts.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }
}

// MARK: - CNContactPicker SwiftUI Wrapper

struct ContactPicker: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void

        init(onSelect: @escaping (CNContact) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }
    }
}

// MARK: - Data Models

struct LocalEmergencyContact: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var relationship: String
    var phone: String
    var email: String
    var address: String
    var countryCode: String
}

struct EmergencyNumber {
    let label: String
    let number: String
    let icon: String
    let color: Color
    let note: String?
}

struct RegionalEmergencyInfo {
    let regionName: String
    let areaCode: String
    /// The first number is the one the app tells people to call in an SOS
    /// (ambulance first where ambulance and police differ).
    let numbers: [EmergencyNumber]

    /// The number shown on SOS screens and the hotline card.
    var primaryNumber: String { numbers.first?.number ?? "112" }

    /// Markets the app is offered in (App Store availability) plus places family
    /// members often are. Unknown regions fall back to 112 (works from most mobiles).
    static let supportedRegions = ["US", "CA", "HK", "MO", "TW", "SG", "AU", "NZ", "MY", "TH", "PH", "JP",
                                   "CN", "GB", "FR", "DE", "KR", "UA"]

    private static func n(_ key: String, _ number: String, _ icon: String, _ color: Color) -> EmergencyNumber {
        EmergencyNumber(label: LanguageManager.shared.localized("emergency.svc.\(key)"), number: number,
                        icon: icon, color: color, note: nil)
    }
    private static let all = "staroflife.fill", amb = "cross.case.fill", pol = "shield.fill",
                       fire = "flame.fill", line = "phone.fill"

    /// Country name in the app's language (e.g. 香港 / Hong Kong / Hong Kong).
    static func regionName(_ code: String) -> String {
        Locale(identifier: LanguageManager.shared.current.rawValue).localizedString(forRegionCode: code) ?? code
    }

    static func forCountry(_ code: String) -> RegionalEmergencyInfo {
        let c = code.uppercased() == "UK" ? "GB" : code.uppercased()
        func info(_ dial: String, _ numbers: [EmergencyNumber]) -> RegionalEmergencyInfo {
            RegionalEmergencyInfo(regionName: regionName(c), areaCode: dial, numbers: numbers)
        }
        switch c {
        // App Store markets
        case "US": return info("+1", [n("all", "911", all, .red), n("poison", "1-800-222-1222", "cross.vial.fill", .purple)])
        case "CA": return info("+1", [n("all", "911", all, .red), n("poison", "1-844-764-7669", "cross.vial.fill", .purple)])
        case "HK": return info("+852", [n("all", "999", all, .red), n("mobile112", "112", line, .gray)])
        case "MO": return info("+853", [n("all", "999", all, .red), n("mobile112", "112", line, .gray)])
        case "TW": return info("+886", [n("ambulanceFire", "119", amb, .red), n("police", "110", pol, .blue),
                                        n("mobile112", "112", line, .gray)])
        case "SG": return info("+65", [n("ambulanceFire", "995", amb, .red), n("police", "999", pol, .blue)])
        case "AU": return info("+61", [n("all", "000", all, .red), n("mobile112", "112", line, .gray),
                                       n("policeNonEmergency", "131 444", pol, .blue)])
        case "NZ": return info("+64", [n("all", "111", all, .red), n("policeNonEmergency", "105", pol, .blue)])
        case "MY": return info("+60", [n("ambulancePolice", "999", all, .red), n("fire", "994", fire, .orange),
                                       n("mobile112", "112", line, .gray)])
        case "TH": return info("+66", [n("ambulance", "1669", amb, .red), n("police", "191", pol, .blue),
                                       n("fire", "199", fire, .orange), n("touristPolice", "1155", pol, .teal)])
        case "PH": return info("+63", [n("all", "911", all, .red)])
        case "JP": return info("+81", [n("ambulanceFire", "119", amb, .red), n("police", "110", pol, .blue),
                                       n("coastGuard", "118", line, .teal)])
        // Where family members often are
        case "CN": return info("+86", [n("ambulance", "120", amb, .red), n("police", "110", pol, .blue),
                                       n("fire", "119", fire, .orange), n("traffic", "122", "car.fill", .gray)])
        case "GB": return info("+44", [n("all", "999", all, .red), n("healthLine", "111", line, .blue)])
        case "FR": return info("+33", [n("ambulance", "15", amb, .red), n("police", "17", pol, .blue),
                                       n("fire", "18", fire, .orange), n("european", "112", all, .red)])
        case "DE": return info("+49", [n("ambulanceFire", "112", amb, .red), n("police", "110", pol, .blue)])
        case "KR": return info("+82", [n("ambulanceFire", "119", amb, .red), n("police", "112", pol, .blue)])
        case "UA": return info("+380", [n("all", "112", all, .red), n("ambulance", "103", amb, .red),
                                        n("police", "102", pol, .blue), n("fire", "101", fire, .orange)])
        default:
            return RegionalEmergencyInfo(regionName: regionName(c), areaCode: "",
                                         numbers: [n("international", "112", all, .red)])
        }
    }
}
