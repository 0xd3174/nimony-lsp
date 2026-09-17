#![allow(dead_code)]

use std::collections::HashSet;
use lsp_types::{CompletionItem, CompletionItemKind, InsertTextFormat, Position};
use regex::Regex;

use crate::coords::LineIndex;

const NIM_KEYWORDS: &[&str] = &[
    "addr", "and", "as", "asm", "bind", "block", "break", "case", "cast", "concept", "const",
    "continue", "converter", "defer", "discard", "distinct", "div", "do", "elif", "else", "end",
    "enum", "except", "export", "finally", "for", "from", "func", "if", "import", "in", "include",
    "interface", "is", "isnot", "iterator", "let", "macro", "method", "mixin", "mod", "nil",
    "not", "notin", "object", "of", "or", "out", "proc", "ptr", "raise", "ref", "return", "shl",
    "shr", "static", "template", "try", "type", "using", "var", "when", "while", "xor", "yield",
];

const BUILTIN_TYPES: &[(&str, &str)] = &[
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

struct SnippetDef {
    trigger: &'static str,
    label: &'static str,
    insert_text: &'static str,
    detail: &'static str,
}

const SNIPPETS: &[SnippetDef] = &[
    SnippetDef {
        trigger: "proc",
        label: "proc snippet",
        insert_text: "proc ${1:name}(${2:params}): ${3:ReturnType} =\n  ${0}",
        detail: "Procedure declaration snippet",
    },
    SnippetDef {
        trigger: "func",
        label: "func snippet",
        insert_text: "func ${1:name}(${2:params}): ${3:ReturnType} =\n  ${0}",
        detail: "Side-effect-free function snippet",
    },
    SnippetDef {
        trigger: "iterator",
        label: "iterator snippet",
        insert_text: "iterator ${1:name}(${2:params}): ${3:YieldType} =\n  ${0}",
        detail: "Iterator declaration snippet",
    },
    SnippetDef {
        trigger: "template",
        label: "template snippet",
        insert_text: "template ${1:name}(${2:params}) =\n  ${0}",
        detail: "Inline code template snippet",
    },
    SnippetDef {
        trigger: "type object",
        label: "type ... = object",
        insert_text: "type\n  ${1:Name}* = object\n    ${0}",
        detail: "Object type definition snippet",
    },
    SnippetDef {
        trigger: "type enum",
        label: "type ... = enum",
        insert_text: "type\n  ${1:Name}* = enum\n    ${0}",
        detail: "Enum type definition snippet",
    },
    SnippetDef {
        trigger: "for",
        label: "for loop",
        insert_text: "for ${1:item} in ${2:items}:\n  ${0}",
        detail: "For loop snippet",
    },
    SnippetDef {
        trigger: "while",
        label: "while loop",
        insert_text: "while ${1:condition}:\n  ${0}",
        detail: "While loop snippet",
    },
    SnippetDef {
        trigger: "if",
        label: "if statement",
        insert_text: "if ${1:condition}:\n  ${0}",
        detail: "If statement snippet",
    },
    SnippetDef {
        trigger: "case",
        label: "case statement",
        insert_text: "case ${1:expr}\nof ${2:val}:\n  ${0}\nelse:\n  discard",
        detail: "Case statement snippet",
    },
    SnippetDef {
        trigger: "try",
        label: "try ... except",
        insert_text: "try:\n  ${1}\nexcept ${2:CatchableError} as ${3:e}:\n  ${0}",
        detail: "Try-except error handling snippet",
    },
];

#[derive(Clone)]
pub struct CompletionEngine;

impl CompletionEngine {
    pub fn new() -> Self {
        Self
    }

    pub fn complete(&self, doc_text: &str, pos: Position) -> Vec<CompletionItem> {
        let line_index = LineIndex::new(doc_text);
        let line_0based = (pos.line as usize).min(line_index.line_count().saturating_sub(1));
        let line_str = line_index.line_content(line_0based, doc_text);

        // Extract prefix characters up to pos.character (LSP 0-based UTF-16 code units)
        let mut prefix_chars = Vec::new();
        let mut cur_u16 = 0usize;
        for ch in line_str.chars() {
            if cur_u16 >= pos.character as usize {
                break;
            }
            cur_u16 += ch.len_utf16();
            prefix_chars.push(ch);
        }

        // Extract identifier prefix before cursor
        let prefix: String = prefix_chars
            .into_iter()
            .rev()
            .take_while(|c| c.is_alphanumeric() || *c == '_')
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect();

        let prefix_lower = prefix.to_lowercase();
        let mut items = Vec::new();
        let mut seen_labels = HashSet::new();

        // 1. Keywords
        for &kw in NIM_KEYWORDS {
            if prefix_lower.is_empty() || kw.to_lowercase().starts_with(&prefix_lower) {
                if seen_labels.insert(kw.to_string()) {
                    items.push(CompletionItem {
                        label: kw.to_string(),
                        kind: Some(CompletionItemKind::KEYWORD),
                        detail: Some("Nim keyword".to_string()),
                        ..Default::default()
                    });
                }
            }
        }

        // 2. Built-in types
        for &(ty, desc) in BUILTIN_TYPES {
            if prefix_lower.is_empty() || ty.to_lowercase().starts_with(&prefix_lower) {
                if seen_labels.insert(ty.to_string()) {
                    items.push(CompletionItem {
                        label: ty.to_string(),
                        kind: Some(CompletionItemKind::CLASS),
                        detail: Some(desc.to_string()),
                        ..Default::default()
                    });
                }
            }
        }

        // 3. Snippets
        for snip in SNIPPETS {
            if prefix_lower.is_empty()
                || snip.trigger.to_lowercase().starts_with(&prefix_lower)
                || snip.label.to_lowercase().starts_with(&prefix_lower)
            {
                if seen_labels.insert(snip.label.to_string()) {
                    items.push(CompletionItem {
                        label: snip.label.to_string(),
                        kind: Some(CompletionItemKind::SNIPPET),
                        detail: Some(snip.detail.to_string()),
                        insert_text: Some(snip.insert_text.to_string()),
                        insert_text_format: Some(InsertTextFormat::SNIPPET),
                        ..Default::default()
                    });
                }
            }
        }

        // 4. In-buffer symbol scanner (resilient to syntax errors elsewhere)
        let proc_regex = Regex::new(
            r"(?m)^\s*(?:proc|func|iterator|template|macro|converter|method)\s+([a-zA-Z_][a-zA-Z0-9_]*)\*?\s*(\([^)]*\))?(?:\s*:\s*([a-zA-Z0-9_\[\],\s]+))?",
        )
        .unwrap();

        for cap in proc_regex.captures_iter(doc_text) {
            let name = cap.get(1).map(|m| m.as_str()).unwrap_or("");
            if !name.is_empty()
                && (prefix_lower.is_empty() || name.to_lowercase().starts_with(&prefix_lower))
            {
                if seen_labels.insert(name.to_string()) {
                    let params = cap.get(2).map(|m| m.as_str()).unwrap_or("()");
                    let ret = cap.get(3).map(|m| m.as_str()).unwrap_or("void");
                    let detail = format!("proc{}: {}", params, ret);
                    items.push(CompletionItem {
                        label: name.to_string(),
                        kind: Some(CompletionItemKind::FUNCTION),
                        detail: Some(detail),
                        ..Default::default()
                    });
                }
            }
        }

        let type_regex = Regex::new(
            r"(?m)^\s*([a-zA-Z_][a-zA-Z0-9_]*)\*?(?:\[[^\]]+\])?\s*=\s*(?:object|enum|concept|ref|ptr|distinct)",
        )
        .unwrap();

        for cap in type_regex.captures_iter(doc_text) {
            let name = cap.get(1).map(|m| m.as_str()).unwrap_or("");
            if !name.is_empty()
                && (prefix_lower.is_empty() || name.to_lowercase().starts_with(&prefix_lower))
            {
                if seen_labels.insert(name.to_string()) {
                    items.push(CompletionItem {
                        label: name.to_string(),
                        kind: Some(CompletionItemKind::STRUCT),
                        detail: Some(format!("type {} = object", name)),
                        ..Default::default()
                    });
                }
            }
        }

        let field_regex = Regex::new(
            r"(?m)^\s+([a-zA-Z_][a-zA-Z0-9_]*)\*?\s*:\s*([a-zA-Z0-9_\[\],\s]+)",
        )
        .unwrap();

        for cap in field_regex.captures_iter(doc_text) {
            let name = cap.get(1).map(|m| m.as_str()).unwrap_or("");
            if !name.is_empty()
                && (prefix_lower.is_empty() || name.to_lowercase().starts_with(&prefix_lower))
            {
                if seen_labels.insert(name.to_string()) {
                    let ty = cap.get(2).map(|m| m.as_str()).unwrap_or("auto");
                    let detail = format!("field {}: {}", name, ty.trim());
                    items.push(CompletionItem {
                        label: name.to_string(),
                        kind: Some(CompletionItemKind::FIELD),
                        detail: Some(detail),
                        ..Default::default()
                    });
                }
            }
        }

        let var_regex = Regex::new(
            r"(?m)^\s*(?:var|let|const)\s+([a-zA-Z_][a-zA-Z0-9_]*)\*?(?:\s*:\s*([a-zA-Z0-9_\[\],\s]+))?",
        )
        .unwrap();

        for cap in var_regex.captures_iter(doc_text) {
            let name = cap.get(1).map(|m| m.as_str()).unwrap_or("");
            if !name.is_empty()
                && (prefix_lower.is_empty() || name.to_lowercase().starts_with(&prefix_lower))
            {
                if seen_labels.insert(name.to_string()) {
                    let ty = cap.get(2).map(|m| m.as_str()).unwrap_or("auto");
                    let detail = format!("let {}: {}", name, ty);
                    items.push(CompletionItem {
                        label: name.to_string(),
                        kind: Some(CompletionItemKind::VARIABLE),
                        detail: Some(detail),
                        ..Default::default()
                    });
                }
            }
        }

        items
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keyword_completion() {
        let engine = CompletionEngine::new();
        let doc = "pr";
        let items = engine.complete(doc, Position::new(0, 2));
        assert!(items.iter().any(|i| i.label == "proc"));
    }

    #[test]
    fn test_type_completion() {
        let engine = CompletionEngine::new();
        let doc = "var x: in";
        let items = engine.complete(doc, Position::new(0, 9));
        assert!(items.iter().any(|i| i.label == "int"));
    }

    #[test]
    fn test_in_buffer_proc_completion() {
        let engine = CompletionEngine::new();
        let doc = "proc calculateCustomSum(a, b: int): int = a + b\nlet total = calc";
        let items = engine.complete(doc, Position::new(1, 16));
        assert!(items.iter().any(|i| i.label == "calculateCustomSum"));
    }

    #[test]
    fn test_in_buffer_var_completion() {
        let engine = CompletionEngine::new();
        let doc = "let activeUserCount = 99\nlet users = act";
        let items = engine.complete(doc, Position::new(1, 15));
        assert!(items.iter().any(|i| i.label == "activeUserCount"));
    }

    #[test]
    fn test_multibyte_utf8_completion() {
        let engine = CompletionEngine::new();
        // Line with 2-byte UTF-8 character 'é'
        // 'let café = 1\n' -> 'é' is at UTF-16 index 7, ends at 8
        let doc = "let café = 1\nlet x = pr";
        // Must not panic on character boundary at (0, 8)
        let _items = engine.complete(doc, Position::new(0, 8));

        let items2 = engine.complete(doc, Position::new(1, 10));
        assert!(items2.iter().any(|i| i.label == "proc"));
    }

    #[test]
    fn test_astral_plane_emoji_completion() {
        let engine = CompletionEngine::new();
        // Line with 4-byte astral plane emoji '🚀' (2 UTF-16 code units)
        // 'let 🚀 = 2\n' -> '🚀' occupies UTF-16 units 4..6
        let doc = "let 🚀 = 2\nlet y = in";
        let items = engine.complete(doc, Position::new(0, 6));
        // Should not panic on emoji surrogate boundary
        assert!(!items.is_empty());

        let items2 = engine.complete(doc, Position::new(1, 10));
        assert!(items2.iter().any(|i| i.label == "int"));
    }

    #[test]
    fn test_generic_field_completion() {
        let engine = CompletionEngine::new();
        let doc = "type Box[T] = object\n  item: T\nlet b = Box[int](it";
        let items = engine.complete(doc, Position::new(2, 20));
        assert!(items.iter().any(|i| i.label == "item" && i.kind == Some(CompletionItemKind::FIELD)));
    }
}
