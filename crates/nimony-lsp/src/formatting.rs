#![allow(dead_code)]

use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use lsp_types::{FormattingOptions, Position, Range, TextEdit};
use similar::{DiffOp, TextDiff};

#[derive(Clone)]
pub struct FormattingEngine {
    pub nimpretty_bin: PathBuf,
}

impl FormattingEngine {
    pub fn new(nimpretty_bin: PathBuf) -> Self {
        Self { nimpretty_bin }
    }

    pub fn format(
        &self,
        text: &str,
        options: &FormattingOptions,
        cancel: Option<&Arc<AtomicBool>>,
    ) -> Result<Option<Vec<TextEdit>>, String> {
        if let Some(c) = cancel {
            if c.load(Ordering::SeqCst) {
                return Ok(None);
            }
        }

        let tab_size = options.tab_size;
        let indent_arg = format!("--indent:{}", tab_size);

        let mut child = Command::new(&self.nimpretty_bin)
            .arg("--stdin")
            .arg(&indent_arg)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to spawn nimpretty: {}", e))?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin
                .write_all(text.as_bytes())
                .map_err(|e| format!("Failed to write to nimpretty stdin: {}", e))?;
        }

        let output = child
            .wait_with_output()
            .map_err(|e| format!("Failed to read nimpretty output: {}", e))?;

        // Exit code 1 means syntax error - must return Ok(None) to avoid corrupting document
        if !output.status.success() {
            return Ok(None);
        }

        let formatted = String::from_utf8_lossy(&output.stdout);
        let edits = compute_minimal_edits(text, &formatted);
        Ok(Some(edits))
    }
}

pub fn compute_minimal_edits(original: &str, formatted: &str) -> Vec<TextEdit> {
    if original == formatted {
        return Vec::new();
    }

    let diff = TextDiff::from_lines(original, formatted);
    let orig_lines: Vec<&str> = original.split('\n').collect();
    let total_orig_lines = orig_lines.len();
    let last_orig_line_len = orig_lines.last().map(|l| l.len()).unwrap_or(0);

    let mut edits = Vec::new();

    for op in diff.ops() {
        match *op {
            DiffOp::Equal { .. } => {}
            DiffOp::Delete {
                old_index, old_len, ..
            } => {
                let start = Position::new(old_index as u32, 0);
                let end = if old_index + old_len >= total_orig_lines {
                    Position::new((total_orig_lines - 1) as u32, last_orig_line_len as u32)
                } else {
                    Position::new((old_index + old_len) as u32, 0)
                };
                edits.push(TextEdit {
                    range: Range::new(start, end),
                    new_text: String::new(),
                });
            }
            DiffOp::Insert {
                old_index,
                new_index,
                new_len,
            } => {
                let pos = if old_index >= total_orig_lines {
                    Position::new((total_orig_lines - 1) as u32, last_orig_line_len as u32)
                } else {
                    Position::new(old_index as u32, 0)
                };
                let mut new_text = String::new();
                for slice in &diff.new_slices()[new_index..new_index + new_len] {
                    new_text.push_str(slice);
                }
                edits.push(TextEdit {
                    range: Range::new(pos, pos),
                    new_text,
                });
            }
            DiffOp::Replace {
                old_index,
                old_len,
                new_index,
                new_len,
            } => {
                let start = Position::new(old_index as u32, 0);
                let end = if old_index + old_len >= total_orig_lines {
                    Position::new((total_orig_lines - 1) as u32, last_orig_line_len as u32)
                } else {
                    Position::new((old_index + old_len) as u32, 0)
                };
                let mut new_text = String::new();
                for slice in &diff.new_slices()[new_index..new_index + new_len] {
                    new_text.push_str(slice);
                }
                edits.push(TextEdit {
                    range: Range::new(start, end),
                    new_text,
                });
            }
        }
    }

    if edits.is_empty() {
        vec![TextEdit {
            range: Range::new(
                Position::new(0, 0),
                Position::new((total_orig_lines - 1) as u32, last_orig_line_len as u32),
            ),
            new_text: formatted.to_string(),
        }]
    } else {
        edits
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_minimal_edits_identical() {
        let text = "proc hello() = discard\n";
        let edits = compute_minimal_edits(text, text);
        assert!(edits.is_empty());
    }

    #[test]
    fn test_compute_minimal_edits_changed_line() {
        let orig = "proc foo( a :int ):int=a\n";
        let formatted = "proc foo(a: int): int = a\n";
        let edits = compute_minimal_edits(orig, formatted);
        assert_eq!(edits.len(), 1);
        assert_eq!(edits[0].new_text, formatted);
    }
}
