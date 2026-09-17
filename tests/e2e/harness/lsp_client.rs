// Opaque-box LSP stdio test client for E2E tests
// Standalone Rust binary, compiled with standard rustc (no external dependencies).

use std::env;
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
enum IncomingMessage {
    Response { id: String, raw: String },
    Notification { method: String, raw: String },
    Unknown(String),
}

fn extract_json_string_field(json: &str, field: &str) -> Option<String> {
    let key = format!("\"{}\"", field);
    let key_pos = json.find(&key)?;
    let after_key = &json[key_pos + key.len()..];
    let colon_pos = after_key.find(':')?;
    let val_str = after_key[colon_pos + 1..].trim_start();
    if val_str.starts_with('"') {
        let after_quote = &val_str[1..];
        let mut escaped = false;
        let mut end = 0;
        for (i, c) in after_quote.char_indices() {
            if escaped {
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '"' {
                end = i;
                break;
            }
        }
        Some(after_quote[..end].to_string())
    } else {
        None
    }
}

fn extract_json_id_field(json: &str) -> Option<String> {
    let key = "\"id\"";
    let key_pos = json.find(key)?;
    let after_key = &json[key_pos + key.len()..];
    let colon_pos = after_key.find(':')?;
    let val_str = after_key[colon_pos + 1..].trim_start();
    if val_str.starts_with('"') {
        extract_json_string_field(json, "id")
    } else {
        // numeric id
        let mut end = 0;
        for (i, c) in val_str.char_indices() {
            if c.is_ascii_digit() || c == '-' {
                end = i + 1;
            } else {
                break;
            }
        }
        if end > 0 {
            Some(val_str[..end].to_string())
        } else {
            None
        }
    }
}

fn parse_message(raw: &str) -> IncomingMessage {
    let id = extract_json_id_field(raw);
    let method = extract_json_string_field(raw, "method");

    match (id, method) {
        (Some(id), None) => IncomingMessage::Response { id, raw: raw.to_string() },
        (None, Some(method)) => IncomingMessage::Notification { method, raw: raw.to_string() },
        (Some(id), Some(_method)) => IncomingMessage::Response { id, raw: raw.to_string() }, // Server request to client
        _ => IncomingMessage::Unknown(raw.to_string()),
    }
}

struct LspProcess {
    child: Child,
    stdin: ChildStdin,
    rx: Receiver<IncomingMessage>,
    notifications: Vec<(String, String)>,
    responses: Vec<(String, String)>,
}

impl LspProcess {
    fn spawn(cmd: &str, args: &[String], cwd: Option<&str>) -> io::Result<Self> {
        let mut command = Command::new(cmd);
        command.args(args);
        if let Some(c) = cwd {
            command.current_dir(c);
        }
        command.stdin(Stdio::piped());
        command.stdout(Stdio::piped());
        command.stderr(Stdio::inherit());

        let mut child = command.spawn()?;
        let stdin = child.stdin.take().ok_or_else(|| io::Error::new(io::ErrorKind::Other, "Failed to open stdin"))?;
        let stdout = child.stdout.take().ok_or_else(|| io::Error::new(io::ErrorKind::Other, "Failed to open stdout"))?;

        let (tx, rx) = mpsc::channel();

        thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let mut header = String::new();
                let mut content_length: Option<usize> = None;

                loop {
                    header.clear();
                    match reader.read_line(&mut header) {
                        Ok(0) => return, // EOF
                        Ok(_) => {
                            let trimmed = header.trim();
                            if trimmed.is_empty() {
                                break; // Header end (\r\n\r\n)
                            }
                            if trimmed.to_lowercase().starts_with("content-length:") {
                                if let Some(val) = trimmed.split(':').nth(1) {
                                    if let Ok(len) = val.trim().parse::<usize>() {
                                        content_length = Some(len);
                                    }
                                }
                            }
                        }
                        Err(_) => return,
                    }
                }

                if let Some(len) = content_length {
                    let mut body_buf = vec![0u8; len];
                    if reader.read_exact(&mut body_buf).is_ok() {
                        if let Ok(body_str) = String::from_utf8(body_buf) {
                            let msg = parse_message(&body_str);
                            if tx.send(msg).is_err() {
                                break;
                            }
                        }
                    }
                }
            }
        });

        Ok(Self {
            child,
            stdin,
            rx,
            notifications: Vec::new(),
            responses: Vec::new(),
        })
    }

    fn write_frame(&mut self, payload: &str) -> io::Result<()> {
        let frame = format!("Content-Length: {}\r\n\r\n{}", payload.len(), payload);
        self.stdin.write_all(frame.as_bytes())?;
        self.stdin.flush()
    }

    fn write_raw(&mut self, raw: &[u8]) -> io::Result<()> {
        self.stdin.write_all(raw)?;
        self.stdin.flush()
    }

    fn pump_messages(&mut self) {
        while let Ok(msg) = self.rx.try_recv() {
            match msg {
                IncomingMessage::Response { id, raw } => self.responses.push((id, raw)),
                IncomingMessage::Notification { method, raw } => self.notifications.push((method, raw)),
                IncomingMessage::Unknown(raw) => self.notifications.push(("unknown".to_string(), raw)),
            }
        }
    }

    fn wait_for_response(&mut self, target_id: &str, timeout: Duration) -> Option<String> {
        // Check already buffered
        if let Some(pos) = self.responses.iter().position(|(id, _)| id == target_id) {
            return Some(self.responses.remove(pos).1);
        }

        let start = Instant::now();
        while start.elapsed() < timeout {
            let rem = timeout.saturating_sub(start.elapsed());
            match self.rx.recv_timeout(rem) {
                Ok(IncomingMessage::Response { id, raw }) => {
                    if id == target_id {
                        return Some(raw);
                    } else {
                        self.responses.push((id, raw));
                    }
                }
                Ok(IncomingMessage::Notification { method, raw }) => {
                    self.notifications.push((method, raw));
                }
                Ok(IncomingMessage::Unknown(raw)) => {
                    self.notifications.push(("unknown".to_string(), raw));
                }
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => break,
            }
        }
        None
    }

    fn wait_for_notification(&mut self, target_method: &str, timeout: Duration) -> Option<String> {
        if let Some(pos) = self.notifications.iter().position(|(m, _)| m == target_method) {
            return Some(self.notifications.remove(pos).1);
        }

        let start = Instant::now();
        while start.elapsed() < timeout {
            let rem = timeout.saturating_sub(start.elapsed());
            match self.rx.recv_timeout(rem) {
                Ok(IncomingMessage::Notification { method, raw }) => {
                    if method == target_method {
                        return Some(raw);
                    } else {
                        self.notifications.push((method, raw));
                    }
                }
                Ok(IncomingMessage::Response { id, raw }) => {
                    self.responses.push((id, raw));
                }
                Ok(IncomingMessage::Unknown(raw)) => {
                    self.notifications.push(("unknown".to_string(), raw));
                }
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => break,
            }
        }
        None
    }

    #[allow(dead_code)]
    fn wait_for_any_notification(&mut self, timeout: Duration) -> Option<(String, String)> {
        if !self.notifications.is_empty() {
            return Some(self.notifications.remove(0));
        }

        let start = Instant::now();
        while start.elapsed() < timeout {
            let rem = timeout.saturating_sub(start.elapsed());
            match self.rx.recv_timeout(rem) {
                Ok(IncomingMessage::Notification { method, raw }) => {
                    return Some((method, raw));
                }
                Ok(IncomingMessage::Response { id, raw }) => {
                    self.responses.push((id, raw));
                }
                Ok(IncomingMessage::Unknown(raw)) => {
                    self.notifications.push(("unknown".to_string(), raw));
                }
                Err(RecvTimeoutError::Timeout) => break,
                Err(RecvTimeoutError::Disconnected) => break,
            }
        }
        None
    }

    fn kill(mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn print_help() {
    eprintln!(
        "Usage: lsp_client <subcommand> [options]\n\
         Subcommands:\n\
           single-request --cmd <cmd> [--cwd <dir>] --request <json> [--timeout <ms>]\n\
           raw-send-recv  --cmd <cmd> [--cwd <dir>] --raw <string> [--timeout <ms>]\n\
           run-script     --cmd <cmd> [--cwd <dir>] --script <script_file>\n\
           coords-test    --text <text> --line <line> --col <col> (calculates byte vs utf16)\n"
    );
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_help();
        std::process::exit(1);
    }

    match args[1].as_str() {
        "coords-test" => {
            // Helper for Tier 1 UTF-16 coords round-trip
            let mut text = String::new();
            let mut target_line = 0usize;
            let mut target_utf16_col = 0usize;

            let mut i = 2;
            while i < args.len() {
                match args[i].as_str() {
                    "--text" => {
                        text = args[i + 1].replace("\\n", "\n");
                        i += 2;
                    }
                    "--file" => {
                        text = fs::read_to_string(&args[i + 1]).unwrap_or_default();
                        i += 2;
                    }
                    "--line" => {
                        target_line = args[i + 1].parse().unwrap_or(0);
                        i += 2;
                    }
                    "--utf16-col" => {
                        target_utf16_col = args[i + 1].parse().unwrap_or(0);
                        i += 2;
                    }
                    _ => i += 1,
                }
            }

            let lines: Vec<&str> = text.lines().collect();
            if target_line >= lines.len() {
                eprintln!("Line {} out of bounds (len {})", target_line, lines.len());
                std::process::exit(1);
            }

            let line_str = lines[target_line];
            let mut current_utf16 = 0usize;
            let mut byte_offset = 0usize;

            for ch in line_str.chars() {
                if current_utf16 >= target_utf16_col {
                    break;
                }
                current_utf16 += ch.len_utf16();
                byte_offset += ch.len_utf8();
            }

            // Output JSON mapping
            println!(
                "{{\"lsp_line\":{},\"lsp_utf16_col\":{},\"nimony_1based_line\":{},\"nimony_1based_col\":{},\"nimony_0based_byte_offset\":{}}}",
                target_line,
                target_utf16_col,
                target_line + 1,
                byte_offset + 1,
                byte_offset
            );
        }

        "single-request" => {
            let mut cmd = String::new();
            let mut cmd_args: Vec<String> = Vec::new();
            let mut cwd: Option<String> = None;
            let mut request = String::new();
            let mut timeout_ms = 5000u64;

            let mut i = 2;
            while i < args.len() {
                match args[i].as_str() {
                    "--cmd" => {
                        cmd = args[i + 1].clone();
                        i += 2;
                    }
                    "--arg" => {
                        cmd_args.push(args[i + 1].clone());
                        i += 2;
                    }
                    "--cwd" => {
                        cwd = Some(args[i + 1].clone());
                        i += 2;
                    }
                    "--request" => {
                        request = args[i + 1].clone();
                        i += 2;
                    }
                    "--timeout" => {
                        timeout_ms = args[i + 1].parse().unwrap_or(5000);
                        i += 2;
                    }
                    _ => i += 1,
                }
            }

            if cmd.is_empty() || request.is_empty() {
                eprintln!("Missing --cmd or --request");
                std::process::exit(1);
            }

            let req_id = extract_json_id_field(&request).unwrap_or_else(|| "1".to_string());

            let mut proc = match LspProcess::spawn(&cmd, &cmd_args, cwd.as_deref()) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("Failed to spawn {}: {}", cmd, e);
                    std::process::exit(127);
                }
            };

            if let Err(e) = proc.write_frame(&request) {
                eprintln!("Failed to write request: {}", e);
                proc.kill();
                std::process::exit(1);
            }

            let timeout = Duration::from_millis(timeout_ms);
            match proc.wait_for_response(&req_id, timeout) {
                Some(resp) => {
                    println!("{}", resp);
                    proc.kill();
                    std::process::exit(0);
                }
                None => {
                    eprintln!("Timed out waiting for response id {}", req_id);
                    proc.kill();
                    std::process::exit(2);
                }
            }
        }

        "raw-send-recv" => {
            let mut cmd = String::new();
            let cmd_args: Vec<String> = Vec::new();
            let mut cwd: Option<String> = None;
            let mut raw_str = String::new();
            let mut timeout_ms = 3000u64;

            let mut i = 2;
            while i < args.len() {
                match args[i].as_str() {
                    "--cmd" => {
                        cmd = args[i + 1].clone();
                        i += 2;
                    }
                    "--cwd" => {
                        cwd = Some(args[i + 1].clone());
                        i += 2;
                    }
                    "--raw" => {
                        raw_str = args[i + 1].clone();
                        i += 2;
                    }
                    "--timeout" => {
                        timeout_ms = args[i + 1].parse().unwrap_or(3000);
                        i += 2;
                    }
                    _ => i += 1,
                }
            }

            let mut proc = match LspProcess::spawn(&cmd, &cmd_args, cwd.as_deref()) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("Failed to spawn {}: {}", cmd, e);
                    std::process::exit(127);
                }
            };

            let _ = proc.write_raw(raw_str.as_bytes());

            let timeout = Duration::from_millis(timeout_ms);
            let start = Instant::now();
            let mut received = false;
            while start.elapsed() < timeout {
                let rem = timeout.saturating_sub(start.elapsed());
                if let Ok(msg) = proc.rx.recv_timeout(rem) {
                    match msg {
                        IncomingMessage::Response { raw, .. } => {
                            println!("{}", raw);
                            received = true;
                            break;
                        }
                        IncomingMessage::Notification { raw, .. } => {
                            println!("{}", raw);
                            received = true;
                            break;
                        }
                        IncomingMessage::Unknown(raw) => {
                            println!("{}", raw);
                            received = true;
                            break;
                        }
                    }
                } else {
                    break;
                }
            }

            proc.kill();
            if received {
                std::process::exit(0);
            } else {
                std::process::exit(2);
            }
        }

        "run-script" => {
            // Script runner executing JSON lines or commands
            let mut cmd = String::new();
            let mut cmd_args: Vec<String> = Vec::new();
            let mut cwd: Option<String> = None;
            let mut script_path = String::new();

            let mut i = 2;
            while i < args.len() {
                match args[i].as_str() {
                    "--cmd" => {
                        cmd = args[i + 1].clone();
                        i += 2;
                    }
                    "--arg" => {
                        cmd_args.push(args[i + 1].clone());
                        i += 2;
                    }
                    "--cwd" => {
                        cwd = Some(args[i + 1].clone());
                        i += 2;
                    }
                    "--script" => {
                        script_path = args[i + 1].clone();
                        i += 2;
                    }
                    _ => i += 1,
                }
            }

            let script_content = match fs::read_to_string(&script_path) {
                Ok(c) => c,
                Err(e) => {
                    eprintln!("Failed to read script file {}: {}", script_path, e);
                    std::process::exit(1);
                }
            };

            let mut proc = match LspProcess::spawn(&cmd, &cmd_args, cwd.as_deref()) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("Failed to spawn {}: {}", cmd, e);
                    std::process::exit(127);
                }
            };

            for line in script_content.lines() {
                let trimmed = line.trim();
                if trimmed.is_empty() || trimmed.starts_with('#') {
                    continue;
                }

                // format: SEND_REQ <json>
                // format: SEND_NOTIF <json>
                // format: WAIT_RESP <id> [timeout_ms]
                // format: WAIT_DIAG [timeout_ms]
                // format: SLEEP <ms>
                if let Some(req) = trimmed.strip_prefix("SEND_REQ ") {
                    if let Err(e) = proc.write_frame(req) {
                        eprintln!("SEND_REQ failed: {}", e);
                        proc.kill();
                        std::process::exit(1);
                    }
                } else if let Some(notif) = trimmed.strip_prefix("SEND_NOTIF ") {
                    if let Err(e) = proc.write_frame(notif) {
                        eprintln!("SEND_NOTIF failed: {}", e);
                        proc.kill();
                        std::process::exit(1);
                    }
                } else if let Some(wait_args) = trimmed.strip_prefix("WAIT_RESP ") {
                    let parts: Vec<&str> = wait_args.split_whitespace().collect();
                    let target_id = parts[0];
                    let timeout_ms = if parts.len() > 1 { parts[1].parse().unwrap_or(5000) } else { 5000 };
                    match proc.wait_for_response(target_id, Duration::from_millis(timeout_ms)) {
                        Some(resp) => println!("RESP:{}:{}", target_id, resp),
                        None => {
                            eprintln!("TIMEOUT waiting for resp {}", target_id);
                            println!("RESP:{}:TIMEOUT", target_id);
                        }
                    }
                } else if let Some(diag_arg) = trimmed.strip_prefix("WAIT_DIAG") {
                    let timeout_ms = diag_arg.trim().parse::<u64>().unwrap_or(5000);
                    match proc.wait_for_notification("textDocument/publishDiagnostics", Duration::from_millis(timeout_ms)) {
                        Some(notif) => println!("DIAG:{}", notif),
                        None => {
                            eprintln!("TIMEOUT waiting for diagnostics");
                            println!("DIAG:TIMEOUT");
                        }
                    }
                } else if let Some(sleep_arg) = trimmed.strip_prefix("SLEEP ") {
                    let ms = sleep_arg.trim().parse::<u64>().unwrap_or(100);
                    thread::sleep(Duration::from_millis(ms));
                }
            }

            proc.pump_messages();
            proc.kill();
            std::process::exit(0);
        }

        _ => {
            print_help();
            std::process::exit(1);
        }
    }
}
