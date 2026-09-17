"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
/**
 * Multi-language emergency phrases and consulate data.
 * All data is static — no Firestore needed.
 */
// Emergency phrases by language code
const EMERGENCY_PHRASES = {
    en: {
        helpText: "I need help. Please call emergency services.",
        emergencyNumber: "911",
        language: "English",
    },
    zh: {
        helpText: "我需要帮助，请拨打急救电话。",
        emergencyNumber: "120",
        language: "中文",
    },
    ja: {
        helpText: "助けてください。救急車を呼んでください。",
        emergencyNumber: "119",
        language: "日本語",
    },
    ko: {
        helpText: "도움이 필요합니다. 응급 서비스에 전화해 주세요.",
        emergencyNumber: "119",
        language: "한국어",
    },
    fr: {
        helpText: "J'ai besoin d'aide. Appelez les secours s'il vous plaît.",
        emergencyNumber: "15",
        language: "Français",
    },
    de: {
        helpText: "Ich brauche Hilfe. Bitte rufen Sie den Notdienst.",
        emergencyNumber: "112",
        language: "Deutsch",
    },
    es: {
        helpText: "Necesito ayuda. Por favor llame a emergencias.",
        emergencyNumber: "112",
        language: "Español",
    },
    pt: {
        helpText: "Preciso de ajuda. Por favor, ligue para a emergência.",
        emergencyNumber: "112",
        language: "Português",
    },
    it: {
        helpText: "Ho bisogno di aiuto. Per favore chiamate il pronto soccorso.",
        emergencyNumber: "118",
        language: "Italiano",
    },
    ru: {
        helpText: "Мне нужна помощь. Пожалуйста, вызовите скорую помощь.",
        emergencyNumber: "103",
        language: "Русский",
    },
    ar: {
        helpText: "أحتاج مساعدة. من فضلك اتصل بالطوارئ.",
        emergencyNumber: "911",
        language: "العربية",
    },
    th: {
        helpText: "ฉันต้องการความช่วยเหลือ กรุณาโทรเรียกรถพยาบาล",
        emergencyNumber: "1669",
        language: "ไทย",
    },
    vi: {
        helpText: "Tôi cần giúp đỡ. Xin hãy gọi cấp cứu.",
        emergencyNumber: "115",
        language: "Tiếng Việt",
    },
    ms: {
        helpText: "Saya perlukan bantuan. Sila hubungi perkhidmatan kecemasan.",
        emergencyNumber: "999",
        language: "Bahasa Melayu",
    },
    uk: {
        helpText: "Мені потрібна допомога. Будь ласка, викличте швидку.",
        emergencyNumber: "103",
        language: "Українська",
    },
    tr: {
        helpText: "Yardıma ihtiyacım var. Lütfen acil servisi arayın.",
        emergencyNumber: "112",
        language: "Türkçe",
    },
    pl: {
        helpText: "Potrzebuję pomocy. Proszę zadzwonić po pogotowie.",
        emergencyNumber: "112",
        language: "Polski",
    },
    nl: {
        helpText: "Ik heb hulp nodig. Bel alstublieft de hulpdiensten.",
        emergencyNumber: "112",
        language: "Nederlands",
    },
    hi: {
        helpText: "मुझे मदद चाहिए। कृपया आपातकालीन सेवाओं को बुलाएं।",
        emergencyNumber: "112",
        language: "हिन्दी",
    },
    sv: {
        helpText: "Jag behöver hjälp. Ring ambulansen tack.",
        emergencyNumber: "112",
        language: "Svenska",
    },
};
// Consulate & emergency contacts by country code
const CONSULATE_DATA = {
    US: {
        countryName: "美国",
        emergencyNumber: "911",
        policeNumber: "911",
        ambulanceNumber: "911",
        chineseEmbassy: "+1-202-495-2266",
        chineseConsulate: ["+1-212-244-9392", "+1-312-453-0210", "+1-415-852-5900", "+1-713-520-1462", "+1-213-807-8088"],
    },
    CA: {
        countryName: "加拿大",
        emergencyNumber: "911",
        policeNumber: "911",
        ambulanceNumber: "911",
        chineseEmbassy: "+1-613-789-3434",
        chineseConsulate: ["+1-416-964-7260", "+1-604-734-0704", "+1-514-419-6748"],
    },
    GB: {
        countryName: "英国",
        emergencyNumber: "999",
        policeNumber: "999",
        ambulanceNumber: "999",
        chineseEmbassy: "+44-20-7299-4049",
    },
    AU: {
        countryName: "澳大利亚",
        emergencyNumber: "000",
        policeNumber: "000",
        ambulanceNumber: "000",
        chineseEmbassy: "+61-2-6228-3999",
        chineseConsulate: ["+61-3-9822-0604", "+61-2-8595-8002"],
    },
    JP: {
        countryName: "日本",
        emergencyNumber: "110",
        policeNumber: "110",
        ambulanceNumber: "119",
        chineseEmbassy: "+81-3-3403-3388",
    },
    KR: {
        countryName: "韩国",
        emergencyNumber: "112",
        policeNumber: "112",
        ambulanceNumber: "119",
        chineseEmbassy: "+82-2-738-1038",
    },
    DE: {
        countryName: "德国",
        emergencyNumber: "112",
        policeNumber: "110",
        ambulanceNumber: "112",
        chineseEmbassy: "+49-30-27588-0",
    },
    FR: {
        countryName: "法国",
        emergencyNumber: "112",
        policeNumber: "17",
        ambulanceNumber: "15",
        chineseEmbassy: "+33-1-4936-2790",
    },
    NZ: {
        countryName: "新西兰",
        emergencyNumber: "111",
        policeNumber: "111",
        ambulanceNumber: "111",
        chineseEmbassy: "+64-4-474-9631",
    },
    SG: {
        countryName: "新加坡",
        emergencyNumber: "999",
        policeNumber: "999",
        ambulanceNumber: "995",
        chineseEmbassy: "+65-6471-2117",
    },
    TH: {
        countryName: "泰国",
        emergencyNumber: "191",
        policeNumber: "191",
        ambulanceNumber: "1669",
        chineseEmbassy: "+66-2-245-7044",
    },
    MY: {
        countryName: "马来西亚",
        emergencyNumber: "999",
        policeNumber: "999",
        ambulanceNumber: "999",
        chineseEmbassy: "+60-3-2163-6815",
    },
    UA: {
        countryName: "乌克兰",
        emergencyNumber: "112",
        policeNumber: "102",
        ambulanceNumber: "103",
        chineseEmbassy: "+380-44-253-1354",
    },
};
/**
 * GET /v1/emergency-text/:lang
 * Get emergency help text in a specific language.
 * No auth required — must work when phone is partially accessible.
 */
router.get("/:lang", (req, res) => {
    const { lang } = req.params;
    const phrase = EMERGENCY_PHRASES[lang] || EMERGENCY_PHRASES["en"];
    res.json(phrase);
});
/**
 * GET /v1/emergency-text
 * Get all available emergency phrases.
 */
router.get("/", (_req, res) => {
    res.json(EMERGENCY_PHRASES);
});
/**
 * GET /v1/consulate/:countryCode
 * Get consulate and emergency contacts for a country.
 */
router.get("/consulate/:countryCode", auth_1.authMiddleware, (req, res) => {
    const { countryCode } = req.params;
    const data = CONSULATE_DATA[countryCode.toUpperCase()];
    if (!data) {
        res.status(404).json({ error: "Country not found" });
        return;
    }
    res.json(data);
});
/**
 * GET /v1/consulate
 * Get all available consulate data.
 */
router.get("/consulate", auth_1.authMiddleware, (_req, res) => {
    const countries = Object.entries(CONSULATE_DATA).map(([code, data]) => ({
        countryCode: code,
        countryName: data.countryName,
        emergencyNumber: data.emergencyNumber,
    }));
    res.json(countries);
});
exports.default = router;
//# sourceMappingURL=emergencyText.js.map