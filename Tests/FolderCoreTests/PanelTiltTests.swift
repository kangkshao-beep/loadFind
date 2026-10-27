import XCTest
@testable import FolderCore

final class PanelTiltTests: XCTestCase {
    func testStartingAnotherDragWithoutMovementPreservesThePose() {
        let pose = PanelTilt.dragged(from: .neutral, deltaX: 97, deltaY: 80, width: 388, height: 528)
        XCTAssertNotEqual(pose, .neutral)
        XCTAssertEqual(PanelTilt.dragged(from: pose, deltaX: 0, deltaY: 0, width: 388, height: 528), pose)
    }

    func testAFullDragAndRepeatedDragsAccumulateRotation() {
        let turn = PanelTilt.dragged(from: .neutral, deltaX: 388, deltaY: 528, width: 388, height: 528)
        XCTAssertEqual(turn.yawDegrees, 360)
        XCTAssertEqual(turn.pitchDegrees, -360)
        let next = PanelTilt.dragged(from: turn, deltaX: 194, deltaY: 0, width: 388, height: 528)
        XCTAssertEqual(next.yawDegrees, 540)
        XCTAssertEqual(next.pitchDegrees, -360)
        XCTAssertTrue(abs(next.lightHorizontal) <= 1 && abs(next.lightVertical) <= 1)
    }

    func testReversingTheSameDragReturnsToTheOriginalOrientation() {
        let turn = PanelTilt.dragged(from: .neutral, deltaX: 97, deltaY: 80, width: 388, height: 528)
        let reversed = PanelTilt.dragged(from: turn, deltaX: -97, deltaY: -80, width: 388, height: 528)
        XCTAssertEqual(reversed, .neutral)
    }

    func testInvalidDragInputNeverLosesTheCurrentPose() {
        let pose = PanelTilt.dragged(from: .neutral, deltaX: 97, deltaY: 0, width: 388, height: 528)
        XCTAssertEqual(PanelTilt.dragged(from: pose, deltaX: 5, deltaY: 5, width: 0, height: 528), pose)
        XCTAssertEqual(PanelTilt.dragged(from: pose, deltaX: .nan, deltaY: 0, width: 388, height: 528), pose)
        XCTAssertEqual(PanelTilt.dragged(from: pose, deltaX: 0, deltaY: .infinity, width: 388, height: 528), pose)
        XCTAssertEqual(PanelTilt.dragged(from: pose, deltaX: .greatestFiniteMagnitude, deltaY: 0,
                                       width: .leastNonzeroMagnitude, height: 528), pose)
    }
}
