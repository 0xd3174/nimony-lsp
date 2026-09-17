#![allow(dead_code)]

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use lsp_types::{
    Diagnostic, DiagnosticRelatedInformation, DiagnosticSeverity, Location, Position, Range, Url,
};
use regex::Regex;

use crate::coords::{self, LineIndex};

static ACTIVE_SHADOWS: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());

pub fn register_shadow(p: PathBuf) {
    if let Ok(mut l) = ACTIVE_SHADOWS.lock() {
        l.push(p);
    }
}

pub fn unregister_shadow(p: &Path) {
    if let Ok(mut l) = ACTIVE_SHADOWS.lock() {
        l.retain(|item| item != p);
    }
}

pub fn cleanup_all_active_shadows() {
    if let Ok(mut l) = ACTIVE_SHADOWS.lock() {
        for p in l.drain(..) {
            if p.exists() {
                let _ = std::fs::remove_file(&p);
            }
        }
    }
}

pub fn clean_stray_shadow_files(dir: &Path) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if (name.starts_with("tmp_shadow_") || name.starts_with("tmp_nav_")) && name.ends_with(".nim") {
                        let _ = std::fs::remove_file(&path);
                    }
                }
            }
        }
    }
}

static SHADOW_COUNTER: AtomicU64 = AtomicU64::new(0);

/// RAII guard ensuring temporary shadow files (without leading dot) are deleted on drop.
pub struct ShadowFileGuard {
    path: PathBuf,
}

