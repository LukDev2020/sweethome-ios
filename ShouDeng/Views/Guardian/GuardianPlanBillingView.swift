import SwiftUI

// MARK: - Screen B6: Plan & Billing
//
// Design from shoudeng-full-design.html:
//   - Current plan card with line items & monthly total
//   - "What this money did this month" panel
//   - Upsell for family package

struct GuardianPlanBillingView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("方案与账单")
                        .font(.system(size: 20, weight: .bold))
                    Text("按被守护的人计费")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Bill card
                billCard

                // Value recap
                valueRecapPanel

                // Upsell
                upsellCard
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("方案与账单")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Bill Card

    private var billCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("守护团队 + 专业响应")
                .font(.system(size: 14, weight: .semibold))
            Text("下次扣款 10 月 2 日")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            billLine("守护团队 · 全家共用", amount: "¥28")
            billLine("专业响应 · 小雨", amount: "¥98")
            billLine("专业响应 · 奶奶", amount: "¥98")

            Divider().padding(.vertical, 4)

            HStack {
                Text("每月合计")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("¥224")
                    .font(.system(size: 15, weight: .bold, design: .serif))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func billLine(_ label: String, amount: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount)
                .font(.system(size: 13, design: .serif))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Value Recap

    private var valueRecapPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本月这笔钱做了什么")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            valueRow("响应中心待命", value: "720 小时")
            valueRow("专员实际介入", value: "1 次 · 8 月 14 日")
            valueRow("失联预警拦截", value: "3 次")
            valueRow("覆盖的时区缺口", value: "每日 4 小时")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func valueRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Upsell

    private var upsellCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("爸爸和弟弟尚未开通专业响应。四人套餐 ¥288，比单独订阅省 ¥104。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {} label: {
                Text("查看全家套餐")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pro)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(pro.opacity(0.06))
        )
    }
}
