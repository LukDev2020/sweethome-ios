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

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
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
                    Image(systemName: "plus")
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
                Text(String(contact.name.prefix(1)))
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
            UIApplication.shared.open(url)
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
                    Button(LanguageManager.shared.localized("emergency.contacts.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LanguageManager.shared.localized("emergency.contacts.save")) {
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
    let numbers: [EmergencyNumber]

    static func forCountry(_ code: String) -> RegionalEmergencyInfo {
        switch code.uppercased() {
        case "CN":
            return RegionalEmergencyInfo(
                regionName: "中国",
                areaCode: "+86",
                numbers: [
                    EmergencyNumber(label: "急救中心", number: "120", icon: "cross.case.fill", color: .red, note: "急救/医疗"),
                    EmergencyNumber(label: "报警", number: "110", icon: "shield.fill", color: .blue, note: "公安"),
                    EmergencyNumber(label: "火警", number: "119", icon: "flame.fill", color: .orange, note: "消防"),
                    EmergencyNumber(label: "交通事故", number: "122", icon: "car.fill", color: .gray, note: "交警"),
                ]
            )
        case "US":
            return RegionalEmergencyInfo(
                regionName: "美国",
                areaCode: "+1",
                numbers: [
                    EmergencyNumber(label: "Emergency", number: "911", icon: "staroflife.fill", color: .red, note: "Police / Fire / Ambulance"),
                    EmergencyNumber(label: "Poison Control", number: "1-800-222-1222", icon: "cross.vial.fill", color: .purple, note: nil),
                ]
            )
        case "CA":
            return RegionalEmergencyInfo(
                regionName: "加拿大",
                areaCode: "+1",
                numbers: [
                    EmergencyNumber(label: "Emergency", number: "911", icon: "staroflife.fill", color: .red, note: "Police / Fire / Ambulance"),
                    EmergencyNumber(label: "Poison Control", number: "1-844-764-7669", icon: "cross.vial.fill", color: .purple, note: nil),
                ]
            )
        case "GB", "UK":
            return RegionalEmergencyInfo(
                regionName: "英国",
                areaCode: "+44",
                numbers: [
                    EmergencyNumber(label: "Emergency", number: "999", icon: "staroflife.fill", color: .red, note: "Police / Fire / Ambulance"),
                    EmergencyNumber(label: "Non-emergency", number: "111", icon: "phone.fill", color: .blue, note: "NHS helpline"),
                ]
            )
        case "UA":
            return RegionalEmergencyInfo(
                regionName: "乌克兰",
                areaCode: "+380",
                numbers: [
                    EmergencyNumber(label: "Emergency", number: "112", icon: "staroflife.fill", color: .red, note: "通用紧急号码"),
                    EmergencyNumber(label: "Ambulance", number: "103", icon: "cross.case.fill", color: .red, note: "急救"),
                    EmergencyNumber(label: "Police", number: "102", icon: "shield.fill", color: .blue, note: "警察"),
                    EmergencyNumber(label: "Fire", number: "101", icon: "flame.fill", color: .orange, note: "消防"),
                ]
            )
        case "AU":
            return RegionalEmergencyInfo(
                regionName: "澳大利亚",
                areaCode: "+61",
                numbers: [
                    EmergencyNumber(label: "Emergency", number: "000", icon: "staroflife.fill", color: .red, note: "Police / Fire / Ambulance"),
                    EmergencyNumber(label: "Police Assistance", number: "131 444", icon: "shield.fill", color: .blue, note: "非紧急"),
                ]
            )
        case "JP":
            return RegionalEmergencyInfo(
                regionName: "日本",
                areaCode: "+81",
                numbers: [
                    EmergencyNumber(label: "救急", number: "119", icon: "cross.case.fill", color: .red, note: "急救/消防"),
                    EmergencyNumber(label: "警察", number: "110", icon: "shield.fill", color: .blue, note: "警察"),
                ]
            )
        case "KR":
            return RegionalEmergencyInfo(
                regionName: "韩国",
                areaCode: "+82",
                numbers: [
                    EmergencyNumber(label: "Emergency", number: "119", icon: "cross.case.fill", color: .red, note: "急救/消防"),
                    EmergencyNumber(label: "Police", number: "112", icon: "shield.fill", color: .blue, note: "警察"),
                ]
            )
        case "TW":
            return RegionalEmergencyInfo(
                regionName: "台湾",
                areaCode: "+886",
                numbers: [
                    EmergencyNumber(label: "急救/消防", number: "119", icon: "cross.case.fill", color: .red, note: nil),
                    EmergencyNumber(label: "报警", number: "110", icon: "shield.fill", color: .blue, note: nil),
                ]
            )
        case "SG":
            return RegionalEmergencyInfo(
                regionName: "新加坡",
                areaCode: "+65",
                numbers: [
                    EmergencyNumber(label: "Police", number: "999", icon: "shield.fill", color: .blue, note: nil),
                    EmergencyNumber(label: "Ambulance/Fire", number: "995", icon: "cross.case.fill", color: .red, note: nil),
                ]
            )
        case "FR":
            return RegionalEmergencyInfo(
                regionName: "法国",
                areaCode: "+33",
                numbers: [
                    EmergencyNumber(label: "SAMU", number: "15", icon: "cross.case.fill", color: .red, note: "急救"),
                    EmergencyNumber(label: "Police", number: "17", icon: "shield.fill", color: .blue, note: nil),
                    EmergencyNumber(label: "Pompiers", number: "18", icon: "flame.fill", color: .orange, note: "消防"),
                    EmergencyNumber(label: "European", number: "112", icon: "staroflife.fill", color: .red, note: "通用"),
                ]
            )
        case "DE":
            return RegionalEmergencyInfo(
                regionName: "德国",
                areaCode: "+49",
                numbers: [
                    EmergencyNumber(label: "Notruf", number: "112", icon: "staroflife.fill", color: .red, note: "急救/消防"),
                    EmergencyNumber(label: "Polizei", number: "110", icon: "shield.fill", color: .blue, note: "警察"),
                ]
            )
        default:
            // EU default or unknown
            return RegionalEmergencyInfo(
                regionName: code.uppercased(),
                areaCode: "+\(code)",
                numbers: [
                    EmergencyNumber(label: "Emergency", number: "112", icon: "staroflife.fill", color: .red, note: "International emergency number"),
                ]
            )
        }
    }
}
