import SwiftUI

// MARK: - Biometric Enable Prompt
//
// Shown once after the user's first successful OTP login.
// Asks if they want to enable Face ID / Touch ID for quick app access.

struct BiometricEnablePromptView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var biometric = BiometricAuthManager.shared

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let ink2 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.62)

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: biometric.biometricIconName)
                .font(.scaled(size: 56))
                .foregroundStyle(navy.opacity(0.8))

            Text("启用\(biometric.biometricName)登录？")
                .font(.scaled(size: 20, weight: .bold))
                .foregroundStyle(navy)

            Text("下次打开守灯时，无需输入验证码即可快速登录。\n您可以随时在设置中关闭此功能。")
                .font(.scaled(size: 14))
                .foregroundStyle(ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button {
                    try? biometric.enable()
                    biometric.hasShownPrompt = true
                    isPresented = false
                } label: {
                    Text("启用\(biometric.biometricName)")
                        .font(.scaled(size: 15.5, weight: .medium))
                        .foregroundStyle(cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(navy)
                        )
                }

                Button {
                    biometric.hasShownPrompt = true
                    isPresented = false
                } label: {
                    Text("暂不开启")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .presentationDetents([.medium])
    }
}
