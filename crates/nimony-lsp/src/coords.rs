#![allow(dead_code)]

use lsp_types::Position;

/// Line index providing byte offset indexing and UTF-16 <-> UTF-8 coordinate translations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LineIndex {
    /// Byte offsets where each line starts (0-based)
    pub line_starts: Vec<usize>,
    /// Total byte length of text
    pub len: usize,
}

impl LineIndex {
    pub fn new(text: &str) -> Self {
        let mut line_starts = vec![0];
        for (i, b) in text.bytes().enumerate() {
            if b == b'\n' {
                line_starts.push(i + 1);
            }
        }
        Self {
            line_starts,
            len: text.len(),
        }
    }

    pub fn line_count(&self) -> usize {
        self.line_starts.len()
    }

    pub fn line_start(&self, line: usize) -> usize {
        if line >= self.line_starts.len() {
            self.len
        } else {
            self.line_starts[line]
        }
    }

    /// Returns the text slice of a line without trailing '\r' or '\n'.
    pub fn line_content<'a>(&self, line: usize, text: &'a str) -> &'a str {
        if line >= self.line_starts.len() {
            return "";
        }
        let start = self.line_starts[line];
        let end = if line + 1 < self.line_starts.len() {
            self.line_starts[line + 1]
        } else {
            text.len()
        };

        if start > text.len() || start > end {
            return "";
        }
        let slice = &text[start..end.min(text.len())];
        slice.trim_end_matches(&['\r', '\n'][..])
    }

    /// Alias for line_content.
    pub fn line_slice<'a>(&self, line: usize, text: &'a str) -> &'a str {
        self.line_content(line, text)
    }

    pub fn lsp_pos_to_byte_offset(&self, text: &str, pos: Position) -> usize {
        lsp_pos_to_byte_offset(self, text, pos)
    }

    pub fn byte_offset_to_lsp_pos(&self, text: &str, byte_offset: usize) -> Position {
        byte_offset_to_lsp_pos(self, text, byte_offset)
    }

    pub fn lsp_to_nimony_1based(&self, text: &str, pos: Position) -> (u32, u32) {
        lsp_to_nimony_1based(self, text, pos)
    }

    pub fn lsp_to_nimony_0based(&self, text: &str, pos: Position) -> (u32, u32) {
        lsp_to_nimony_0based(self, text, pos)
    }

    pub fn nimony_1based_to_lsp(&self, text: &str, line_1based: u32, col_1based: u32) -> Position {
        nimony_1based_to_lsp(self, text, line_1based, col_1based)
    }

    pub fn nimony_0based_to_lsp(&self, text: &str, line_1based: u32, target_byte_offset: u32) -> Position {
        nimony_0based_to_lsp(self, text, line_1based, target_byte_offset)
    }
}

/// Clamps a byte index to the nearest lower char boundary <= index, saturated to s.len().
pub fn clamp_char_boundary(s: &str, mut index: usize) -> usize {
    if index >= s.len() {
        return s.len();
    }
    while !s.is_char_boundary(index) {
        index = index.saturating_sub(1);
    }
    index
}

/// Translate LSP Position (0-based line, UTF-16 code unit offset) into Nimony 1-based (line, UTF-8 byte col).
pub fn lsp_to_nimony_1based(index: &LineIndex, text: &str, pos: Position) -> (u32, u32) {
    let line_0based = (pos.line as usize).min(index.line_count().saturating_sub(1));
    let target_utf16_col = pos.character as usize;

    let line_str = index.line_content(line_0based, text);

    let mut current_utf16 = 0usize;
    let mut byte_offset = 0usize;

    for ch in line_str.chars() {
        if current_utf16 >= target_utf16_col {
            break;
        }
        current_utf16 += ch.len_utf16();
        byte_offset += ch.len_utf8();
    }

    let nimony_line = (line_0based + 1) as u32;
    let nimony_col = (byte_offset + 1) as u32;
    (nimony_line, nimony_col)
}

/// Translate LSP Position into Nimony 1-based line and 0-based UTF-8 byte column.
pub fn lsp_to_nimony_0based(index: &LineIndex, text: &str, pos: Position) -> (u32, u32) {
    let (nim_line, nim_col_1based) = lsp_to_nimony_1based(index, text, pos);
    (nim_line, nim_col_1based.saturating_sub(1))
}

