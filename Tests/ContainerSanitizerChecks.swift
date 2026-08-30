import Foundation

@main
enum ContainerSanitizerChecks {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let result = MediaContainerSanitizer.neutralizeC2PABMFFBoxes(in: input)
        expect(result.count > 0, "nested/top-level C2PA box is found")
        expect(result.data.count == input.count, "C2PA neutralization preserves file length")
        expect(result.data.range(of: Data("openai-test-genid".utf8)) == nil,
               "C2PA payload is zeroed")
        print("Container sanitizer checks passed (\(result.count) box)" )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        print("PASS: \(message)")
    }
}
