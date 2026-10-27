import XCTest
@testable import FolderCore

final class CardGeometryTests: XCTestCase {
    func testAFullTurnShowsFrontEdgeBackEdgeAndFront() {
        for (yaw, front, back) in [(0.0, true, false), (90, false, false), (180, false, true), (270, false, false), (360, true, false)] {
            let card = CardGeometry(width: 340, height: 480, pitch: 0, yaw: yaw)
            XCTAssertEqual(card.frontVisible, front, "yaw \(yaw)")
            XCTAssertEqual(card.backVisible, back, "yaw \(yaw)")
        }
    }

    func testEdgeOnViewHasRealThickness() {
        let card = CardGeometry(width: 340, height: 480, depth: 18, pitch: 0, yaw: 90)
        let front = card.project(x: 0, y: 0, z: 9)
        let back = card.project(x: 0, y: 0, z: -9)
        XCTAssertGreaterThan(abs(front.x - back.x), 8)
    }

    func testRotatingEveryDirectionKeepsAllCornersInsideTheStage() {
        for pitch in stride(from: -360.0, through: 360, by: 30) {
            for yaw in stride(from: -360.0, through: 360, by: 45) {
                let card = CardGeometry(width: 340, height: 480, pitch: pitch, yaw: yaw)
                for x in [-170.0, 170] {
                    for y in [-240.0, 240] {
                        for z in [-9.0, 9] {
                            let point = card.project(x: x, y: y, z: z)
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                            XCTAssertGreaterThanOrEqual(point.x, -0.000001)
                            XCTAssertLessThanOrEqual(point.x, 340.000001)
                            XCTAssertGreaterThanOrEqual(point.y, -0.000001)
                            XCTAssertLessThanOrEqual(point.y, 480.000001)
                        }
                    }
                }
            }
        }
    }

    func testInteractiveFaceProjectionMatchesTheSolidGeometry() {
        for pitch in [-320.0, -135, -60, 0, 57, 135, 360] {
            for yaw in [-180.0, -90, 0, 27, 90, 179, 360] {
                let card = CardGeometry(width: 340, height: 480, pitch: pitch, yaw: yaw)
                for back in [false, true] {
                    let transform = card.faceProjection(back: back)
                    let sign = back ? -1.0 : 1.0
                    for x in [0.0, 170, 340] {
                        for y in [0.0, 240, 480] {
                            let actual = transform.project(x: x, y: y)
                            let expected = card.project(x: sign * (x - 170), y: y - 240, z: sign * 9)
                            XCTAssertEqual(actual.x, expected.x, accuracy: 0.000001)
                            XCTAssertEqual(actual.y, expected.y, accuracy: 0.000001)
                        }
                    }
                }
            }
        }
    }

    func testFullRevolutionAndInvalidInputsStayStable() {
        let flat = CardGeometry(width: 340, height: 480, pitch: 0, yaw: 0)
        let turned = CardGeometry(width: 340, height: 480, pitch: 360, yaw: 360)
        XCTAssertEqual(flat.project(x: 170, y: 240, z: 9), turned.project(x: 170, y: 240, z: 9))
        let invalid = CardGeometry(width: 0, height: .nan, pitch: .nan, yaw: .infinity)
        let point = invalid.project(x: 0, y: 0, z: 0)
        XCTAssertTrue(point.x.isFinite && point.y.isFinite)
    }
}
