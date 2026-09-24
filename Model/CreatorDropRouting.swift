/// What an image dropped on the Theme Creator canvas should change.
enum CreatorDropAction: Equatable {
    case setPoster
    case setKey(String)
    case reject
}

/// Routes a Creator canvas drop. `keyDigit` is the keypad key under the
/// drop point, or nil when the drop lands between keys or off the keypad.
func creatorDropAction(isIndividualKeys: Bool, keyDigit: String?) -> CreatorDropAction {
    guard isIndividualKeys else { return .setPoster }
    // A miss must not silently replace the poster, which is hidden in this mode.
    return keyDigit.map { .setKey($0) } ?? .reject
}
