import XCTest
@testable import SleepTracker

final class RingBufferTests: XCTestCase {
    func testLatestReturnsFewerWhenNotFull() {
        var buffer = RingBuffer(capacity: 10)
        buffer.write([1, 2, 3])

        XCTAssertEqual(buffer.latest(5), [1, 2, 3])
        XCTAssertEqual(buffer.count, 3)
    }

    func testWrapAround() {
        var buffer = RingBuffer(capacity: 5)
        buffer.write([1, 2, 3, 4, 5, 6, 7])

        XCTAssertEqual(buffer.latest(5), [3, 4, 5, 6, 7])
        XCTAssertEqual(buffer.latest(2), [6, 7])
    }

    func testWriteLargerThanCapacityKeepsTail() {
        var buffer = RingBuffer(capacity: 3)
        buffer.write((1...10).map { Float($0) })

        XCTAssertEqual(buffer.latest(3), [8, 9, 10])
    }

    func testMultipleSmallWritesWrap() {
        var buffer = RingBuffer(capacity: 4)
        buffer.write([1, 2])
        buffer.write([3, 4])
        buffer.write([5])

        XCTAssertEqual(buffer.latest(4), [2, 3, 4, 5])
    }

    func testClearResetsCount() {
        var buffer = RingBuffer(capacity: 4)
        buffer.write([1, 2, 3])
        buffer.clear()

        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.latest(3), [])
    }

    func testNonPositiveRequestReturnsEmpty() {
        var buffer = RingBuffer(capacity: 4)
        buffer.write([1, 2, 3])

        XCTAssertEqual(buffer.latest(0), [])
        XCTAssertEqual(buffer.latest(-1), [])
    }
}
