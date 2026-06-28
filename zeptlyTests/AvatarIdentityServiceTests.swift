import UIKit
import XCTest
@testable import zeptly

@MainActor
final class AvatarIdentityServiceTests: XCTestCase {
    func testExtractsBoundedAvatarAndFindsUniqueNearDuplicate() throws {
        let first = try XCTUnwrap(AvatarIdentityService.extract(from: screenshot(variant: 0), bounds: bounds))
        let second = try XCTUnwrap(AvatarIdentityService.extract(from: screenshot(variant: 1), bounds: bounds))

        XCTAssertLessThanOrEqual(first.imageData.count, 40_000)
        let storedImage = try XCTUnwrap(UIImage(data: first.imageData))
        XCTAssertEqual(storedImage.size, CGSize(width: 128, height: 128))
        let candidates = [
            stored(id: "same", artifact: first),
            stored(id: "different", artifact: second)
        ]
        let similarities = AvatarIdentityService.similarities(artifact: first, candidates: candidates)

        XCTAssertEqual(AvatarIdentityService.uniqueStrongMatch(in: similarities), "same")
    }

    func testRejectsBoundsOutsideHeader() {
        let invalid = NormalizedAvatarBounds(x: 0.1, y: 0.7, width: 0.16, height: 0.08)
        XCTAssertNil(AvatarIdentityService.extract(from: screenshot(variant: 0), bounds: invalid))
    }

    private var bounds: NormalizedAvatarBounds {
        NormalizedAvatarBounds(x: 0.1, y: 0.1, width: 0.16, height: 0.08)
    }

    private func stored(id: String, artifact: AvatarArtifact) -> StoredAvatarFingerprint {
        StoredAvatarFingerprint(
            chatID: id,
            perceptualHash: artifact.perceptualHash,
            featurePrintData: artifact.featurePrintData,
            quality: artifact.quality,
            revision: artifact.revision
        )
    }

    private func screenshot(variant: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800))
        let image = renderer.image { context in
            UIColor(white: 0.08, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
            let avatar = CGRect(x: 40, y: 80, width: 64, height: 64)
            (variant == 0 ? UIColor.systemBlue : UIColor.systemOrange).setFill()
            context.cgContext.fillEllipse(in: avatar)
            UIColor.white.setFill()
            if variant == 0 {
                context.cgContext.fillEllipse(in: CGRect(x: 56, y: 94, width: 22, height: 22))
                context.fill(CGRect(x: 51, y: 121, width: 38, height: 17))
            } else {
                context.fill(CGRect(x: 48, y: 91, width: 45, height: 12))
                context.fill(CGRect(x: 60, y: 108, width: 18, height: 29))
            }
        }
        return image.pngData()!
    }
}
