import XCTest
@testable import Vinyl

final class LayoutMetricsTests: XCTestCase {
    func testPortraitPhone() {
        let m = LayoutMetrics(size: CGSize(width: 440, height: 956))
        XCTAssertEqual(m.shape, .portrait)
        XCTAssertTrue(m.showsProgress)
        XCTAssertLessThanOrEqual(m.recordSide * 2, 440)
    }
    func testWideCanvas() {
        let m = LayoutMetrics(size: CGSize(width: 1100, height: 700))
        XCTAssertEqual(m.shape, .wide)
        XCTAssertLessThanOrEqual(m.recordSide, 700 * 0.7)
    }
    func testOuterSideways() {
        let m = LayoutMetrics(size: CGSize(width: 700, height: 400))
        XCTAssertEqual(m.shape, .outerSideways)
        XCTAssertFalse(m.showsProgress)
        XCTAssertLessThanOrEqual(m.recordSide, 400)
    }
    func testDiscTintStaysDark() {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { c in
            UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let ui = UIColor(PlayerModel.discTint(img))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertLessThan(r, 0.3)
    }
}
