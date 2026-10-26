import SwiftUI

struct ReactionBarView: View {
    let postId: String
    @State private var reactions: [String: Bool] = ["thumbsup": false, "heart": false, "hands.clap": false]

    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    private let emojiMap: [(key: String, emoji: String)] = [
        ("thumbsup", "\u{1F44D}"),
        ("heart", "\u{2764}\u{FE0F}"),
        ("hands.clap", "\u{1F44F}")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(emojiMap, id: \.key) { item in
                Button {
                    withAnimation(.spring(response: 0.2)) {
                        reactions[item.key]?.toggle()
                    }
                } label: {
                    Text(item.emoji)
                        .font(.system(size: 14))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(reactions[item.key] == true
                                      ? lamp.opacity(0.12)
                                      : Color(red: 251/255, green: 248/255, blue: 241/255))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(reactions[item.key] == true
                                        ? lamp.opacity(0.3)
                                        : Color(red: 18/255, green: 32/255, blue: 58/255).opacity(0.06),
                                        lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.key)
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}
