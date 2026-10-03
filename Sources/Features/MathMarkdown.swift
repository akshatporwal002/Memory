import Foundation

/// Preserve TeX before CommonMark interprets its backslashes as escapes.
enum MathMarkdown {
    static func protect(_ source: String) -> String {
        let pattern = #"```[\s\S]*?```|`[^`\n]*`|\\\[([\s\S]*?)\\\]|\$\$([\s\S]*?)\$\$|\\\(([^\n]*?)\\\)|(?<!\\)\$([^$\n]+?)\$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        var result = source
        let ns = source as NSString
        for match in regex.matches(in: source, range: NSRange(location:0,length:ns.length)).reversed() {
            guard let range = Range(match.range, in:result) else { continue }
            for group in 1...4 where match.range(at:group).location != NSNotFound {
                let tex = ns.substring(with:match.range(at:group))
                // Backticks cannot safely be enclosed in a generated code span.
                guard !tex.contains("`") else { break }
                result.replaceSubrange(range,with:group <= 2 ? "\n\n```math\n\(tex)\n```\n\n" : "`ENGRAM_MATH:\(tex)`")
                break
            }
        }
        return result
    }
}
