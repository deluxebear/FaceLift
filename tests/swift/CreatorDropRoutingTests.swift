// Compiled together with Model/CreatorDropRouting.swift by tests/test_creator_drop_routing.py.
import Foundation

func expect(_ actual: CreatorDropAction, _ expected: CreatorDropAction, _ name: String) {
    if actual != expected {
        print("FAIL \(name): got \(actual), expected \(expected)")
        exit(1)
    }
    print("ok \(name)")
}

@main
struct CreatorDropRoutingTests {
    static func main() {
        // Poster Slice: dropping anywhere on the canvas, including on a key, sets the poster.
        expect(creatorDropAction(isIndividualKeys: false, keyDigit: "5"), .setPoster, "poster mode, on key")
        expect(creatorDropAction(isIndividualKeys: false, keyDigit: nil), .setPoster, "poster mode, off key")
        // Individual Keys: a key takes the image; a miss must not replace the hidden poster.
        expect(creatorDropAction(isIndividualKeys: true, keyDigit: "5"), .setKey("5"), "keys mode, on key")
        expect(creatorDropAction(isIndividualKeys: true, keyDigit: nil), .reject, "keys mode, off key")
    }
}
