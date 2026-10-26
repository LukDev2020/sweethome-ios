import SwiftUI

struct ProfileHeaderView: View {
    let name: String
    let email: String
    let initial: String
    let role: String
    let roleColor: Color
    let bloodType: String?
    let allergy: String?
    let iceContact: String?
    var onEdit: (() -> Void)?

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)

    var body: some View {
        VStack(spacing: 12) {
            // Top row: avatar + info + edit
            HStack(spacing: 14) {
                // Avatar with camera
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(roleColor)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Text(initial)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Circle()
                        .fill(offWhiteBg)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 8))
                                .foregroundColor(ink.opacity(0.55))
                        )
                        .overlay(Circle().stroke(offWhiteBg, lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(ink)
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundColor(ink.opacity(0.55))
                    Text(role)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(roleColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(roleColor.opacity(0.1))
                        .cornerRadius(6)
                        .padding(.top, 2)
                }

                Spacer()

                if let onEdit {
                    Button(action: onEdit) {
                        Text("Edit")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(red: 27/255, green: 94/255, blue: 189/255))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 27/255, green: 94/255, blue: 189/255).opacity(0.08))
                            .cornerRadius(8)
                    }
                }
            }

            // Medical summary row
            if bloodType != nil || allergy != nil || iceContact != nil {
                HStack(spacing: 0) {
                    if let bt = bloodType {
                        medStat("Blood", value: bt, color: ink)
                        divider
                    }
                    if let al = allergy {
                        medStat("Allergy", value: al, color: alert)
                        divider
                    }
                    if let ice = iceContact {
                        medStat("ICE", value: ice, color: safe)
                    }
                    Spacer()
                }
                .padding(10)
                .background(offWhiteBg)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ink.opacity(0.06), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(offWhiteBg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(ink.opacity(0.06), lineWidth: 1)
        )
    }

    private func medStat(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(ink.opacity(0.3))
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
        }
        .frame(minWidth: 50)
    }

    private var divider: some View {
        Rectangle()
            .fill(ink.opacity(0.06))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }
}
