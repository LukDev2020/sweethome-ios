import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Family Feed Sync
//
// Pure rules for keeping the family circle's cached posts in step with the server
// (used by AppCoordinator, covered by FamilyFeedTests):
//  - the server's list is the truth; the only local posts kept are this phone's
//    unsent ones (and ones confirmed while the fetch was in flight);
//  - only https:// media links ever go to the server;
//  - photos are downsized before upload.

enum FamilyFeedSync {

    /// Automatic retries per unsent post (after a fetch succeeds); Retry always works.
    static let maxAutomaticAttempts = 5

    /// Server posts, plus local posts the server can't know about yet: unsent ones,
    /// and `keep` (sent while this fetch was in flight). Everything else local is
    /// replaced by the server copy or dropped (deleted by its author). Newest first.
    static func merge(server: [FamilyPost], local: [FamilyPost], keep: Set<String> = []) -> [FamilyPost] {
        let serverIds = Set(server.map(\.id))
        var seen = Set<String>()
        let unique = server.filter { seen.insert($0.id).inserted }
        let carried = local.filter { !serverIds.contains($0.id) && ($0.isUnsent || keep.contains($0.id)) }
        return (unique + carried).sorted { $0.createdAt > $1.createdAt }
    }

    /// Links everyone in the family can open. A file:// path only exists on this phone.
    static func remoteMediaURLs(_ urls: [String]) -> [String] {
        urls.filter { URL(string: $0)?.scheme?.lowercased() == "https" }
    }

    /// A send cut short (app killed or suspended) is shown as not sent.
    static func interruptedSendsFailed(_ posts: [FamilyPost]) -> [FamilyPost] {
        posts.map { post in
            guard post.delivery?.state == .sending else { return post }
            var p = post
            p.delivery?.state = .failed
            return p
        }
    }

    /// Builds before this one kept failed sends as ordinary posts with a random
    /// UUID id (server ids never look like that) and file:// photo paths. Turns
    /// mine into unsent posts so they get a Retry instead of vanishing at the next
    /// refresh. `saveImage` stores a photo still on disk and returns its name.
    static func legacyFailedSends(_ posts: [FamilyPost], myId: String?,
                                  saveImage: (URL) -> String?) -> [FamilyPost] {
        posts.compactMap { post in
            guard post.delivery == nil, UUID(uuidString: post.id) != nil,
                  post.authorId == "local" || (myId != nil && post.authorId == myId) else { return post }
            var p = post
            let local = post.mediaURLs.filter { $0.hasPrefix("file://") }
            p.mediaURLs = remoteMediaURLs(post.mediaURLs)
            let images = local.compactMap { URL(string: $0) }.compactMap(saveImage)
            if p.text.isEmpty && p.mediaURLs.isEmpty && images.isEmpty { return nil }
            p.delivery = FamilyPostDelivery(state: .failed, attempts: 0, pendingImages: images)
            return p
        }
    }
}

// MARK: - Photo downsizing

enum FamilyMediaEncoder {

    /// A JPEG of at most `maxPixelSize` on the long edge, upright, without metadata
    /// (no GPS/EXIF) — typically 0.3–0.8 MB instead of several MB.
    static func jpegForUpload(_ data: Data, maxPixelSize: Int = 1600, quality: Double = 0.7) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
