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
exports.reverseGeocode = reverseGeocode;
exports.batchReverseGeocode = batchReverseGeocode;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
// Cache geocoding results to reduce API calls
// Key: lat,lng rounded to 4 decimal places (~11m precision)
const CACHE_COLLECTION = "geocoding_cache";
const CACHE_TTL_DAYS = 30;
/**
 * Reverse geocode coordinates to a human-readable address.
 * Uses Google Maps Geocoding API with caching.
 */
async function reverseGeocode(latitude, longitude) {
    const apiKey = functions.config().google?.maps_api_key;
    if (!apiKey) {
        console.warn("[Geocoding] No API key configured — skipping");
        return null;
    }
    // Round to 4 decimal places for cache key (~11m precision)
    const cacheKey = `${latitude.toFixed(4)},${longitude.toFixed(4)}`;
    // Check cache first
    const cached = await db.collection(CACHE_COLLECTION).doc(cacheKey).get();
    if (cached.exists) {
        const data = cached.data();
        const age = Date.now() - data.cachedAt.toDate().getTime();
        if (age < CACHE_TTL_DAYS * 24 * 60 * 60 * 1000) {
            return data.address;
        }
    }
    try {
        const url = `https://maps.googleapis.com/maps/api/geocode/json` +
            `?latlng=${latitude},${longitude}` +
            `&language=zh-CN` +
            `&result_type=street_address|sublocality|locality` +
            `&key=${apiKey}`;
        const response = await fetch(url);
        const data = await response.json();
        if (data.status !== "OK" || !data.results || data.results.length === 0) {
            console.warn(`[Geocoding] No results for ${cacheKey}: ${data.status}`);
            return null;
        }
        // Extract the most useful address
        const result = data.results[0];
        const address = formatChineseAddress(result);
        // Cache the result
        await db
            .collection(CACHE_COLLECTION)
            .doc(cacheKey)
            .set({
            address,
            fullResult: result.formatted_address,
            latitude,
            longitude,
            cachedAt: admin.firestore.Timestamp.now(),
        });
        return address;
    }
    catch (error) {
        console.error("[Geocoding] API call failed:", error);
        return null;
    }
}
/**
 * Format a Google geocoding result into a concise Chinese address.
 */
function formatChineseAddress(result) {
    const components = result.address_components;
    // Extract relevant parts
    let city = "";
    let district = "";
    let street = "";
    let sublocality = "";
    for (const comp of components) {
        if (comp.types.includes("locality")) {
            city = comp.long_name;
        }
        else if (comp.types.includes("sublocality_level_1") || comp.types.includes("sublocality")) {
            district = comp.long_name;
        }
        else if (comp.types.includes("route")) {
            street = comp.long_name;
        }
        else if (comp.types.includes("neighborhood")) {
            sublocality = comp.long_name;
        }
    }
    // Build concise address: "北京市朝阳区建国路" or "基辅市中心"
    const parts = [city, district, sublocality, street].filter(Boolean);
    return parts.length > 0 ? parts.join("") : result.formatted_address;
}
/**
 * Batch reverse geocode for evidence bundle generation.
 * Only geocodes unique locations to minimize API calls.
 */
async function batchReverseGeocode(locations) {
    const results = new Map();
    // Deduplicate by rounded coordinates
    const unique = new Map();
    for (const loc of locations) {
        const key = `${loc.latitude.toFixed(4)},${loc.longitude.toFixed(4)}`;
        if (!unique.has(key)) {
            unique.set(key, { lat: loc.latitude, lng: loc.longitude });
        }
    }
    // Geocode each unique location (with rate limiting)
    for (const [key, coords] of unique) {
        const address = await reverseGeocode(coords.lat, coords.lng);
        if (address) {
            results.set(key, address);
        }
        // Google Maps rate limit: 50 QPS, add small delay for safety
        await new Promise((resolve) => setTimeout(resolve, 25));
    }
    return results;
}
//# sourceMappingURL=geocoding.js.map