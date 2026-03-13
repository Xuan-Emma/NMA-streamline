import Foundation

/// Protocol adopted by all citation file-format parsers.
///
/// Conforming types declare the file extensions they handle and expose a
/// single `parse(data:)` entry-point that accepts raw bytes, enabling
/// `ImportManager` to dispatch to the correct parser polymorphically
/// without a growing `switch` statement.
///
/// ## Adding a new format
/// 1. Create a parser struct or class.
/// 2. Conform it to `CitationParser` by implementing `supportedExtensions`
///    and `parse(data:)`.
/// 3. Add an instance of the new parser to `ImportManager.parsers`.
protocol CitationParser {
    /// File extensions handled by this parser, lowercased (e.g. `["ris"]`).
    var supportedExtensions: [String] { get }

    /// Parse raw file bytes into an array of `Citation` objects.
    func parse(data: Data) -> [Citation]
}
