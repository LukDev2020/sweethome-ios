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
exports.logger = void 0;
const functions = __importStar(require("firebase-functions"));
function log(level, service, message, extra) {
    const entry = {
        severity: level,
        message,
        service,
        timestamp: new Date().toISOString(),
        ...extra,
    };
    switch (level) {
        case "ERROR":
            functions.logger.error(entry);
            break;
        case "WARN":
            functions.logger.warn(entry);
            break;
        default:
            functions.logger.info(entry);
    }
}
exports.logger = {
    info: (service, message, extra) => log("INFO", service, message, extra),
    warn: (service, message, extra) => log("WARN", service, message, extra),
    error: (service, message, extra) => log("ERROR", service, message, extra),
    // SOS-specific logging with full context
    sos: (action, sosEventId, extra) => log("INFO", "sos", action, { sosEventId, ...extra }),
    // Auth event logging
    auth: (action, userId, extra) => log("INFO", "auth", action, { userId, ...extra }),
    // Payment event logging
    payment: (action, userId, extra) => log("INFO", "payment", action, { userId, ...extra }),
    // Webhook event logging
    webhook: (source, action, extra) => log("INFO", "webhook", `${source}: ${action}`, extra),
};
//# sourceMappingURL=logger.js.map