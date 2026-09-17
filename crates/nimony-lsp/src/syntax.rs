#![allow(dead_code)]

/// Nim language keywords, sorted alphabetically for binary search.
pub const NIM_KEYWORDS: &[&str] = &[
    "addr", "and", "as", "asm", "bind", "block", "break", "case", "cast", "concept", "const",
    "continue", "converter", "defer", "discard", "distinct", "div", "do", "elif", "else", "end",
    "enum", "except", "export", "finally", "for", "from", "func", "if", "import", "in", "include",
    "interface", "is", "isnot", "iterator", "let", "macro", "method", "mixin", "mod", "nil",
    "not", "notin", "object", "of", "or", "out", "proc", "ptr", "raise", "ref", "return", "shl",
    "shr", "static", "template", "try", "type", "using", "var", "when", "while", "xor", "yield",
];

/// Built-in primitive types and descriptions in Nim.
pub const BUILTIN_TYPES: &[(&str, &str)] = &[
    ("int", "Signed integer (platform word size)"),
    ("int8", "8-bit signed integer"),
    ("int16", "16-bit signed integer"),
    ("int32", "32-bit signed integer"),
    ("int64", "64-bit signed integer"),
    ("uint", "Unsigned integer (platform word size)"),
    ("uint8", "8-bit unsigned integer (byte)"),
    ("uint16", "16-bit unsigned integer"),
    ("uint32", "32-bit unsigned integer"),
    ("uint64", "64-bit unsigned integer"),
    ("float", "64-bit floating point"),
    ("float32", "32-bit floating point"),
    ("float64", "64-bit floating point"),
    ("bool", "Boolean type (true or false)"),
    ("char", "Single ASCII character"),
    ("string", "Dynamically sized UTF-8 string"),
    ("cstring", "Compatibility C-style string (null terminated)"),
    ("pointer", "Untyped raw memory pointer"),
    ("auto", "Compiler type inference"),
    ("any", "Type class matching any type"),
    ("void", "Return type for procs returning nothing"),
    ("typed", "Resolved AST expression (macro parameter)"),
    ("untyped", "Unresolved AST expression (macro/template parameter)"),
    ("typedesc", "Type description meta-type"),
    ("seq", "Dynamically sized homogeneous sequence"),
    ("array", "Fixed-size homogeneous array"),
    ("openArray", "Slice view over seq or array"),
    ("varargs", "Variable length parameter list"),
    ("set", "High-performance bit set"),
    ("tuple", "Anonymous or named tuple type"),
];

/// Checks whether an identifier is a reserved Nim language keyword.
pub fn is_nim_keyword(word: &str) -> bool {
    NIM_KEYWORDS.binary_search(&word).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_nim_keyword() {
        assert!(is_nim_keyword("proc"));
        assert!(is_nim_keyword("let"));
        assert!(is_nim_keyword("yield"));
        assert!(!is_nim_keyword("myVar"));
        assert!(!is_nim_keyword(""));
    }

    #[test]
    fn test_keywords_are_sorted() {
        for window in NIM_KEYWORDS.windows(2) {
            assert!(
                window[0] < window[1],
                "NIM_KEYWORDS not sorted: {} >= {}",
                window[0],
                window[1]
            );
        }
    }
}
