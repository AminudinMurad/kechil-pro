import CoreGraphics
import Foundation

@main
enum ScrollbarGeometryChecks {
    static func main() {
        checkVerticalTrack()
        checkHorizontalTrack()
        checkShortTrackAccessibilityFloor()
        checkValueClamping()
        print("Scrollbar geometry checks passed")
    }

    private static func checkVerticalTrack() {
        let slot = CGRect(x: 2, y: 3, width: 7, height: 700)
        let top = KechilScrollbarGeometry.thumbRect(
            in: slot, value: 0, axis: .vertical)
        let middle = KechilScrollbarGeometry.thumbRect(
            in: slot, value: 0.5, axis: .vertical)
        let bottom = KechilScrollbarGeometry.thumbRect(
            in: slot, value: 1, axis: .vertical)

        require(close(top.height, 70), "vertical thumb must be 10% of its track")
        require(close(top.minY, slot.minY), "value 0 must start at the top")
        require(close(middle.midY, slot.midY), "value 0.5 must centre the thumb")
        require(close(bottom.maxY, slot.maxY), "value 1 must end at the bottom")
    }

    private static func checkHorizontalTrack() {
        let slot = CGRect(x: 4, y: 6, width: 900, height: 7)
        let leading = KechilScrollbarGeometry.thumbRect(
            in: slot, value: 0, axis: .horizontal)
        let trailing = KechilScrollbarGeometry.thumbRect(
            in: slot, value: 1, axis: .horizontal)

        require(close(leading.width, 90), "horizontal thumb must be 10% of its track")
        require(close(leading.minX, slot.minX), "value 0 must start at the leading edge")
        require(close(trailing.maxX, slot.maxX), "value 1 must end at the trailing edge")
    }

    private static func checkShortTrackAccessibilityFloor() {
        let slot = CGRect(x: 0, y: 0, width: 7, height: 180)
        let thumb = KechilScrollbarGeometry.thumbRect(
            in: slot, value: 0.25, axis: .vertical)
        require(
            close(thumb.height, KechilScrollbarGeometry.minimumThumbLength),
            "short tracks must retain a usable thumb")
    }

    private static func checkValueClamping() {
        let slot = CGRect(x: 0, y: 0, width: 7, height: 500)
        let before = KechilScrollbarGeometry.thumbRect(
            in: slot, value: -1, axis: .vertical)
        let after = KechilScrollbarGeometry.thumbRect(
            in: slot, value: 2, axis: .vertical)
        require(close(before.minY, slot.minY), "negative values must clamp to zero")
        require(close(after.maxY, slot.maxY), "values above one must clamp to one")
    }

    private static func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fputs("Scrollbar geometry check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