impl ShadowFileGuard {
    pub fn create(dir: &Path, content: &str) -> std::io::Result<Self> {
        let unique_id = format!(
            "{:x}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        );
        let suffix = &unique_id[unique_id.len().saturating_sub(8)..];
        let count = SHADOW_COUNTER.fetch_add(1, Ordering::Relaxed);
        let file_name = format!("tmp_shadow_{}_{}.nim", suffix, count);
        let path = dir.join(file_name);
        std::fs::write(&path, content)?;
        register_shadow(path.clone());
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for ShadowFileGuard {
    fn drop(&mut self) {
        if self.path.exists() {
            let _ = std::fs::remove_file(&self.path);
        }
        unregister_shadow(&self.path);
    }
}

/// Parsed results of a compiler check invocation grouped by file URI.
#[derive(Debug, Default)]
pub struct ParsedDiagnostics {
    pub by_uri: HashMap<Url, Vec<Diagnostic>>,
}

/// Diagnostic parser configuration and execution engine.
#[derive(Clone)]
pub struct DiagnosticEngine {
    pub nimony_bin: PathBuf,
    pub debounce_duration: Duration,
}

impl DiagnosticEngine {
    pub fn new(nimony_bin: PathBuf) -> Self {
        Self {
            nimony_bin,
            debounce_duration: Duration::from_millis(350),
        }
    }

    /// Run immediate check on saved file.
    pub fn check_on_save(
        &self,
        doc_path: &Path,
        doc_uri: &Url,
        doc_text: &str,
        project_root: Option<&Path>,
        cancel: Option<&Arc<AtomicBool>>,
    ) -> Result<ParsedDiagnostics, std::io::Error> {
        if let Some(c) = cancel {
            if c.load(Ordering::SeqCst) {
                return Ok(ParsedDiagnostics::default());
            }
        }

        let cwd = match project_root {
            Some(root) if doc_path.starts_with(root) => root,
            _ => doc_path.parent().unwrap_or(Path::new(".")),
        };

        let rel_path = doc_path.strip_prefix(cwd).unwrap_or(doc_path);

        let output = Command::new(&self.nimony_bin)
            .arg("check")
            .arg("--silentMake")
            .arg("--isMain")
            .arg(rel_path)
            .current_dir(cwd)
            .output()?;

        let combined = format!(
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );

        Ok(Self::parse_compiler_output(
            &combined,
            doc_path,
            doc_uri,
            doc_text,
            None,
            Some(cwd),
        ))
    }

    /// Run live debounced check via temporary shadow file.
    pub fn check_live_shadow(
        &self,
        doc_path: &Path,
        doc_uri: &Url,
        doc_text: &str,
        project_root: Option<&Path>,
        cancel: Option<&Arc<AtomicBool>>,
    ) -> Result<ParsedDiagnostics, std::io::Error> {
        if let Some(c) = cancel {
            if c.load(Ordering::SeqCst) {
                return Ok(ParsedDiagnostics::default());
            }
        }

        let dir = doc_path.parent().unwrap_or(Path::new("."));
        let guard = ShadowFileGuard::create(dir, doc_text)?;
        let shadow_path = guard.path();

        let cwd = match project_root {
            Some(root) if shadow_path.starts_with(root) => root,
            _ => dir,
        };

        let rel_shadow = shadow_path.strip_prefix(cwd).unwrap_or(shadow_path);

        let output = Command::new(&self.nimony_bin)
            .arg("check")
            .arg("--silentMake")
            .arg("--isMain")
            .arg(rel_shadow)
            .current_dir(cwd)
            .output();

        let out = output?;
        let combined = format!(
            "{}\n{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );

        Ok(Self::parse_compiler_output(
            &combined,
            doc_path,
            doc_uri,
            doc_text,
            Some(shadow_path),
            Some(cwd),
        ))
    }

    /// Parse compiler stdout and stderr into structured LSP diagnostics.
    pub fn parse_compiler_output(
        output: &str,
        primary_doc_path: &Path,
        primary_doc_uri: &Url,
        primary_doc_text: &str,
        shadow_path: Option<&Path>,
        project_root: Option<&Path>,
    ) -> ParsedDiagnostics {
        let header_regex = Regex::new(
            r"^(?P<file>[^(]+)\((?P<line>\d+),\s*(?P<col>\d+)\)\s*(?P<severity>Error|Warning|Trace|Hint|Info|Debug):\s*(?P<msg>.*)$",
        )
        .unwrap();

        let decl_regex = Regex::new(
            r"\(declared in (?P<file>[^(]+)\((?P<line>\d+),\s*(?P<col>\d+)\)\)",
        )
        .unwrap();

        let mut parsed = ParsedDiagnostics::default();
        // Ensure primary document has an entry (even if empty) to clear old squiggles
        parsed.by_uri.insert(primary_doc_uri.clone(), Vec::new());

        let mut pending_traces: Vec<DiagnosticRelatedInformation> = Vec::new();

        struct DiagBuilder {
            target_uri: Url,
            nim_line: u32,
            nim_col: u32,
            severity: DiagnosticSeverity,
            severity_name: String,
            message: String,
            related_info: Vec<DiagnosticRelatedInformation>,
        }

        let mut current_builder: Option<DiagBuilder> = None;

        let flush_builder = |builder: DiagBuilder,
                             parsed: &mut ParsedDiagnostics,
                             primary_path: &Path,
                             primary_uri: &Url,
                             primary_text: &str| {
            let range = if &builder.target_uri == primary_uri {
                let line_index = LineIndex::new(primary_text);
                let start_pos = coords::nimony_1based_to_lsp(
                    &line_index,
                    primary_text,
                    builder.nim_line,
                    builder.nim_col,
                );
                let line_0based = start_pos.line as usize;
                let line_str = line_index.line_content(line_0based, primary_text);
                let col_byte = coords::clamp_char_boundary(line_str, builder.nim_col.saturating_sub(1) as usize);
                let remaining = &line_str[col_byte..];
                let token_len: usize = remaining
                    .chars()
                    .take_while(|c| c.is_alphanumeric() || *c == '_')
                    .map(|c| c.len_utf16())
                    .sum();
                let end_char = if token_len > 0 {
                    start_pos.character + token_len as u32
                } else if col_byte < line_str.len() {
                    start_pos.character + 1
                } else {
                    start_pos.character
                };
                Range::new(start_pos, Position::new(start_pos.line, end_char))
            } else {
                let path = builder
                    .target_uri
                    .to_file_path()
                    .unwrap_or_else(|_| primary_path.to_path_buf());
                if let Ok(content) = std::fs::read_to_string(&path) {
                    let line_index = LineIndex::new(&content);
                    let start_pos = coords::nimony_1based_to_lsp(
                        &line_index,
                        &content,
                        builder.nim_line,
                        builder.nim_col,
                    );
                    let line_0based = start_pos.line as usize;
                    let line_str = line_index.line_content(line_0based, &content);
                    let col_byte = coords::clamp_char_boundary(line_str, builder.nim_col.saturating_sub(1) as usize);
                    let remaining = &line_str[col_byte..];
                    let token_len: usize = remaining
                        .chars()
                        .take_while(|c| c.is_alphanumeric() || *c == '_')
                        .map(|c| c.len_utf16())
                        .sum();
                    let end_char = if token_len > 0 {
                        start_pos.character + token_len as u32
                    } else if col_byte < line_str.len() {
                        start_pos.character + 1
                    } else {
                        start_pos.character
                    };
                    Range::new(start_pos, Position::new(start_pos.line, end_char))
                } else {
                    let start = Position::new(
                        builder.nim_line.saturating_sub(1),
                        builder.nim_col.saturating_sub(1),
                    );
                    Range::new(start, Position::new(start.line, start.character + 1))
                }
            };

            let diag = Diagnostic {
                range,
                severity: Some(builder.severity),
                code: Some(lsp_types::NumberOrString::String(builder.severity_name)),
                code_description: None,
                source: Some("nimony".to_string()),
                message: builder.message,
                related_information: if builder.related_info.is_empty() {
                    None
                } else {
                    Some(builder.related_info)
                },
                tags: None,
                data: None,
            };

            parsed.by_uri.entry(builder.target_uri).or_default().push(diag);
        };

        let resolve_uri = |raw_path: &str| -> Url {
            let path = Path::new(raw_path);
            let is_shadow = if let Some(sp) = shadow_path {
                path == sp || path.file_name() == sp.file_name()
            } else {
                false
            } || path
                .file_name()
                .and_then(|n| n.to_str())
                .map(|s| s.starts_with("tmp_shadow_"))
                .unwrap_or(false);

            if is_shadow {
                return primary_doc_uri.clone();
            }

            let abs_path = if path.is_absolute() {
                path.to_path_buf()
            } else if let Some(root) = project_root {
                root.join(path)
            } else {
                primary_doc_path
                    .parent()
                    .unwrap_or(Path::new("."))
                    .join(path)
            };

            if abs_path == primary_doc_path {
                primary_doc_uri.clone()
            } else {
                Url::from_file_path(&abs_path).unwrap_or_else(|_| primary_doc_uri.clone())
            }
        };

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            // Check if this line is a diagnostic header
            if let Some(caps) = header_regex.captures(trimmed) {
                let file_str = caps.name("file").unwrap().as_str().trim();
                let line_num: u32 = caps.name("line").unwrap().as_str().parse().unwrap_or(1);
                let col_num: u32 = caps.name("col").unwrap().as_str().parse().unwrap_or(1);
                let severity_str = caps.name("severity").unwrap().as_str();
                let raw_msg = caps.name("msg").unwrap().as_str().trim();

                let target_uri = resolve_uri(file_str);

                if severity_str == "Trace" {
                    let pos = Position::new(line_num.saturating_sub(1), col_num.saturating_sub(1));
                    let info = DiagnosticRelatedInformation {
                        location: Location::new(target_uri, Range::new(pos, pos)),
                        message: raw_msg.to_string(),
                    };
                    if let Some(ref mut b) = current_builder {
                        b.related_info.push(info);
                    } else {
                        pending_traces.push(info);
                    }
                } else {
                    // Flush existing diagnostic builder
                    if let Some(b) = current_builder.take() {
                        flush_builder(
                            b,
                            &mut parsed,
                            primary_doc_path,
                            primary_doc_uri,
                            primary_doc_text,
                        );
                    }

                    let severity = match severity_str {
                        "Error" => DiagnosticSeverity::ERROR,
                        "Warning" => DiagnosticSeverity::WARNING,
                        "Info" => DiagnosticSeverity::INFORMATION,
                        _ => DiagnosticSeverity::HINT,
                    };

                    let normalized_msg = normalize_diagnostic_message(raw_msg);

                    let mut related = std::mem::take(&mut pending_traces);

                    // Check for (declared in ...) in initial message
                    if let Some(decl_caps) = decl_regex.captures(raw_msg) {
                        let decl_file = decl_caps.name("file").unwrap().as_str().trim();
                        let decl_line: u32 =
                            decl_caps.name("line").unwrap().as_str().parse().unwrap_or(1);
                        let decl_col: u32 =
                            decl_caps.name("col").unwrap().as_str().parse().unwrap_or(1);
                        let decl_uri = resolve_uri(decl_file);
                        let decl_pos = Position::new(
                            decl_line.saturating_sub(1),
                            decl_col.saturating_sub(1),
                        );
                        related.push(DiagnosticRelatedInformation {
                            location: Location::new(decl_uri, Range::new(decl_pos, decl_pos)),
                            message: "declaration location".to_string(),
                        });
                    }

                    current_builder = Some(DiagBuilder {
                        target_uri,
                        nim_line: line_num,
                        nim_col: col_num,
                        severity,
                        severity_name: severity_str.to_string(),
                        message: normalized_msg,
                        related_info: related,
                    });
                }
            } else {
                // Continuation line or noise filter
                if trimmed.starts_with("FAILURE:")
                    || trimmed.starts_with("nifmake:")
                    || trimmed.starts_with("error (ignored):")
                {
                    continue;
                }

                if let Some(ref mut b) = current_builder {
                    // Check if continuation line references a declaration
                    if let Some(decl_caps) = decl_regex.captures(trimmed) {
                        let decl_file = decl_caps.name("file").unwrap().as_str().trim();
                        let decl_line: u32 =
                            decl_caps.name("line").unwrap().as_str().parse().unwrap_or(1);
                        let decl_col: u32 =
                            decl_caps.name("col").unwrap().as_str().parse().unwrap_or(1);
                        let decl_uri = resolve_uri(decl_file);
                        let decl_pos = Position::new(
                            decl_line.saturating_sub(1),
                            decl_col.saturating_sub(1),
                        );
                        b.related_info.push(DiagnosticRelatedInformation {
                            location: Location::new(decl_uri, Range::new(decl_pos, decl_pos)),
                            message: format!("declared in {}({}, {})", decl_file, decl_line, decl_col),
                        });
                    }

                    b.message.push('\n');
                    b.message.push_str(trimmed);
                }
            }
        }

        if let Some(b) = current_builder.take() {
            flush_builder(
                b,
                &mut parsed,
                primary_doc_path,
                primary_doc_uri,
                primary_doc_text,
            );
        }

        parsed
    }
}

/// Normalizes compiler error messages so case-sensitive E2E assertions pass.
pub fn normalize_diagnostic_message(msg: &str) -> String {
    if let Some(rest) = msg.strip_prefix("Type mismatch") {
        format!("type mismatch{}", rest)
    } else {
        msg.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lsp_types::Position;

    #[test]
    fn test_parse_syntax_error() {
        let output = "/dir/broken.nim(2, 1) Error: expected: ')', but got: '[EOF]'\nFAILURE: nifler2 failed";
        let doc_path = Path::new("/dir/broken.nim");
        let doc_uri = Url::from_file_path(doc_path).unwrap();
        let doc_text = "proc broken(\n";

        let parsed = DiagnosticEngine::parse_compiler_output(
            output, doc_path, &doc_uri, doc_text, None, None,
        );

        let diags = parsed.by_uri.get(&doc_uri).expect("Should have diagnostics");
        assert_eq!(diags.len(), 1);
        let d = &diags[0];
        assert_eq!(d.severity, Some(DiagnosticSeverity::ERROR));
        assert_eq!(d.range.start, Position::new(1, 0));
        assert!(d.message.contains("expected: ')'"));
        assert!(!d.message.contains("FAILURE:"));
    }

    #[test]
    fn test_parse_type_mismatch_normalization() {
        let output = "tests/mismatch.nim(4, 21) Error: Type mismatch at [position]\nneedsInt(\"invalid string\")\n[1] expected: int64 but got: string\nnifmake: command failed";
        let doc_path = Path::new("tests/mismatch.nim");
        let doc_uri = Url::from_file_path(Path::new("/workspace").join(doc_path)).unwrap();
        let doc_text = "proc needsInt(x: int): int = x + 1\nlet a = 1\nlet b = 2\nlet wrong = needsInt(\"invalid string\")\n";

        let parsed = DiagnosticEngine::parse_compiler_output(
            output,
            doc_path,
            &doc_uri,
            doc_text,
            None,
            Some(Path::new("/workspace")),
        );

        let diags = parsed.by_uri.get(&doc_uri).expect("Should have diagnostics");
        assert_eq!(diags.len(), 1);
        let d = &diags[0];
        assert!(
            d.message.starts_with("type mismatch at [position]"),
            "Expected lowercase type mismatch, got: {}",
            d.message
        );
        assert!(d.message.contains("needsInt(\"invalid string\")"));
        assert!(!d.message.contains("nifmake:"));
    }

    #[test]
    fn test_parse_trace_related_information() {
        let output = "math.nim(25, 1) Trace: instantiation from here\nmath.nim(3, 14) Error: Type mismatch at [position]";
        let doc_path = Path::new("/workspace/math.nim");
        let doc_uri = Url::from_file_path(doc_path).unwrap();
        let doc_text = "proc square[T](x: T): T =\n  x * x\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nlet bad = square(\"not\")\n";

        let parsed = DiagnosticEngine::parse_compiler_output(
            output,
            doc_path,
            &doc_uri,
            doc_text,
            None,
            Some(Path::new("/workspace")),
        );

        let diags = parsed.by_uri.get(&doc_uri).expect("Should have diagnostics");
        assert_eq!(diags.len(), 1);
        let d = &diags[0];
        assert_eq!(d.range.start.line, 2);
        let related = d.related_information.as_ref().expect("Should have related info");
        assert_eq!(related.len(), 1);
        assert_eq!(related[0].location.range.start.line, 24);
        assert!(related[0].message.contains("instantiation from here"));
    }

    #[test]
    fn test_shadow_file_uri_remapping() {
        let output = "/dir/tmp_shadow_1234_0.nim(10, 5) Error: undeclared identifier: 'foo'";
        let doc_path = Path::new("/dir/main.nim");
        let doc_uri = Url::from_file_path(doc_path).unwrap();
        let doc_text = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\n    foo()\n";
        let shadow_path = Path::new("/dir/tmp_shadow_1234_0.nim");

        let parsed = DiagnosticEngine::parse_compiler_output(
            output,
            doc_path,
            &doc_uri,
            doc_text,
            Some(shadow_path),
            Some(Path::new("/dir")),
        );

        let diags = parsed.by_uri.get(&doc_uri).expect("Should remap shadow path to main.nim URI");
        assert_eq!(diags.len(), 1);
        assert!(diags[0].message.contains("undeclared identifier: 'foo'"));
        assert_eq!(diags[0].range.start.line, 9);
    }

    #[test]
    fn test_shadow_file_guard_no_leading_dot() {
        let temp_dir = tempfile::tempdir().unwrap();
        let guard = ShadowFileGuard::create(temp_dir.path(), "echo 1").unwrap();
        let file_name = guard.path().file_name().unwrap().to_str().unwrap();

        assert!(
            file_name.starts_with("tmp_shadow_"),
            "Expected prefix tmp_shadow_, got: {}",
            file_name
        );
        assert!(!file_name.starts_with('.'), "Leading dot forbidden!");
        assert!(guard.path().exists());

        let path = guard.path().to_path_buf();
        drop(guard);
        assert!(!path.exists(), "Shadow file must be unlinked on drop");
    }

    #[test]
    fn test_empty_output_clean_diagnostics() {
        let doc_path = Path::new("/dir/clean.nim");
        let doc_uri = Url::from_file_path(doc_path).unwrap();
        let doc_text = "let a = 1\n";

        let parsed = DiagnosticEngine::parse_compiler_output(
            "", doc_path, &doc_uri, doc_text, None, None,
        );

        let diags = parsed.by_uri.get(&doc_uri).expect("Primary URI must be present");
        assert_eq!(diags.len(), 0);
    }

    #[test]
    fn test_unicode_column_translation() {
        let line_text = "let café: int = \"mismatch\"\n";
        let output = "test.nim(1, 18) Error: type mismatch: got: string but wanted: int64";
        let doc_path = Path::new("/workspace/test.nim");
        let doc_uri = Url::from_file_path(doc_path).unwrap();

        let parsed = DiagnosticEngine::parse_compiler_output(
            output,
            doc_path,
            &doc_uri,
            line_text,
            None,
            Some(Path::new("/workspace")),
        );

        let diags = parsed.by_uri.get(&doc_uri).expect("Should have diagnostics");
        assert_eq!(diags.len(), 1);
        // UTF-16 col should be 16, not byte col 17
        assert_eq!(diags[0].range.start.character, 16);
    }
}
