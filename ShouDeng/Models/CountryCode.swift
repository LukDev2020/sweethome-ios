import Foundation

// MARK: - Country Code
//
// Model for international dialing codes with emoji flags.
// Used by CountryCodePicker for phone number input.

struct CountryCode: Identifiable, Hashable {
    var id: String { isoCode }
    let name: String        // English name
    let localName: String   // Native/Chinese name
    let dialCode: String    // e.g. "+86"
    let isoCode: String     // e.g. "CN"
    let flag: String        // Emoji flag

    /// Returns the emoji flag for a 2-letter ISO country code.
    static func flag(for isoCode: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in isoCode.uppercased().unicodeScalars {
            if let s = Unicode.Scalar(base + scalar.value) {
                flag.append(String(s))
            }
        }
        return flag
    }

    /// Detect user's current country from device locale.
    static var deviceDefault: CountryCode {
        let regionCode = Locale.current.region?.identifier ?? "CN"
        return all.first { $0.isoCode == regionCode } ?? all.first { $0.isoCode == "CN" }!
    }

    // MARK: - All Country Codes

    static let all: [CountryCode] = [
        // East Asia
        CountryCode(name: "China", localName: "中国", dialCode: "+86", isoCode: "CN", flag: flag(for: "CN")),
        CountryCode(name: "Hong Kong", localName: "中国香港", dialCode: "+852", isoCode: "HK", flag: flag(for: "HK")),
        CountryCode(name: "Macau", localName: "中国澳门", dialCode: "+853", isoCode: "MO", flag: flag(for: "MO")),
        CountryCode(name: "Taiwan", localName: "中国台湾", dialCode: "+886", isoCode: "TW", flag: flag(for: "TW")),
        CountryCode(name: "Japan", localName: "日本", dialCode: "+81", isoCode: "JP", flag: flag(for: "JP")),
        CountryCode(name: "South Korea", localName: "韩国", dialCode: "+82", isoCode: "KR", flag: flag(for: "KR")),
        CountryCode(name: "Mongolia", localName: "蒙古", dialCode: "+976", isoCode: "MN", flag: flag(for: "MN")),

        // Southeast Asia
        CountryCode(name: "Singapore", localName: "新加坡", dialCode: "+65", isoCode: "SG", flag: flag(for: "SG")),
        CountryCode(name: "Malaysia", localName: "马来西亚", dialCode: "+60", isoCode: "MY", flag: flag(for: "MY")),
        CountryCode(name: "Thailand", localName: "泰国", dialCode: "+66", isoCode: "TH", flag: flag(for: "TH")),
        CountryCode(name: "Vietnam", localName: "越南", dialCode: "+84", isoCode: "VN", flag: flag(for: "VN")),
        CountryCode(name: "Philippines", localName: "菲律宾", dialCode: "+63", isoCode: "PH", flag: flag(for: "PH")),
        CountryCode(name: "Indonesia", localName: "印度尼西亚", dialCode: "+62", isoCode: "ID", flag: flag(for: "ID")),
        CountryCode(name: "Cambodia", localName: "柬埔寨", dialCode: "+855", isoCode: "KH", flag: flag(for: "KH")),
        CountryCode(name: "Myanmar", localName: "缅甸", dialCode: "+95", isoCode: "MM", flag: flag(for: "MM")),
        CountryCode(name: "Laos", localName: "老挝", dialCode: "+856", isoCode: "LA", flag: flag(for: "LA")),
        CountryCode(name: "Brunei", localName: "文莱", dialCode: "+673", isoCode: "BN", flag: flag(for: "BN")),

        // South Asia
        CountryCode(name: "India", localName: "印度", dialCode: "+91", isoCode: "IN", flag: flag(for: "IN")),
        CountryCode(name: "Pakistan", localName: "巴基斯坦", dialCode: "+92", isoCode: "PK", flag: flag(for: "PK")),
        CountryCode(name: "Bangladesh", localName: "孟加拉国", dialCode: "+880", isoCode: "BD", flag: flag(for: "BD")),
        CountryCode(name: "Sri Lanka", localName: "斯里兰卡", dialCode: "+94", isoCode: "LK", flag: flag(for: "LK")),
        CountryCode(name: "Nepal", localName: "尼泊尔", dialCode: "+977", isoCode: "NP", flag: flag(for: "NP")),

        // Oceania
        CountryCode(name: "Australia", localName: "澳大利亚", dialCode: "+61", isoCode: "AU", flag: flag(for: "AU")),
        CountryCode(name: "New Zealand", localName: "新西兰", dialCode: "+64", isoCode: "NZ", flag: flag(for: "NZ")),
        CountryCode(name: "Fiji", localName: "斐济", dialCode: "+679", isoCode: "FJ", flag: flag(for: "FJ")),

        // North America
        CountryCode(name: "United States", localName: "美国", dialCode: "+1", isoCode: "US", flag: flag(for: "US")),
        CountryCode(name: "Canada", localName: "加拿大", dialCode: "+1", isoCode: "CA", flag: flag(for: "CA")),
        CountryCode(name: "Mexico", localName: "墨西哥", dialCode: "+52", isoCode: "MX", flag: flag(for: "MX")),

        // South America
        CountryCode(name: "Brazil", localName: "巴西", dialCode: "+55", isoCode: "BR", flag: flag(for: "BR")),
        CountryCode(name: "Argentina", localName: "阿根廷", dialCode: "+54", isoCode: "AR", flag: flag(for: "AR")),
        CountryCode(name: "Colombia", localName: "哥伦比亚", dialCode: "+57", isoCode: "CO", flag: flag(for: "CO")),
        CountryCode(name: "Chile", localName: "智利", dialCode: "+56", isoCode: "CL", flag: flag(for: "CL")),
        CountryCode(name: "Peru", localName: "秘鲁", dialCode: "+51", isoCode: "PE", flag: flag(for: "PE")),
        CountryCode(name: "Venezuela", localName: "委内瑞拉", dialCode: "+58", isoCode: "VE", flag: flag(for: "VE")),
        CountryCode(name: "Ecuador", localName: "厄瓜多尔", dialCode: "+593", isoCode: "EC", flag: flag(for: "EC")),
        CountryCode(name: "Cuba", localName: "古巴", dialCode: "+53", isoCode: "CU", flag: flag(for: "CU")),

        // Europe - Western
        CountryCode(name: "United Kingdom", localName: "英国", dialCode: "+44", isoCode: "GB", flag: flag(for: "GB")),
        CountryCode(name: "Germany", localName: "德国", dialCode: "+49", isoCode: "DE", flag: flag(for: "DE")),
        CountryCode(name: "France", localName: "法国", dialCode: "+33", isoCode: "FR", flag: flag(for: "FR")),
        CountryCode(name: "Italy", localName: "意大利", dialCode: "+39", isoCode: "IT", flag: flag(for: "IT")),
        CountryCode(name: "Spain", localName: "西班牙", dialCode: "+34", isoCode: "ES", flag: flag(for: "ES")),
        CountryCode(name: "Netherlands", localName: "荷兰", dialCode: "+31", isoCode: "NL", flag: flag(for: "NL")),
        CountryCode(name: "Switzerland", localName: "瑞士", dialCode: "+41", isoCode: "CH", flag: flag(for: "CH")),
        CountryCode(name: "Portugal", localName: "葡萄牙", dialCode: "+351", isoCode: "PT", flag: flag(for: "PT")),
        CountryCode(name: "Belgium", localName: "比利时", dialCode: "+32", isoCode: "BE", flag: flag(for: "BE")),
        CountryCode(name: "Austria", localName: "奥地利", dialCode: "+43", isoCode: "AT", flag: flag(for: "AT")),
        CountryCode(name: "Ireland", localName: "爱尔兰", dialCode: "+353", isoCode: "IE", flag: flag(for: "IE")),
        CountryCode(name: "Luxembourg", localName: "卢森堡", dialCode: "+352", isoCode: "LU", flag: flag(for: "LU")),

        // Europe - Northern
        CountryCode(name: "Sweden", localName: "瑞典", dialCode: "+46", isoCode: "SE", flag: flag(for: "SE")),
        CountryCode(name: "Denmark", localName: "丹麦", dialCode: "+45", isoCode: "DK", flag: flag(for: "DK")),
        CountryCode(name: "Norway", localName: "挪威", dialCode: "+47", isoCode: "NO", flag: flag(for: "NO")),
        CountryCode(name: "Finland", localName: "芬兰", dialCode: "+358", isoCode: "FI", flag: flag(for: "FI")),
        CountryCode(name: "Iceland", localName: "冰岛", dialCode: "+354", isoCode: "IS", flag: flag(for: "IS")),

        // Europe - Eastern
        CountryCode(name: "Russia", localName: "俄罗斯", dialCode: "+7", isoCode: "RU", flag: flag(for: "RU")),
        CountryCode(name: "Poland", localName: "波兰", dialCode: "+48", isoCode: "PL", flag: flag(for: "PL")),
        CountryCode(name: "Ukraine", localName: "乌克兰", dialCode: "+380", isoCode: "UA", flag: flag(for: "UA")),
        CountryCode(name: "Czech Republic", localName: "捷克", dialCode: "+420", isoCode: "CZ", flag: flag(for: "CZ")),
        CountryCode(name: "Romania", localName: "罗马尼亚", dialCode: "+40", isoCode: "RO", flag: flag(for: "RO")),
        CountryCode(name: "Hungary", localName: "匈牙利", dialCode: "+36", isoCode: "HU", flag: flag(for: "HU")),
        CountryCode(name: "Greece", localName: "希腊", dialCode: "+30", isoCode: "GR", flag: flag(for: "GR")),
        CountryCode(name: "Croatia", localName: "克罗地亚", dialCode: "+385", isoCode: "HR", flag: flag(for: "HR")),
        CountryCode(name: "Slovakia", localName: "斯洛伐克", dialCode: "+421", isoCode: "SK", flag: flag(for: "SK")),
        CountryCode(name: "Slovenia", localName: "斯洛文尼亚", dialCode: "+386", isoCode: "SI", flag: flag(for: "SI")),
        CountryCode(name: "Serbia", localName: "塞尔维亚", dialCode: "+381", isoCode: "RS", flag: flag(for: "RS")),
        CountryCode(name: "Bulgaria", localName: "保加利亚", dialCode: "+359", isoCode: "BG", flag: flag(for: "BG")),
        CountryCode(name: "Lithuania", localName: "立陶宛", dialCode: "+370", isoCode: "LT", flag: flag(for: "LT")),
        CountryCode(name: "Latvia", localName: "拉脱维亚", dialCode: "+371", isoCode: "LV", flag: flag(for: "LV")),
        CountryCode(name: "Estonia", localName: "爱沙尼亚", dialCode: "+372", isoCode: "EE", flag: flag(for: "EE")),

        // Middle East
        CountryCode(name: "United Arab Emirates", localName: "阿联酋", dialCode: "+971", isoCode: "AE", flag: flag(for: "AE")),
        CountryCode(name: "Saudi Arabia", localName: "沙特阿拉伯", dialCode: "+966", isoCode: "SA", flag: flag(for: "SA")),
        CountryCode(name: "Turkey", localName: "土耳其", dialCode: "+90", isoCode: "TR", flag: flag(for: "TR")),
        CountryCode(name: "Israel", localName: "以色列", dialCode: "+972", isoCode: "IL", flag: flag(for: "IL")),
        CountryCode(name: "Qatar", localName: "卡塔尔", dialCode: "+974", isoCode: "QA", flag: flag(for: "QA")),
        CountryCode(name: "Kuwait", localName: "科威特", dialCode: "+965", isoCode: "KW", flag: flag(for: "KW")),
        CountryCode(name: "Jordan", localName: "约旦", dialCode: "+962", isoCode: "JO", flag: flag(for: "JO")),
        CountryCode(name: "Lebanon", localName: "黎巴嫩", dialCode: "+961", isoCode: "LB", flag: flag(for: "LB")),

        // Africa
        CountryCode(name: "South Africa", localName: "南非", dialCode: "+27", isoCode: "ZA", flag: flag(for: "ZA")),
        CountryCode(name: "Nigeria", localName: "尼日利亚", dialCode: "+234", isoCode: "NG", flag: flag(for: "NG")),
        CountryCode(name: "Egypt", localName: "埃及", dialCode: "+20", isoCode: "EG", flag: flag(for: "EG")),
        CountryCode(name: "Kenya", localName: "肯尼亚", dialCode: "+254", isoCode: "KE", flag: flag(for: "KE")),
        CountryCode(name: "Morocco", localName: "摩洛哥", dialCode: "+212", isoCode: "MA", flag: flag(for: "MA")),
    ]
}
