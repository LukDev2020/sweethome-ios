import XCTest
import SwiftUI
@testable import ShouDeng

final class GlobeLabelTests: XCTestCase {
    private func pin(_ label: String, _ lat: Double, _ lng: Double, me: Bool = false) -> GlobeMapView.Pin {
        .init(label: label, latitude: lat, longitude: lng, color: .orange, isMe: me)
    }

    func testPeopleInSameCityShareOneLabel() {
        let groups = GlobeMapView.labelGroups([
            pin("You · Toronto, Canada", 43.65, -79.38, me: true),
            pin("Xiulan Chen · Chengdu", 30.6586, 104.0647),
            pin("Jianguo Chen · Chengdu", 30.6705, 104.0435),
        ])
        XCTAssertEqual(groups.map(\.label), ["You · Toronto, Canada", "Xiulan Chen, Jianguo Chen · Chengdu"])
        XCTAssertEqual(groups[1].pinIndices, [1, 2])
    }

    func testThreeOrMoreNamesCollapse() {
        XCTAssertEqual(GlobeMapView.mergedLabel(["A · Paris", "B · Paris", "C · Paris"]), "A +2 · Paris")
        XCTAssertEqual(GlobeMapView.mergedLabel(["A", "B"]), "A, B")
        XCTAssertEqual(GlobeMapView.mergedLabel(["A · Paris", "B · Versailles"]), "A, B")
    }

    func testDistantCitiesStaySeparate() {
        let groups = GlobeMapView.labelGroups([pin("Kevin · Shanghai", 31.23, 121.47), pin("Mom · Chengdu", 30.66, 104.06)])
        XCTAssertEqual(groups.count, 2)
    }
}
