import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() {
        print("  PASS  \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)")
    }
}

@main
struct PasteURLChecks {
    static func main() throws {
        print("\nPaste URL and direct-download contract")

        let videoURL = URL(string: "https://cdn.example.com/media/clip.mp4?token=abc")!
        check(PasteURLService.source(from: videoURL.absoluteString) == .remote(videoURL),
              "HTTPS video URL resolves as a remote source")

        let imageURL = URL(string: "http://images.example.com/photo.webp")!
        check(PasteURLService.source(from: imageURL.absoluteString) == .remote(imageURL),
              "HTTP image URL resolves as a remote source")

        check(PasteURLService.validationMessage(for: videoURL.absoluteString,
                                                media: .video) == nil,
              "direct video URL is accepted before response validation")
        check(PasteURLService.validationMessage(for: imageURL.absoluteString,
                                                media: .image) == nil,
              "direct image URL is accepted before response validation")
        check(PasteURLService.source(from: "ftp://example.com/file.mp4") == nil,
              "non-HTTP remote schemes are rejected")

        let youtubeMessage = "YouTube links aren't supported. Download videos you own through YouTube Studio or Google Takeout, then add the local file."
        let metaMessage = "Facebook and Instagram links aren't supported. Export media you own through Meta Accounts Center, then add the local file."
        check(PasteURLService.validationMessage(
                for: "https://www.youtube.com/watch?v=example", media: .video) == youtubeMessage,
              "YouTube watch pages direct owners to official export tools")
        check(PasteURLService.validationMessage(
                for: "https://youtu.be/example", media: .video) == youtubeMessage,
              "YouTube short links are rejected")
        check(PasteURLService.validationMessage(
                for: "https://rr1---sn.example.googlevideo.com/videoplayback", media: .video) == youtubeMessage,
              "YouTube delivery hosts cannot bypass the safe-import boundary")
        check(PasteURLService.validationMessage(
                for: "https://www.facebook.com/reel/123", media: .video) == metaMessage,
              "Facebook video pages direct owners to Accounts Center")
        check(PasteURLService.validationMessage(
                for: "https://www.instagram.com/reel/example/", media: .video) == metaMessage,
              "Instagram Reel pages direct owners to Accounts Center")
        check(PasteURLService.validationMessage(
                for: "https://scontent.example.fbcdn.net/video.mp4", media: .video) == metaMessage,
              "Meta delivery hosts cannot bypass the safe-import boundary")
        check(PasteURLService.validationMessage(
                for: "https://youtube.com.example.net/video.mp4", media: .video) == nil,
              "domain-suffix matching does not reject lookalike hosts")
        check(PasteURLService.validationMessage(
                for: "https://media.example.com/video.mp4", media: .video) == nil,
              "ordinary direct media hosts remain supported")

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kechil-paste-url-checks-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let movie = folder.appendingPathComponent("local.mp4")
        let image = folder.appendingPathComponent("local.png")
        try Data([0, 1, 2]).write(to: movie)
        try Data([3, 4, 5]).write(to: image)

        check(PasteURLService.source(from: movie.path) == .local(movie.standardizedFileURL),
              "absolute local path resolves without a download")
        check(PasteURLService.validationMessage(for: movie.path, media: .video) == nil,
              "supported local video remains accepted")
        check(PasteURLService.validationMessage(for: image.path, media: .image) == nil,
              "supported local image remains accepted")
        check(PasteURLService.validationMessage(for: image.path, media: .video) != nil,
              "image cannot enter a video queue")
        check(PasteURLService.validationMessage(for: movie.path, media: .image) != nil,
              "video cannot enter an image queue")
        check(DirectMediaDownloadService.maximumBytes == 20_000_000_000,
              "direct downloads have a deterministic 20 GB ceiling")

        if failures == 0 {
            print("\nALL PASTE URL CHECKS PASSED")
        } else {
            print("\n\(failures) PASTE URL CHECK(S) FAILED")
            exit(1)
        }
    }
}
