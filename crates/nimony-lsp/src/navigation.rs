#![allow(dead_code)]

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

use lsp_types::{
    DocumentHighlight, DocumentHighlightKind, GotoDefinitionResponse, Hover, HoverContents,
    Location, MarkupContent, MarkupKind, Position, Range, Url,
};
use regex::Regex;

use crate::coords::{self, LineIndex};

static NAV_COUNTER: AtomicU64 = AtomicU64::new(0);

/// RAII guard for temporary shadow files during navigation queries on dirty/untitled buffers.
pub struct NavShadowGuard {
    path: PathBuf,
}

impl NavShadowGuard {
    pub fn create(dir: &Path, content: &str) -> std::io::Result<Self> {
        let unique_id = format!(
            "{:x}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        );
        let suffix = &unique_id[unique_id.len().saturating_sub(8)..];
        let count = NAV_COUNTER.fetch_add(1, Ordering::Relaxed);
        let file_name = format!("tmp_nav_{}_{}.nim", suffix, count);
        let path = dir.join(file_name);
        std::fs::write(&path, content)?;
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for NavShadowGuard {
    fn drop(&mut self) {
        if self.path.exists() {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}

#[derive(Clone)]
pub struct NavigationEngine {
    pub nimony_bin: PathBuf,
}

impl NavigationEngine {
    pub fn new(nimony_bin: PathBuf) -> Self {
        Self { nimony_bin }
    }

    /// textDocument/definition
    pub fn goto_definition(
        &self,
        doc_path: &Path,
        doc_uri: &Url,
        doc_text: &str,
        pos: Position,
        project_root: Option<&Path>,
        cancel: Option<&Arc<AtomicBool>>,
    ) -> Result<Option<GotoDefinitionResponse>, String> {
        if let Some(c) = cancel {
            if c.load(Ordering::SeqCst) {
                return Ok(None);
            }
        }

        let line_index = LineIndex::new(doc_text);
        let line_0based = (pos.line as usize).min(line_index.line_count().saturating_sub(1));
        let line_str = line_index.line_content(line_0based, doc_text);

        let (word, _word_range) = match get_word_at_pos(line_str, pos.line, pos.character as usize)
        {
            Some(w) => w,
            None => return Ok(None),
        };

        // Whitespace, numbers, and language keywords do not have symbol definitions
        if word.chars().all(|c| c.is_ascii_digit()) || is_nim_keyword(word) {
            return Ok(None);
        }

        // Determine working directory and target file (shadow file if buffer is dirty)
        let dir = doc_path.parent().unwrap_or(Path::new("."));
        let is_disk_synced = doc_path.exists()
            && std::fs::read_to_string(doc_path)
                .map(|s| s == doc_text)
                .unwrap_or(false);

        let (_shadow_guard, target_file, shadow_name) = if is_disk_synced {
            (None, doc_path.to_path_buf(), None)
        } else {
            let guard = NavShadowGuard::create(dir, doc_text)
                .map_err(|e| format!("Failed to create nav shadow file: {}", e))?;
            let name = guard
                .path()
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            let p = guard.path().to_path_buf();
            (Some(guard), p, Some(name))
        };

        let cwd = match project_root {
            Some(root) if target_file.starts_with(root) => root,
            _ => dir,
        };

        let rel_target = target_file.strip_prefix(cwd).unwrap_or(&target_file);
        let (nim_line, nim_col) = coords::lsp_to_nimony_1based(&line_index, doc_text, pos);

        let def_arg = format!("--def:{},{},{}", rel_target.display(), nim_line, nim_col);

        let output = Command::new(&self.nimony_bin)
            .arg("check")
            .arg("--silentMake")
            .arg("--isMain")
            .arg(&def_arg)
            .arg(rel_target)
            .current_dir(cwd)
            .output();

        if let Ok(out) = output {
            let stdout_str = String::from_utf8_lossy(&out.stdout);
            for line in stdout_str.lines() {
                if line.starts_with("def\t") {
                    if let Some((loc, _sym)) = parse_tsv_line(
                        line,
                        cwd,
                        doc_uri,
                        shadow_name.as_deref(),
                        doc_path,
                        doc_text,
                    ) {
                        return Ok(Some(GotoDefinitionResponse::Scalar(loc)));
                    }
                }
            }
        }

        // Fallback to in-buffer declaration scanner for local variables/parameters
        if let Some(loc) = find_in_buffer_declaration(doc_text, doc_uri, word) {
            return Ok(Some(GotoDefinitionResponse::Scalar(loc)));
        }

        Ok(None)
    }

    /// textDocument/references
    pub fn find_references(
        &self,
        doc_path: &Path,
        doc_uri: &Url,
        doc_text: &str,
        pos: Position,
        include_declaration: bool,
        project_root: Option<&Path>,
        cancel: Option<&Arc<AtomicBool>>,
    ) -> Result<Option<Vec<Location>>, String> {
        if let Some(c) = cancel {
            if c.load(Ordering::SeqCst) {
                return Ok(None);
            }
        }

        let line_index = LineIndex::new(doc_text);
        let line_0based = (pos.line as usize).min(line_index.line_count().saturating_sub(1));
        let line_str = line_index.line_content(line_0based, doc_text);

        let (word, _word_range) = match get_word_at_pos(line_str, pos.line, pos.character as usize)
        {
            Some(w) => w,
            None => return Ok(None),
        };

        if word.chars().all(|c| c.is_ascii_digit()) || is_nim_keyword(word) {
            return Ok(None);
        }

        let dir = doc_path.parent().unwrap_or(Path::new("."));
        let is_disk_synced = doc_path.exists()
            && std::fs::read_to_string(doc_path)
                .map(|s| s == doc_text)
                .unwrap_or(false);

        let (_shadow_guard, target_file, shadow_name) = if is_disk_synced {
            (None, doc_path.to_path_buf(), None)
        } else {
            let guard = NavShadowGuard::create(dir, doc_text)
                .map_err(|e| format!("Failed to create nav shadow file: {}", e))?;
            let name = guard
                .path()
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            let p = guard.path().to_path_buf();
            (Some(guard), p, Some(name))
        };

        let cwd = match project_root {
            Some(root) if target_file.starts_with(root) => root,
            _ => dir,
        };

        let rel_target = target_file.strip_prefix(cwd).unwrap_or(&target_file);
        let (nim_line, nim_col) = coords::lsp_to_nimony_1based(&line_index, doc_text, pos);

        let usages_arg = format!("--usages:{},{},{}", rel_target.display(), nim_line, nim_col);

        let mut locations = Vec::new();
        let mut def_loc: Option<Location> = None;

        // Query definition site if needed
        let def_arg = format!("--def:{},{},{}", rel_target.display(), nim_line, nim_col);
        if let Ok(def_out) = Command::new(&self.nimony_bin)
            .arg("check")
            .arg("--silentMake")
            .arg("--isMain")
            .arg(&def_arg)
            .arg(rel_target)
            .current_dir(cwd)
            .output()
        {
            let def_str = String::from_utf8_lossy(&def_out.stdout);
            for line in def_str.lines() {
                if line.starts_with("def\t") {
                    if let Some((loc, _sym)) = parse_tsv_line(
                        line,
                        cwd,
                        doc_uri,
                        shadow_name.as_deref(),
                        doc_path,
                        doc_text,
                    ) {
                        def_loc = Some(loc.clone());
                        if include_declaration {
                            locations.push(loc);
                        }
                    }
                }
            }
        }

        // Query usages
        if let Ok(out) = Command::new(&self.nimony_bin)
            .arg("check")
            .arg("--silentMake")
            .arg("--isMain")
            .arg(&usages_arg)
            .arg(rel_target)
            .current_dir(cwd)
            .output()
        {
            let stdout_str = String::from_utf8_lossy(&out.stdout);
            for line in stdout_str.lines() {
                if line.starts_with("use\t") {
                    if let Some((loc, _sym)) = parse_tsv_line(
                        line,
                        cwd,
                        doc_uri,
                        shadow_name.as_deref(),
                        doc_path,
                        doc_text,
                    ) {
                        locations.push(loc);
                    }
                }
            }
        }

        // Fallback: in-buffer token search
        if locations.is_empty() {
            let in_buf = find_in_buffer_references(doc_text, doc_uri, word, include_declaration);
            locations.extend(in_buf);
        } else if !include_declaration {
            if let Some(def) = def_loc {
                locations.retain(|l| {
                    !(l.uri == def.uri
                        && l.range.start.line == def.range.start.line
                        && l.range.start.character == def.range.start.character)
                });
            }
        }

        // Deduplicate
        let mut seen = HashSet::new();
        locations.retain(|loc| {
            let key = (
                loc.uri.as_str().to_string(),
                loc.range.start.line,
                loc.range.start.character,
            );
            seen.insert(key)
        });

        if locations.is_empty() {
            Ok(None)
        } else {
            Ok(Some(locations))
        }
    }

    /// textDocument/hover
    pub fn hover(
        &self,
        doc_path: &Path,
        doc_uri: &Url,
        doc_text: &str,
        pos: Position,
        project_root: Option<&Path>,
        cancel: Option<&Arc<AtomicBool>>,
    ) -> Result<Option<Hover>, String> {
        if let Some(c) = cancel {
            if c.load(Ordering::SeqCst) {
                return Ok(None);
            }
        }

        let line_index = LineIndex::new(doc_text);
        let line_0based = (pos.line as usize).min(line_index.line_count().saturating_sub(1));
        let line_str = line_index.line_content(line_0based, doc_text);

        let (word, word_range) = match get_word_at_pos(line_str, pos.line, pos.character as usize)
        {
            Some(w) => w,
            None => return Ok(None),
        };

        // Tier 1: Static keyword and built-in type documentation
        if let Some(static_doc) = get_static_keyword_or_type_doc(word) {
            return Ok(Some(Hover {
                contents: HoverContents::Markup(MarkupContent {
                    kind: MarkupKind::Markdown,
                    value: static_doc,
                }),
                range: Some(word_range),
            }));
        }

        // Tier 2: User symbol definition signature and doc comments
        if let Ok(Some(GotoDefinitionResponse::Scalar(loc))) =
            self.goto_definition(doc_path, doc_uri, doc_text, pos, project_root, cancel)
        {
            let target_content = if loc.uri == *doc_uri {
                Some(doc_text.to_string())
            } else if let Ok(path) = loc.uri.to_file_path() {
                std::fs::read_to_string(path).ok()
            } else {
                None
            };

            if let Some(content) = target_content {
                let target_index = LineIndex::new(&content);
                let def_line = loc.range.start.line as usize;
                let sig_raw = target_index.line_content(def_line, &content).trim();
                let sig = sig_raw.trim_end_matches('=').trim_end_matches(':').trim();

                // Extract doc comments (## lines) following the declaration
                let mut doc_comments = Vec::new();
                for next_line in (def_line + 1)..target_index.line_count() {
                    let next_str = target_index.line_content(next_line, &content).trim();
                    if let Some(doc_line) = next_str.strip_prefix("##") {
                        doc_comments.push(doc_line.trim().to_string());
                    } else if next_str.is_empty() {
                        continue;
                    } else {
                        break;
                    }
                }

                let markdown = if doc_comments.is_empty() {
                    format!("```nim\n{}\n```", sig)
                } else {
                    format!("```nim\n{}\n```\n\n---\n{}", sig, doc_comments.join("\n"))
                };

                return Ok(Some(Hover {
                    contents: HoverContents::Markup(MarkupContent {
                        kind: MarkupKind::Markdown,
                        value: markdown,
                    }),
                    range: Some(word_range),
                }));
            }
        }

        // Tier 3: In-buffer local declaration extraction
        if let Some(local_doc) = extract_in_buffer_hover(doc_text, word) {
            return Ok(Some(Hover {
                contents: HoverContents::Markup(MarkupContent {
                    kind: MarkupKind::Markdown,
                    value: local_doc,
                }),
                range: Some(word_range),
            }));
        }

        Ok(None)
    }

    /// textDocument/documentHighlight
    pub fn document_highlight(
        &self,
        doc_text: &str,
        pos: Position,
    ) -> Result<Option<Vec<DocumentHighlight>>, String> {
        let line_index = LineIndex::new(doc_text);
        let line_0based = (pos.line as usize).min(line_index.line_count().saturating_sub(1));
        let line_str = line_index.line_content(line_0based, doc_text);

        let (word, _word_range) = match get_word_at_pos(line_str, pos.line, pos.character as usize)
        {
            Some(w) => w,
            None => return Ok(None),
        };

        if is_nim_keyword(word) || word.chars().all(|c| c.is_ascii_digit()) {
            return Ok(None);
        }

        let pattern = format!(r"\b{}\b", regex::escape(word));
        let regex = match Regex::new(&pattern) {
            Ok(r) => r,
            Err(_) => return Ok(None),
        };

        let mut highlights = Vec::new();

        for line_idx in 0..line_index.line_count() {
            let text_line = line_index.line_content(line_idx, doc_text);
            for m in regex.find_iter(text_line) {
                let byte_start = m.start();
                let byte_end = m.end();

                let mut cur_byte = 0usize;
                let mut utf16_start = 0usize;
                let mut utf16_end = 0usize;

                for ch in text_line.chars() {
                    if cur_byte < byte_start {
                        utf16_start += ch.len_utf16();
                    }
                    if cur_byte < byte_end {
                        utf16_end += ch.len_utf16();
                    }
                    cur_byte += ch.len_utf8();
                }

                let range = Range::new(
                    Position::new(line_idx as u32, utf16_start as u32),
                    Position::new(line_idx as u32, utf16_end as u32),
                );

                let is_write = is_declaration_line(text_line, word);
                let kind = if is_write {
                    DocumentHighlightKind::WRITE
                } else {
                    DocumentHighlightKind::READ
                };

                highlights.push(DocumentHighlight {
                    range,
                    kind: Some(kind),
                });
            }
        }

        if highlights.is_empty() {
            Ok(None)
        } else {
            Ok(Some(highlights))
        }
    }
}

fn is_declaration_line(line: &str, word: &str) -> bool {
    let trimmed = line.trim();
    if trimmed.starts_with("var ")
        || trimmed.starts_with("let ")
        || trimmed.starts_with("const ")
        || trimmed.starts_with("type ")
        || trimmed.starts_with("proc ")
        || trimmed.starts_with("func ")
        || trimmed.starts_with("iterator ")
        || trimmed.starts_with("template ")
        || trimmed.starts_with("macro ")
    {
        let head = trimmed.split_whitespace().nth(1).unwrap_or("");
        head.starts_with(word)
    } else {
        false
    }
}

pub fn get_word_at_pos(line_str: &str, line: u32, target_utf16_col: usize) -> Option<(&str, Range)> {
    let mut current_utf16 = 0usize;
    let mut chars_with_col = Vec::new();

    for (byte_idx, ch) in line_str.char_indices() {
        let utf16_start = current_utf16;
        current_utf16 += ch.len_utf16();
        chars_with_col.push((byte_idx, ch, utf16_start, current_utf16));
    }

    let mut found_idx = None;
    for (i, &(_byte_idx, ch, u16_start, u16_end)) in chars_with_col.iter().enumerate() {
        if target_utf16_col >= u16_start && target_utf16_col < u16_end {
            if ch.is_alphanumeric() || ch == '_' {
                found_idx = Some(i);
            }
            break;
        }
    }

    if found_idx.is_none() && target_utf16_col == current_utf16 && !chars_with_col.is_empty() {
        let last_idx = chars_with_col.len() - 1;
        let (_, ch, _, _) = chars_with_col[last_idx];
        if ch.is_alphanumeric() || ch == '_' {
            found_idx = Some(last_idx);
        }
    }

    let idx = found_idx?;

    let mut start_idx = idx;
    while start_idx > 0 {
        let (_, ch, _, _) = chars_with_col[start_idx - 1];
        if ch.is_alphanumeric() || ch == '_' {
            start_idx -= 1;
        } else {
            break;
        }
    }

    let mut end_idx = idx;
    while end_idx + 1 < chars_with_col.len() {
        let (_, ch, _, _) = chars_with_col[end_idx + 1];
        if ch.is_alphanumeric() || ch == '_' {
            end_idx += 1;
        } else {
            break;
        }
    }

    let byte_start = chars_with_col[start_idx].0;
    let byte_end = if end_idx + 1 < chars_with_col.len() {
        chars_with_col[end_idx + 1].0
    } else {
        line_str.len()
    };

    let u16_start = chars_with_col[start_idx].2;
    let u16_end = chars_with_col[end_idx].3;

    let word = &line_str[byte_start..byte_end];
    let range = Range::new(
        Position::new(line, u16_start as u32),
        Position::new(line, u16_end as u32),
    );
    Some((word, range))
}

pub fn is_nim_keyword(word: &str) -> bool {
    matches!(
        word,
        "addr"
            | "and"
            | "as"
            | "asm"
            | "bind"
            | "block"
            | "break"
            | "case"
            | "cast"
            | "concept"
            | "const"
            | "continue"
            | "converter"
            | "defer"
            | "discard"
            | "distinct"
            | "div"
            | "do"
            | "elif"
            | "else"
            | "end"
            | "enum"
            | "except"
            | "export"
            | "finally"
            | "for"
            | "from"
            | "func"
            | "if"
            | "import"
            | "in"
            | "include"
            | "interface"
            | "is"
            | "isnot"
            | "iterator"
            | "let"
            | "macro"
            | "method"
            | "mixin"
            | "mod"
            | "nil"
            | "not"
            | "notin"
            | "object"
            | "of"
            | "or"
            | "out"
            | "proc"
            | "ptr"
            | "raise"
            | "ref"
            | "return"
            | "shl"
            | "shr"
            | "static"
            | "template"
            | "try"
            | "type"
            | "using"
            | "var"
            | "when"
            | "while"
            | "xor"
            | "yield"
    )
}

pub fn get_static_keyword_or_type_doc(word: &str) -> Option<String> {
    match word {
        "proc" => Some("```nim\nkeyword proc\n```\n\nDeclares a procedure (function) in Nim.".to_string()),
        "func" => Some("```nim\nkeyword func\n```\n\nDeclares a side-effect-free function in Nim.".to_string()),
        "iterator" => Some("```nim\nkeyword iterator\n```\n\nDeclares an iterator yielding elements in loops.".to_string()),
        "template" => Some("```nim\nkeyword template\n```\n\nDeclares an inline AST substitution template.".to_string()),
        "macro" => Some("```nim\nkeyword macro\n```\n\nDeclares a compile-time AST transformation macro.".to_string()),
        "type" => Some("```nim\nkeyword type\n```\n\nStarts a type definition block.".to_string()),
        "var" => Some("```nim\nkeyword var\n```\n\nDeclares mutable variables or mutable parameters.".to_string()),
        "let" => Some("```nim\nkeyword let\n```\n\nDeclares single-assignment immutable variables.".to_string()),
        "const" => Some("```nim\nkeyword const\n```\n\nDeclares compile-time constant values.".to_string()),
        "discard" => Some("```nim\nkeyword discard\n```\n\nExplicitly ignores the return value of an expression.".to_string()),
        "import" => Some("```nim\nkeyword import\n```\n\nImports symbols from an external module.".to_string()),
        "export" => Some("```nim\nkeyword export\n```\n\nRe-exports imported symbols to module consumers.".to_string()),
        "return" => Some("```nim\nkeyword return\n```\n\nExits the current procedure with optional return value.".to_string()),
        "yield" => Some("```nim\nkeyword yield\n```\n\nYields a value from an iterator.".to_string()),
        "if" => Some("```nim\nkeyword if\n```\n\nConditional branching expression/statement.".to_string()),
        "elif" => Some("```nim\nkeyword elif\n```\n\nElse-if conditional branch.".to_string()),
        "else" => Some("```nim\nkeyword else\n```\n\nDefault conditional or case branch.".to_string()),
        "when" => Some("```nim\nkeyword when\n```\n\nCompile-time conditional branching.".to_string()),
        "while" => Some("```nim\nkeyword while\n```\n\nWhile loop executing while condition is true.".to_string()),
        "for" => Some("```nim\nkeyword for\n```\n\nIteration loop over an iterable sequence or iterator.".to_string()),
        "case" => Some("```nim\nkeyword case\n```\n\nPattern matching branching on expressions.".to_string()),
        "of" => Some("```nim\nkeyword of\n```\n\nBranch condition inside case statement.".to_string()),
        "try" => Some("```nim\nkeyword try\n```\n\nStarts an exception handling block.".to_string()),
        "except" => Some("```nim\nkeyword except\n```\n\nCatches specific exception types.".to_string()),
        "finally" => Some("```nim\nkeyword finally\n```\n\nAlways executes after try/except block.".to_string()),
        "defer" => Some("```nim\nkeyword defer\n```\n\nDefers execution of a block until scope exit.".to_string()),
        "block" => Some("```nim\nkeyword block\n```\n\nCreates a named or anonymous lexical scope.".to_string()),
        "break" => Some("```nim\nkeyword break\n```\n\nBreaks out of a loop or named block.".to_string()),
        "continue" => Some("```nim\nkeyword continue\n```\n\nContinues to next loop iteration.".to_string()),
        "raise" => Some("```nim\nkeyword raise\n```\n\nRaises an exception.".to_string()),
        "int" => Some("```nim\ntype int\n```\n\nSigned integer matching platform pointer size (32 or 64-bit).".to_string()),
        "int8" => Some("```nim\ntype int8\n```\n\n8-bit signed integer.".to_string()),
        "int16" => Some("```nim\ntype int16\n```\n\n16-bit signed integer.".to_string()),
        "int32" => Some("```nim\ntype int32\n```\n\n32-bit signed integer.".to_string()),
        "int64" => Some("```nim\ntype int64\n```\n\n64-bit signed integer.".to_string()),
        "uint" => Some("```nim\ntype uint\n```\n\nUnsigned integer matching platform pointer size.".to_string()),
        "uint8" => Some("```nim\ntype uint8\n```\n\n8-bit unsigned integer (byte).".to_string()),
        "uint16" => Some("```nim\ntype uint16\n```\n\n16-bit unsigned integer.".to_string()),
        "uint32" => Some("```nim\ntype uint32\n```\n\n32-bit unsigned integer.".to_string()),
        "uint64" => Some("```nim\ntype uint64\n```\n\n64-bit unsigned integer.".to_string()),
        "float" => Some("```nim\ntype float\n```\n\n64-bit floating point number.".to_string()),
        "float32" => Some("```nim\ntype float32\n```\n\n32-bit floating point number.".to_string()),
        "float64" => Some("```nim\ntype float64\n```\n\n64-bit floating point number.".to_string()),
        "bool" => Some("```nim\ntype bool\n```\n\nBoolean type (`true` or `false`).".to_string()),
        "char" => Some("```nim\ntype char\n```\n\nSingle ASCII character type.".to_string()),
        "string" => Some("```nim\ntype string\n```\n\nMutable UTF-8 encoded string with value semantics.".to_string()),
        "cstring" => Some("```nim\ntype cstring\n```\n\nCompatibility C-style null-terminated string.".to_string()),
        "pointer" => Some("```nim\ntype pointer\n```\n\nRaw untyped memory pointer.".to_string()),
        "auto" => Some("```nim\ntype auto\n```\n\nCompiler automatic type deduction.".to_string()),
        "void" => Some("```nim\ntype void\n```\n\nReturn type for procedures that return nothing.".to_string()),
        _ => None,
    }
}

pub fn parse_tsv_line(
    line: &str,
    base_dir: &Path,
    current_doc_uri: &Url,
    shadow_filename: Option<&str>,
    current_doc_path: &Path,
    current_doc_text: &str,
) -> Option<(Location, String)> {
    let parts: Vec<&str> = line.split('\t').collect();
    if parts.len() < 8 {
        return None;
    }

    let tag = parts[0];
    if tag != "def" && tag != "use" {
        return None;
    }

    let raw_sym = parts[2];
    let target_file_str = parts[5];
    let line_1based: u32 = parts[6].parse().ok()?;
    let col_0based: u32 = parts[7].parse().ok()?;

    let target_file = Path::new(target_file_str);
    let is_shadow = if let Some(sn) = shadow_filename {
        target_file_str == sn || target_file.file_name().and_then(|n| n.to_str()) == Some(sn)
    } else {
        false
    } || target_file
        .file_name()
        .and_then(|n| n.to_str())
        .map(|s| s.starts_with("tmp_nav_") || s.starts_with("tmp_shadow_"))
        .unwrap_or(false);

    let (target_uri, content) = if is_shadow {
        (current_doc_uri.clone(), current_doc_text.to_string())
    } else {
        let abs_path = if target_file.is_absolute() {
            target_file.to_path_buf()
        } else {
            base_dir.join(target_file)
        };

        if abs_path == current_doc_path {
            (current_doc_uri.clone(), current_doc_text.to_string())
        } else {
            let uri = Url::from_file_path(&abs_path).ok()?;
            let text = std::fs::read_to_string(&abs_path).unwrap_or_default();
            (uri, text)
        }
    };

    let target_index = LineIndex::new(&content);
    let line_0based = line_1based.saturating_sub(1);
    let line_str = target_index.line_content(line_0based as usize, &content);

    let mut byte_count = 0usize;
    let mut utf16_col = 0usize;
    for ch in line_str.chars() {
        if byte_count >= col_0based as usize {
            break;
        }
        byte_count += ch.len_utf8();
        utf16_col += ch.len_utf16();
    }

    let start_pos = Position::new(line_0based, utf16_col as u32);
    let remaining = if (col_0based as usize) < line_str.len() {
        &line_str[col_0based as usize..]
    } else {
        ""
    };
    let token_len: usize = remaining
        .chars()
        .take_while(|c| c.is_alphanumeric() || *c == '_')
        .map(|c| c.len_utf16())
        .sum();

    let end_pos = Position::new(
        line_0based,
        start_pos.character + if token_len > 0 { token_len as u32 } else { 1 },
    );

    Some((
        Location::new(target_uri, Range::new(start_pos, end_pos)),
        raw_sym.to_string(),
    ))
}

fn find_in_buffer_declaration(doc_text: &str, doc_uri: &Url, word: &str) -> Option<Location> {
    let line_index = LineIndex::new(doc_text);
    let decl_patterns = [
        format!(r"(?m)^\s*(?:proc|func|iterator|template|macro)\s+({})\b", regex::escape(word)),
        format!(r"(?m)^\s*({})\*?\s*=\s*(?:object|enum|concept|ref|ptr|distinct)", regex::escape(word)),
        format!(r"(?m)^\s*(?:var|let|const)\s+({})\b", regex::escape(word)),
        format!(r"(?m)\((?:[a-zA-Z0-9_,\s:]*,\s*)?({})\s*:\s*[a-zA-Z0-9_\[\],\s]+", regex::escape(word)),
    ];

    for pat in &decl_patterns {
        if let Ok(re) = Regex::new(pat) {
            if let Some(caps) = re.captures(doc_text) {
                if let Some(m) = caps.get(1) {
                    let start_offset = m.start();
                    let pos = line_index.byte_offset_to_lsp_pos(doc_text, start_offset);
                    let end_pos = Position::new(pos.line, pos.character + word.encode_utf16().count() as u32);
                    return Some(Location::new(doc_uri.clone(), Range::new(pos, end_pos)));
                }
            }
        }
    }

    None
}

fn find_in_buffer_references(
    doc_text: &str,
    doc_uri: &Url,
    word: &str,
    include_declaration: bool,
) -> Vec<Location> {
    let line_index = LineIndex::new(doc_text);
    let pattern = format!(r"\b{}\b", regex::escape(word));
    let regex = match Regex::new(&pattern) {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };

    let mut locations = Vec::new();

    for line_idx in 0..line_index.line_count() {
        let text_line = line_index.line_content(line_idx, doc_text);
        if !include_declaration && is_declaration_line(text_line, word) {
            continue;
        }

        for m in regex.find_iter(text_line) {
            let byte_start = m.start();
            let byte_end = m.end();

            let mut cur_byte = 0usize;
            let mut utf16_start = 0usize;
            let mut utf16_end = 0usize;

            for ch in text_line.chars() {
                if cur_byte < byte_start {
                    utf16_start += ch.len_utf16();
                }
                if cur_byte < byte_end {
                    utf16_end += ch.len_utf16();
                }
                cur_byte += ch.len_utf8();
            }

            let range = Range::new(
                Position::new(line_idx as u32, utf16_start as u32),
                Position::new(line_idx as u32, utf16_end as u32),
            );

            locations.push(Location::new(doc_uri.clone(), range));
        }
    }

    locations
}

fn extract_in_buffer_hover(doc_text: &str, word: &str) -> Option<String> {
    let line_index = LineIndex::new(doc_text);
    for line_idx in 0..line_index.line_count() {
        let text_line = line_index.line_content(line_idx, doc_text);
        if is_declaration_line(text_line, word) {
            let sig = text_line.trim().trim_end_matches('=').trim_end_matches(':').trim();
            return Some(format!("```nim\n{}\n```", sig));
        }
    }
    None
}
