"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
router.use(auth_1.authMiddleware);
/**
 * GET /v1/coverage/weather
 * Returns weather data for the user's current location.
 * Currently returns sample data; will integrate with weather API in production.
 */
router.get("/weather", async (_req, res) => {
    // Sample weather data — replace with real API integration
    res.json({
        temperature: 12,
        feelsLike: 9,
        condition: "Partly Cloudy",
        icon: "cloud.sun.fill",
        humidity: 62,
        windSpeed: 14,
        windDirection: "NW",
        uvIndex: 3,
        forecast: [
            { day: "Mon", high: 14, low: 6, icon: "sun.max.fill" },
            { day: "Tue", high: 11, low: 4, icon: "cloud.fill" },
            { day: "Wed", high: 9, low: 2, icon: "cloud.rain.fill" },
            { day: "Thu", high: 13, low: 5, icon: "sun.max.fill" },
            { day: "Fri", high: 15, low: 7, icon: "cloud.sun.fill" },
        ],
        updatedAt: new Date().toISOString(),
    });
});
/**
 * GET /v1/coverage/aqi
 * Returns air quality index for the user's location.
 * Currently returns sample data.
 */
router.get("/aqi", async (_req, res) => {
    res.json({
        value: 32,
        label: "Good",
        category: 1,
        dominantPollutant: "PM2.5",
        healthAdvice: "Air quality is considered satisfactory, and air pollution poses little or no risk.",
        updatedAt: new Date().toISOString(),
    });
});
/**
 * GET /v1/coverage/nearby
 * Returns nearby medical facilities.
 * Currently returns sample data; will integrate with Google Places API in production.
 */
router.get("/nearby", async (_req, res) => {
    res.json({
        medical: [
            {
                name: "Toronto General Hospital",
                type: "hospital",
                distance: "1.2 km",
                isOpen: true,
                address: "200 Elizabeth St, Toronto",
                phone: "+14163404800",
            },
            {
                name: "Appletree Medical Clinic",
                type: "clinic",
                distance: "450 m",
                isOpen: true,
                address: "100 King St W, Toronto",
                phone: "+14169671111",
            },
            {
                name: "Shoppers Drug Mart",
                type: "pharmacy",
                distance: "200 m",
                isOpen: true,
                address: "55 Bloor St W, Toronto",
                phone: "+14169221234",
            },
        ],
        updatedAt: new Date().toISOString(),
    });
});
exports.default = router;
//# sourceMappingURL=coverage.js.map