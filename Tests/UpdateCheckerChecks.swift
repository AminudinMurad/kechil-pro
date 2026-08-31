import Foundation

@main
enum UpdateCheckerChecks {
    static func main() {
        var checks = 0

        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        expect(UpdateChecker.isNewer("1.0.1", than: "1.0.0"), "a newer patch release is detected")
        expect(UpdateChecker.isNewer("v1.2.0", than: "1.1.9"), "v-prefixed release tags are compared")
        expect(UpdateChecker.isNewer("1.0.10", than: "1.0.9"), "numeric components are not compared lexically")
        expect(!UpdateChecker.isNewer("1.0", than: "1.0.0"), "missing trailing components are treated as zero")
        expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.1"), "an older release is not marked newer")
        expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"), "the same release is up to date")
        print("ALL UPDATE CHECKER CHECKS PASSED (\(checks) assertions)")
    }
}
