import XCTest
@testable import ShouDeng

/// Tests for StoreKitManager's feature gating logic (static methods that don't need StoreKit runtime).
final class StoreKitGatingTests: XCTestCase {

    // MARK: - minimumPlan(for:)

    func testMinimumPlanForBasicSOS() {
        // basic_sos is available on single (first paid tier)
        let plan = StoreKitManager.minimumPlan(for: "basic_sos")
        XCTAssertEqual(plan, "single")
    }

    func testMinimumPlanForDutySchedule() {
        let plan = StoreKitManager.minimumPlan(for: "duty_schedule")
        XCTAssertEqual(plan, "single")
    }

    func testMinimumPlanForExportPDF() {
        let plan = StoreKitManager.minimumPlan(for: "export_pdf")
        XCTAssertEqual(plan, "single")
    }

    func testMinimumPlanForSMSFallback() {
        let plan = StoreKitManager.minimumPlan(for: "sms_fallback")
        XCTAssertEqual(plan, "family")
    }

    func testMinimumPlanForFamilyDashboard() {
        let plan = StoreKitManager.minimumPlan(for: "family_dashboard")
        XCTAssertEqual(plan, "family")
    }

    func testMinimumPlanForPrioritySupport() {
        let plan = StoreKitManager.minimumPlan(for: "priority_support")
        XCTAssertEqual(plan, "ultimate")
    }

    func testMinimumPlanForUnknownFeature() {
        let plan = StoreKitManager.minimumPlan(for: "nonexistent_feature")
        XCTAssertEqual(plan, "ultimate")
    }

    // MARK: - Feature tier progression

    func testFreeFeaturesAreSubsetOfSingle() {
        // Free features: basic_sos, checkin
        // Single should include all free features plus more
        let freeFeatures: Set<String> = ["basic_sos", "checkin"]
        let singleMin = StoreKitManager.minimumPlan(for: "duty_schedule")
        XCTAssertEqual(singleMin, "single")
        // Free features should still map to single (available in single)
        for feature in freeFeatures {
            XCTAssertEqual(StoreKitManager.minimumPlan(for: feature), "single",
                         "\(feature) should be available starting at single tier")
        }
    }

    func testFamilyExclusiveFeatures() {
        // sms_fallback, family_dashboard, location_history_export are family+
        let familyFeatures = ["sms_fallback", "family_dashboard", "location_history_export"]
        for feature in familyFeatures {
            XCTAssertEqual(StoreKitManager.minimumPlan(for: feature), "family",
                         "\(feature) should require family plan")
        }
    }

    func testUltimateExclusiveFeatures() {
        XCTAssertEqual(StoreKitManager.minimumPlan(for: "priority_support"), "ultimate")
    }
}