/// Translate Nimony 1-based coordinates (from diagnostic output) to LSP Position.
pub fn nimony_1based_to_lsp(index: &LineIndex, text: &str, line_1based: u32, col_1based: u32) -> Position {
    let target_byte_offset = col_1based.saturating_sub(1);
    nimony_0based_to_lsp(index, text, line_1based, target_byte_offset)
}

/// Translate Nimony TSV coordinates (1-based line, 0-based UTF-8 byte offset) to LSP Position.
pub fn nimony_0based_to_lsp(index: &LineIndex, text: &str, line_1based: u32, target_byte_offset: u32) -> Position {
    let line_0based = (line_1based.saturating_sub(1) as usize).min(index.line_count().saturating_sub(1));
    let line_str = index.line_content(line_0based, text);

    let mut current_byte = 0usize;
    let mut utf16_col = 0usize;

    for ch in line_str.chars() {
        if current_byte >= target_byte_offset as usize {
            break;
        }
        current_byte += ch.len_utf8();
        utf16_col += ch.len_utf16();
    }

    Position {
        line: line_0based as u32,
        character: utf16_col as u32,
    }
}

/// Convert LSP Position to document-wide byte offset (for replace_range).
pub fn lsp_pos_to_byte_offset(index: &LineIndex, text: &str, pos: Position) -> usize {
    let line_0based = (pos.line as usize).min(index.line_count().saturating_sub(1));
    let line_start = index.line_start(line_0based);
    let line_str = index.line_content(line_0based, text);

    let mut current_utf16 = 0usize;
    let mut col_byte = 0usize;

    for ch in line_str.chars() {
        if current_utf16 >= pos.character as usize {
            break;
        }
        current_utf16 += ch.len_utf16();
        col_byte += ch.len_utf8();
    }

    (line_start + col_byte).min(text.len())
}

