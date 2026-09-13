import SwiftUI
import ContactsUI

// MARK: - Emergency Contacts View
//
// Shows regional emergency numbers based on the protected person's location,
// and allows pre-entering custom local emergency contacts.
// Accessible from the guardian home / member detail.

struct EmergencyContactsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

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
                        .font(.system(size: 28))
                        .foregroundStyle(alert)
                    Text("紧急救援电话")
                        .font(.system(size: 18, weight: .bold))
                    Text("\(personName)所在地区: \(regionInfo.regionName)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Regional emergency numbers
                regionalNumbersPanel

                // Custom local contacts
                localContactsPanel

                // Tip
                Text("紧急情况下，优先拨打当地急救电话。自定义联络人可提前录入邻居、社区工作人员、当地医院等信息。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("紧急电话")
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
        .onAppear { loadCustomContacts() }
        .onChange(of: customContacts) { saveCustomContacts() }
    }

    private var regionInfo: RegionalEmergencyInfo {
        RegionalEmergencyInfo.forCountry(countryCode)
    }

    // MARK: - Regional Numbers Panel

    private var regionalNumbersPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当地紧急号码")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("区号: \(regionInfo.areaCode)")
                    .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                if let note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                callNumber(number)
            } label: {
                Text(number)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(alert)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Local Contacts Panel

    private var localContactsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("自定义紧急联络人")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddContact = true
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                        Text("添加")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(safe)
                }
            }

            if customContacts.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("暂无自定义联络人")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text("可以录入邻居、社区、当地医院等")
                            .font(.system(size: 11))
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(safe)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 13, weight: .medium))
                Text(contact.relationship)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if !contact.address.isEmpty {
                    Text(contact.address)
                        .font(.system(size: 10))
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
                                .font(.system(size: 10))
                            Text(contact.phone)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(safe)
                    }
                }
                if !contact.email.isEmpty {
                    Text(contact.email)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                customContacts.remove(at: index)
            } label: {
                Label("删除", systemImage: "trash")
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

    private let relationshipOptions = ["邻居", "社区工作人员", "当地医院", "朋友", "房东", "同事", "其他"]

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
                                .font(.system(size: 18))
                            Text("从通讯录选择")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(safe)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }

                Section("基本信息") {
                    TextField("姓名", text: $name)
                    Picker("关系", selection: $relationship) {
                        Text("请选择").tag("")
                        ForEach(relationshipOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                }
                Section("联系方式") {
                    TextField("电话 (含区号)", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("电子邮件 (可选)", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("地址 (可选)") {
                    TextField("详细地址", text: $address)
                }
            }
            .navigationTitle("添加紧急联络人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let contact = LocalEmergencyContact(
                            id: UUID().uuidString,
                            name: name,
                            relationship: relationship.isEmpty ? "其他" : relationship,
                            phone: phone,
                            email: email,
                            address: address,
                            countryCode: countryCode
                        )
                        contacts.append(contact)
                        dismiss()
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                    .font(.system(size: 14, weight: .medium))
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
