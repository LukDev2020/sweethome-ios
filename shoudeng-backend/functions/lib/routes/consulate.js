"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const admin = __importStar(require("firebase-admin"));
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
const db = admin.firestore();
// Consulate data — verified from Chinese MFA official websites
// Numbers are consular protection hotlines (领事保护电话)
const CONSULATE_DATA = {
    US: {
        name: "美国",
        flag: "🇺🇸",
        emergency: "911",
        police: "911",
        ambulance: "911",
        embassy: "+1-202-495-2216",
        consulates: [
            { city: "纽约", phone: "+1-212-695-3125" },
            { city: "旧金山", phone: "+1-415-929-6998" },
            { city: "洛杉矶", phone: "+1-213-807-8052" },
            { city: "芝加哥", phone: "+1-312-397-3015" },
        ],
    },
    CA: {
        name: "加拿大",
        flag: "🇨🇦",
        emergency: "911",
        police: "911",
        ambulance: "911",
        embassy: "+1-613-562-1616",
        consulates: [
            { city: "多伦多", phone: "+1-416-594-2308" },
            { city: "温哥华", phone: "+1-604-336-9926" },
        ],
    },
    GB: {
        name: "英国",
        flag: "🇬🇧",
        emergency: "999",
        police: "999",
        ambulance: "999",
        embassy: "+44-20-7299-8439",
        consulates: [
            { city: "曼彻斯特", phone: "+44-161-224-8986" },
            { city: "爱丁堡", phone: "+44-131-337-4449" },
        ],
    },
    AU: {
        name: "澳大利亚",
        flag: "🇦🇺",
        emergency: "000",
        police: "000",
        ambulance: "000",
        embassy: "+61-2-6228-3948",
        consulates: [
            { city: "悉尼", phone: "+61-2-8595-8029" },
            { city: "墨尔本", phone: "+61-3-9804-3271" },
        ],
    },
    JP: {
        name: "日本",
        flag: "🇯🇵",
        emergency: "110",
        police: "110",
        ambulance: "119",
        embassy: "+81-3-3403-3065",
        consulates: [],
    },
    KR: {
        name: "韩国",
        flag: "🇰🇷",
        emergency: "112",
        police: "112",
        ambulance: "119",
        embassy: "+82-2-755-0572",
        consulates: [],
    },
    DE: {
        name: "德国",
        flag: "🇩🇪",
        emergency: "112",
        police: "110",
        ambulance: "112",
        embassy: "+49-30-27588-551",
        consulates: [
            { city: "法兰克福", phone: "+49-69-6953-8633" },
            { city: "慕尼黑", phone: "+49-89-7244-98146" },
        ],
    },
    FR: {
        name: "法国",
        flag: "🇫🇷",
        emergency: "112",
        police: "17",
        ambulance: "15",
        embassy: "+33-1-5375-8921",
        consulates: [{ city: "里昂", phone: "+33-7-8562-0931" }],
    },
    NZ: {
        name: "新西兰",
        flag: "🇳🇿",
        emergency: "111",
        police: "111",
        ambulance: "111",
        embassy: "+64-4-499-5022",
        consulates: [{ city: "奥克兰", phone: "+64-9-525-1200" }],
    },
    SG: {
        name: "新加坡",
        flag: "🇸🇬",
        emergency: "999",
        police: "999",
        ambulance: "995",
        embassy: "+65-6471-2117",
        consulates: [],
    },
    TH: {
        name: "泰国",
        flag: "🇹🇭",
        emergency: "191",
        police: "191",
        ambulance: "1669",
        embassy: "+66-2-245-7010",
        consulates: [{ city: "清迈", phone: "+66-53-280618" }],
    },
    MY: {
        name: "马来西亚",
        flag: "🇲🇾",
        emergency: "999",
        police: "999",
        ambulance: "999",
        embassy: "+60-3-2164-5301",
        consulates: [],
    },
    UA: {
        name: "乌克兰",
        flag: "🇺🇦",
        emergency: "112",
        police: "102",
        ambulance: "103",
        embassy: "+380-50-355-0734",
        consulates: [],
    },
};
/**
 * GET /v1/consulate
 * List all countries with consulate data.
 */
router.get("/", (_req, res) => {
    const list = Object.entries(CONSULATE_DATA).map(([code, data]) => ({
        countryCode: code,
        name: data.name,
        flag: data.flag,
        emergency: data.emergency,
        police: data.police,
        ambulance: data.ambulance,
        embassy: data.embassy,
        consulates: data.consulates,
    }));
    res.json(list);
});
/**
 * GET /v1/consulate/:countryCode
 * Get consulate info for a specific country.
 */
router.get("/:countryCode", (req, res) => {
    const code = req.params.countryCode.toUpperCase();
    const data = CONSULATE_DATA[code];
    if (!data) {
        res.status(404).json({ error: "Country not found" });
        return;
    }
    res.json({
        countryCode: code,
        ...data,
    });
});
/**
 * GET /v1/consulate/selected/me
 * Get user's selected (pinned) hotline.
 */
router.get("/selected/me", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    try {
        const doc = await db.collection("selected_hotlines").doc(uid).get();
        if (!doc.exists) {
            res.json(null);
            return;
        }
        res.json(doc.data());
    }
    catch (error) {
        console.error("[Consulate] get selected error:", error);
        res.status(500).json({ error: "Failed to get selected hotline" });
    }
});
/**
 * PUT /v1/consulate/selected
 * Save user's selected hotline — shown persistently on home screen.
 */
router.put("/selected", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    const { countryCode, countryName, flag, emergency, embassy, selectedPhone, selectedLabel } = req.body;
    if (!countryCode) {
        res.status(400).json({ error: "countryCode is required" });
        return;
    }
    try {
        await db
            .collection("selected_hotlines")
            .doc(uid)
            .set({
            userId: uid,
            countryCode,
            countryName: countryName || null,
            flag: flag || null,
            emergency: emergency || null,
            embassy: embassy || null,
            selectedPhone: selectedPhone || null,
            selectedLabel: selectedLabel || null,
            updatedAt: admin.firestore.Timestamp.now(),
        }, { merge: true });
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Consulate] save selected error:", error);
        res.status(500).json({ error: "Failed to save selected hotline" });
    }
});
/**
 * DELETE /v1/consulate/selected
 * Remove user's selected hotline.
 */
router.delete("/selected", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    try {
        await db.collection("selected_hotlines").doc(uid).delete();
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Consulate] delete selected error:", error);
        res.status(500).json({ error: "Failed to remove selected hotline" });
    }
});
exports.default = router;
//# sourceMappingURL=consulate.js.map