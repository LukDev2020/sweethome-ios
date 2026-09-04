import SwiftUI

// MARK: - Feature Disclosure Sheet
//
// Shown once per feature on first use. Tracked by AppStorage
// with versioned key — if legal updates the copy, it re-shows.
//
// From revised plan, section 5.3:
//   "其余告知随功能触发，在首次使用时就地弹出"
//   "此种做法可证明用户在具体那一刻被具体告知，
//    举证效力远强于注册时的一次性打包同意。"

struct FeatureDisclosureView: View {
    let feature: DisclaimerCopy.FeatureDisclosure
    let onAcknowledge: () -> Void

    // Design system
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Icon
            Image(systemName: feature.icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(lamp)
                .padding(.bottom, 20)

            // Title
            Text(feature.title)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .padding(.bottom, 14)

            // Body
            Text(feature.body)
                .font(.system(size: 14))
                .foregroundStyle(ink.opacity(0.72))
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            Spacer().frame(height: 32)

            // Button
            Button {
                ConsentLogger.shared.logFeatureDisclosure(feature)
                onAcknowledge()
            } label: {
                Text("我明白了")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ink)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }

            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }
}

// MARK: - View Modifier for Feature Disclosure

struct FeatureDisclosureModifier: ViewModifier {
    let feature: DisclaimerCopy.FeatureDisclosure
    let trigger: Binding<Bool>

    @AppStorage private var acknowledged: Bool
    @State private var showSheet = false

    init(feature: DisclaimerCopy.FeatureDisclosure, trigger: Binding<Bool>) {
        self.feature = feature
        self.trigger = trigger
        self._acknowledged = AppStorage(wrappedValue: false, feature.storageKey)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger.wrappedValue) { _, newValue in
                if newValue && !acknowledged {
                    showSheet = true
                }
            }
            .sheet(isPresented: $showSheet) {
                FeatureDisclosureView(feature: feature) {
                    acknowledged = true
                    showSheet = false
                }
            }
    }
}

extension View {
    /// Attach a feature disclosure sheet that shows on first trigger.
    func featureDisclosure(
        _ feature: DisclaimerCopy.FeatureDisclosure,
        trigger: Binding<Bool>
    ) -> some View {
        modifier(FeatureDisclosureModifier(feature: feature, trigger: trigger))
    }
}