/// Convert document-wide byte offset to LSP Position.
pub fn byte_offset_to_lsp_pos(index: &LineIndex, text: &str, mut byte_offset: usize) -> Position {
    byte_offset = byte_offset.min(text.len());

    let line_idx = match index.line_starts.binary_search(&byte_offset) {
        Ok(idx) => idx,
        Err(idx) => idx.saturating_sub(1),
    };

    let line_start = index.line_starts[line_idx];
    let col_byte_offset = byte_offset.saturating_sub(line_start);
    let line_str = index.line_content(line_idx, text);

    let mut current_byte = 0usize;
    let mut utf16_col = 0usize;

    for ch in line_str.chars() {
        if current_byte >= col_byte_offset {
            break;
        }
        current_byte += ch.len_utf8();
        utf16_col += ch.len_utf16();
    }

    Position {
        line: line_idx as u32,
        character: utf16_col as u32,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lsp_types::Position;

    #[test]
    fn test_ascii_roundtrip() {
        let text = "proc add(a: int): int = a + 1";
        let index = LineIndex::new(text);

        // At UTF-16 col 5 ('a' in "add")
        let pos = Position::new(0, 5);
        let (nim_line, nim_col) = lsp_to_nimony_1based(&index, text, pos);
        assert_eq!(nim_line, 1);
        assert_eq!(nim_col, 6);

        let back_pos = nimony_1based_to_lsp(&index, text, nim_line, nim_col);
        assert_eq!(back_pos, pos);
    }

    #[test]
    fn test_multibyte_utf8_2byte() {
        // "let café = 1" -> 'é' is 2 bytes UTF-8, 1 UTF-16 code unit
        // "let " (4) + "caf" (3) + "é" (2) + " " (1) = 10 bytes at col 9 UTF-16
        let text = "let café = 1";
        let index = LineIndex::new(text);

        let pos = Position::new(0, 9);
        let (line, col) = lsp_to_nimony_1based(&index, text, pos);
        assert_eq!(line, 1);
        assert_eq!(col, 11); // 1-based col 11

        let back = nimony_1based_to_lsp(&index, text, line, col);
        assert_eq!(back, pos);
    }

    #[test]
    fn test_multibyte_utf8_3byte() {
        // '☕' is 3 bytes UTF-8, 1 UTF-16 code unit
        let text = "let c = \"☕\"\nlet d = 2";
        let index = LineIndex::new(text);

        // Position on second line after "let "
        let pos = Position::new(1, 4);
        let (line, col) = lsp_to_nimony_1based(&index, text, pos);
        assert_eq!(line, 2);
        assert_eq!(col, 5);

        let back = nimony_1based_to_lsp(&index, text, line, col);
        assert_eq!(back, pos);
    }

    #[test]
    fn test_astral_plane_emoji_4byte() {
        // "let 🚀 = 1" -> '🚀' is 4 bytes UTF-8, 2 UTF-16 code units (surrogate pair)
        // UTF-16 col 7 is after the space following rocket:
        // 'l','e','t',' ' (4 UTF-16, 4 bytes) + 🚀 (2 UTF-16, 4 bytes) + ' ' (1 UTF-16, 1 byte) = 7 UTF-16, 9 bytes
        let text = "let 🚀 = 1";
        let index = LineIndex::new(text);

        let pos = Position::new(0, 7);
        let (line, col) = lsp_to_nimony_1based(&index, text, pos);
        assert_eq!(line, 1);
        assert_eq!(col, 10); // 9 bytes + 1 = 10

        let back = nimony_1based_to_lsp(&index, text, line, col);
        assert_eq!(back, pos);
    }

    #[test]
    fn test_tsv_0based_conversion() {
        let text = "proc greet*(u: User): string =\n  result = u.name\n";
        let index = LineIndex::new(text);

        // Nimony TSV output for greet: line 1, col 5 (0-based)
        let pos = nimony_0based_to_lsp(&index, text, 1, 5);
        assert_eq!(pos, Position::new(0, 5));
    }

    #[test]
    fn test_crlf_line_endings() {
        let text = "line1\r\nline2\r\nline3";
        let index = LineIndex::new(text);
        assert_eq!(index.line_count(), 3);

        let pos = Position::new(1, 2);
        let (line, col) = lsp_to_nimony_1based(&index, text, pos);
        assert_eq!(line, 2);
        assert_eq!(col, 3);

        let offset = lsp_pos_to_byte_offset(&index, text, pos);
        // "line1\r\n" is 7 bytes; + 2 bytes on line 2 = 9
        assert_eq!(offset, 9);
    }

    #[test]
    fn test_out_of_bounds_saturation() {
        let text = "short";
        let index = LineIndex::new(text);

        // Line out of bounds
        let pos = Position::new(100, 0);
        let (line, col) = lsp_to_nimony_1based(&index, text, pos);
        assert_eq!(line, 1);
        assert_eq!(col, 1);

        // Col out of bounds
        let pos_col = Position::new(0, 500);
        let (line2, col2) = lsp_to_nimony_1based(&index, text, pos_col);
        assert_eq!(line2, 1);
        assert_eq!(col2, 6); // Saturates to text.len() + 1
    }

    #[test]
    fn test_empty_file() {
        let text = "";
        let index = LineIndex::new(text);

        let pos = Position::new(0, 0);
        let (line, col) = lsp_to_nimony_1based(&index, text, pos);
        assert_eq!(line, 1);
        assert_eq!(col, 1);

        let offset = lsp_pos_to_byte_offset(&index, text, pos);
        assert_eq!(offset, 0);
    }

    #[test]
    fn test_clamp_char_boundary() {
        let text = "a cafés 🚀 end";
        assert_eq!(clamp_char_boundary(text, 0), 0);
        assert_eq!(clamp_char_boundary(text, 5), 5); // start of 'é'
        assert_eq!(clamp_char_boundary(text, 6), 5); // inside 'é' clamped to 5
        assert_eq!(clamp_char_boundary(text, 7), 7); // start of 's'
        assert_eq!(clamp_char_boundary(text, 9), 9); // start of '🚀'
        assert_eq!(clamp_char_boundary(text, 10), 9); // inside '🚀'
        assert_eq!(clamp_char_boundary(text, 11), 9); // inside '🚀'
        assert_eq!(clamp_char_boundary(text, 12), 9); // inside '🚀'
        assert_eq!(clamp_char_boundary(text, 13), 13); // after '🚀'
        assert_eq!(clamp_char_boundary(text, 999), text.len()); // out of bounds
    }
}
