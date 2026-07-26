import Foundation

// MARK: - Localization

/// Shorthand for `NSLocalizedString`, because every call site in this app wants
/// exactly one thing from it and the full signature is four arguments of noise.
///
/// Keys are semantic (`menu.newList`), not English source strings. Source-string
/// keys read nicely until someone fixes a typo in the English and silently
/// breaks every other translation; a stable key cannot rot that way. The cost is
/// that `Localizable.strings` has to be maintained by hand rather than generated
/// with `genstrings` — acceptable, since this project has no Xcode build to hang
/// that step off anyway.
///
/// A missing key returns the key itself, which is loud enough to catch in a
/// glance at the running app and harmless if it ever ships.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// `L` plus `String(format:)`, for the handful of strings with a value in them.
///
/// Translators can reorder arguments with `%1$@`-style positional specifiers,
/// which matters for any language that will not tolerate English word order.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

/// Pluralised count strings, resolved through `Localizable.stringsdict`.
///
/// Separate from `L` because it must not fall back to `Localizable.strings`:
/// the whole point is that English needs "1 item" / "2 items" while Chinese
/// needs neither, and only the stringsdict plural rules know which is which.
func LPlural(_ key: String, _ count: Int) -> String {
    String(format: NSLocalizedString(key, comment: ""), count)
}
