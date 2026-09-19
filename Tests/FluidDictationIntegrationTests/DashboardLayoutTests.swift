@testable import FluidVoice_Debug
import XCTest

@MainActor
final class DashboardLayoutTests: XCTestCase {
    func testLearningCardsAlwaysFillTheirRows() {
        for width in stride(from: 320, through: 2000, by: 1) {
            let layout = DashboardLayout(width: CGFloat(width))
            XCTAssertEqual(4 % layout.lessonColumns, 0)
            if layout.hasActionColumn {
                XCTAssertGreaterThanOrEqual(layout.mainWidth, 640)
            }
        }
    }

    func testBreakpointsAndCappedWidth() {
        XCTAssertFalse(DashboardLayout(width: 1023).hasActionColumn)
        XCTAssertTrue(DashboardLayout(width: 1024).hasActionColumn)
        XCTAssertEqual(DashboardLayout(width: 575).lessonColumns, 1)
        XCTAssertEqual(DashboardLayout(width: 576).lessonColumns, 2)
        XCTAssertEqual(DashboardLayout(width: 1096).lessonColumns, 4)
        XCTAssertFalse(DashboardLayout(width: 675).hasHorizontalActions)
        XCTAssertTrue(DashboardLayout(width: 676).hasHorizontalActions)
        XCTAssertFalse(DashboardLayout(width: 1024).hasHorizontalActions)
        XCTAssertEqual(DashboardLayout(width: 2000).contentWidth, DashboardLayout(width: 1440).contentWidth)
    }

    func testStatisticsDoNotSqueezeFourColumnsBesideActions() {
        XCTAssertEqual(DashboardLayout(width: 1024).statisticColumns(count: 4), 2)
        XCTAssertEqual(DashboardLayout(width: 1440).statisticColumns(count: 4), 4)
        XCTAssertEqual(DashboardLayout(width: 320).statisticColumns(count: 4), 1)
    }
}
