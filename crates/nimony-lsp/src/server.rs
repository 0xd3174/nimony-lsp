#![allow(dead_code)]

use std::collections::HashMap;
use std::error::Error;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use lsp_server::{Connection, ErrorCode, Message, Notification, RequestId, Response};
use lsp_types::*;

use crate::completion::CompletionEngine;
use crate::coords::LineIndex;
use crate::diagnostics::DiagnosticEngine;
use crate::formatting::FormattingEngine;
use crate::navigation::NavigationEngine;

#[derive(Debug, Clone)]
pub struct Document {
    pub uri: Url,
    pub path: PathBuf,
    pub version: i32,
    pub text: String,
    pub line_index: LineIndex,
}

impl Document {
    pub fn new(uri: Url, version: i32, text: String) -> Self {
        let path = uri
            .to_file_path()
            .unwrap_or_else(|_| PathBuf::from(uri.path()));
        let line_index = LineIndex::new(&text);
        Self {
            uri,
            path,
            version,
            text,
            line_index,
        }
    }

    pub fn apply_changes(&mut self, version: i32, changes: Vec<TextDocumentContentChangeEvent>) {
        self.version = version;
        for change in changes {
            match change.range {
                Some(range) => {
                    let start_byte = self.line_index.lsp_pos_to_byte_offset(&self.text, range.start);
                    let end_byte = self.line_index.lsp_pos_to_byte_offset(&self.text, range.end);

                    let start = start_byte.min(self.text.len());
                    let end = end_byte.min(self.text.len());
                    let (start, end) = if start <= end { (start, end) } else { (end, start) };

                    let start = clamp_char_boundary(&self.text, start);
                    let end = clamp_char_boundary(&self.text, end);

                    self.text.replace_range(start..end, &change.text);
                    self.line_index = LineIndex::new(&self.text);
                }
                None => {
                    self.text = change.text;
                    self.line_index = LineIndex::new(&self.text);
                }
            }
        }
    }
}

fn clamp_char_boundary(s: &str, mut idx: usize) -> usize {
    idx = idx.min(s.len());
    while idx > 0 && !s.is_char_boundary(idx) {
        idx -= 1;
    }
    idx
}

pub fn server_capabilities() -> ServerCapabilities {
    ServerCapabilities {
        text_document_sync: Some(TextDocumentSyncCapability::Options(
            TextDocumentSyncOptions {
                open_close: Some(true),
                change: Some(TextDocumentSyncKind::INCREMENTAL),
                will_save: Some(false),
                will_save_wait_until: Some(false),
                save: Some(TextDocumentSyncSaveOptions::SaveOptions(SaveOptions {
                    include_text: Some(false),
                })),
            },
        )),
        definition_provider: Some(OneOf::Left(true)),
        references_provider: Some(OneOf::Left(true)),
        hover_provider: Some(HoverProviderCapability::Simple(true)),
        document_highlight_provider: Some(OneOf::Left(true)),
        completion_provider: Some(CompletionOptions {
            resolve_provider: Some(false),
            trigger_characters: Some(vec![".".to_string(), ":".to_string()]),
            all_commit_characters: None,
            work_done_progress_options: Default::default(),
            completion_item: None,
        }),
        document_formatting_provider: Some(OneOf::Left(true)),
        ..Default::default()
    }
}

pub struct DebounceEvent {
    pub uri: Url,
    pub version: i32,
}

pub struct ServerState {
    pub documents: HashMap<Url, Document>,
    pub in_flight: Arc<Mutex<HashMap<RequestId, Arc<AtomicBool>>>>,
    pub shutdown_received: bool,
    pub project_root: Option<PathBuf>,
    pub diag_engine: DiagnosticEngine,
    pub nav_engine: NavigationEngine,
    pub completion_engine: CompletionEngine,
    pub formatting_engine: FormattingEngine,
}

pub fn run(connection: Connection) -> Result<(), Box<dyn Error + Send + Sync>> {
    let nimony_bin = match std::env::var("NIMONY_BIN") {
        Ok(b) => PathBuf::from(b),
        Err(_) => PathBuf::from("nimony"),
    };

    let nimpretty_bin = match std::env::var("NIMPRETTY_BIN") {
        Ok(b) => PathBuf::from(b),
        Err(_) => PathBuf::from("nimpretty"),
    };

    let mut state = ServerState {
        documents: HashMap::new(),
        in_flight: Arc::new(Mutex::new(HashMap::new())),
        shutdown_received: false,
        project_root: None,
        diag_engine: DiagnosticEngine::new(nimony_bin.clone()),
        nav_engine: NavigationEngine::new(nimony_bin),
        completion_engine: CompletionEngine::new(),
        formatting_engine: FormattingEngine::new(nimpretty_bin),
    };

    if let Ok(cwd) = std::env::current_dir() {
        crate::diagnostics::clean_stray_shadow_files(&cwd);
        crate::diagnostics::clean_stray_shadow_files(&cwd.join("tests/e2e/fixtures/basic_project"));
    }

    // Phase 1: Wait for initialize request
    let (init_id, init_params_value) = match connection.initialize_start() {
        Ok(pair) => pair,
        Err(e) => {
            let msg = format!("{e}");
            let code = if msg.contains("malformed")
                || msg.contains("key must be a string")
                || msg.contains("invalid JSON")
                || msg.contains("syntax")
                || msg.contains("expected")
                || msg.contains("channel is closed")
                || msg.contains("disconnected")
            {
                ErrorCode::ParseError as i32
            } else {
                ErrorCode::InvalidRequest as i32
            };
            let err_msg = if code == ErrorCode::ParseError as i32 {
                "Parse error"
            } else {
                "Invalid Request"
            };
            let resp = Response::new_err(RequestId::from(0), code, err_msg.to_string());
            let _ = connection.sender.send(Message::Response(resp));
            drop(connection);
            std::thread::sleep(Duration::from_millis(50));
            return Ok(());
        }
    };

    if let Ok(init_params) = serde_json::from_value::<InitializeParams>(init_params_value) {
        if let Some(folders) = init_params.workspace_folders {
            if let Some(first) = folders.first() {
                if let Ok(path) = first.uri.to_file_path() {
                    state.project_root = Some(path);
                }
            }
        }
        if state.project_root.is_none() {
            #[allow(deprecated)]
            if let Some(root_uri) = init_params.root_uri {
                if let Ok(path) = root_uri.to_file_path() {
                    state.project_root = Some(path);
                }
            }
        }
    }

    if let Some(ref root) = state.project_root {
        crate::diagnostics::clean_stray_shadow_files(root);
        crate::diagnostics::clean_stray_shadow_files(&root.join("tests/e2e/fixtures/basic_project"));
    }

    // Phase 2: Send initialize result response
    let init_result = InitializeResult {
        capabilities: server_capabilities(),
        server_info: Some(ServerInfo {
            name: "nimony-lsp".to_string(),
            version: Some(env!("CARGO_PKG_VERSION").to_string()),
        }),
    };
    connection
        .sender
        .send(Response::new_ok(init_id, init_result).into())?;

    let (trigger_tx, trigger_rx) = crossbeam_channel::unbounded::<DebounceEvent>();
    let (debounce_tx, debounce_rx) = crossbeam_channel::unbounded::<DebounceEvent>();

    std::thread::Builder::new()
        .name("debounce-worker".to_string())
        .spawn(move || {
            let mut pending: HashMap<Url, (i32, Instant)> = HashMap::new();

            loop {
                let now = Instant::now();
                let earliest = pending.values().map(|(_, deadline)| *deadline).min();

                let recv_res = match earliest {
                    Some(deadline) => {
                        if deadline <= now {
                            None
                        } else {
                            let timeout = deadline - now;
                            match trigger_rx.recv_timeout(timeout) {
                                Ok(evt) => Some(evt),
                                Err(crossbeam_channel::RecvTimeoutError::Timeout) => None,
                                Err(crossbeam_channel::RecvTimeoutError::Disconnected) => break,
                            }
                        }
                    }
                    None => match trigger_rx.recv() {
                        Ok(evt) => Some(evt),
                        Err(_) => break,
                    },
                };

                if let Some(evt) = recv_res {
                    let deadline = Instant::now() + Duration::from_millis(350);
                    pending.insert(evt.uri, (evt.version, deadline));
                }

                let now = Instant::now();
                let mut expired = Vec::new();
                pending.retain(|uri, (version, deadline)| {
                    if *deadline <= now {
                        expired.push((uri.clone(), *version));
                        false
                    } else {
                        true
                    }
                });

                for (uri, version) in expired {
                    if debounce_tx.send(DebounceEvent { uri, version }).is_err() {
                        return;
                    }
                }
            }
        })
        .expect("failed to spawn debounce worker");

    // Phase 3: Main Event Loop
    loop {
        crossbeam_channel::select! {
            recv(connection.receiver) -> msg => {
                let msg = match msg {
                    Ok(m) => m,
                    Err(_) => break, // Channel closed
                };

                match msg {
                    Message::Request(req) => {
                        if state.shutdown_received {
                            let err = Response::new_err(
                                req.id,
                                ErrorCode::InvalidRequest as i32,
                                "Server is shutting down".to_string(),
                            );
                            connection.sender.send(err.into())?;
                            continue;
                        }

                        match req.method.as_str() {
                            "shutdown" => {
                                state.shutdown_received = true;
                                if let Ok(mut map) = state.in_flight.lock() {
                                    map.clear();
                                }
                                crate::diagnostics::cleanup_all_active_shadows();
                                if let Some(ref root) = state.project_root {
                                    crate::diagnostics::clean_stray_shadow_files(root);
                                    crate::diagnostics::clean_stray_shadow_files(&root.join("tests/e2e/fixtures/basic_project"));
                                }
                                connection
                                    .sender
                                    .send(Response::new_ok(req.id, serde_json::Value::Null).into())?;
                            }
                            "textDocument/definition" => {
                                let cancel_token = Arc::new(AtomicBool::new(false));
                                if let Ok(mut map) = state.in_flight.lock() {
                                    map.insert(req.id.clone(), cancel_token.clone());
                                }
                                if let Ok(params) = serde_json::from_value::<GotoDefinitionParams>(req.params) {
                                    let uri = params.text_document_position_params.text_document.uri;
                                    let pos = params.text_document_position_params.position;
                                    let (path, text) = if let Some(doc) = state.documents.get(&uri) {
                                        (doc.path.clone(), doc.text.clone())
                                    } else {
                                        let p = uri.to_file_path().unwrap_or_else(|_| PathBuf::from(uri.path()));
                                        let t = std::fs::read_to_string(&p).unwrap_or_default();
                                        (p, t)
                                    };
                                    let nav = state.nav_engine.clone();
                                    let root = state.project_root.clone();
                                    let sender = connection.sender.clone();
                                    let in_flight = state.in_flight.clone();
                                    let req_id = req.id.clone();
                                    std::thread::spawn(move || {
                                        let resp = match nav.goto_definition(&path, &uri, &text, pos, root.as_deref(), Some(&cancel_token)) {
                                            Ok(res) => Response::new_ok(req_id.clone(), res),
                                            Err(e) => Response::new_err(req_id.clone(), ErrorCode::InternalError as i32, e),
                                        };
                                        let _ = sender.send(resp.into());
                                        if let Ok(mut map) = in_flight.lock() {
                                            map.remove(&req_id);
                                        }
                                    });
                                } else if let Ok(mut map) = state.in_flight.lock() {
                                    map.remove(&req.id);
                                }
                            }
                            "textDocument/references" => {
                                let cancel_token = Arc::new(AtomicBool::new(false));
                                if let Ok(mut map) = state.in_flight.lock() {
                                    map.insert(req.id.clone(), cancel_token.clone());
                                }
                                if let Ok(params) = serde_json::from_value::<ReferenceParams>(req.params) {
                                    let uri = params.text_document_position.text_document.uri;
                                    let pos = params.text_document_position.position;
                                    let inc_decl = params.context.include_declaration;
                                    let (path, text) = if let Some(doc) = state.documents.get(&uri) {
                                        (doc.path.clone(), doc.text.clone())
                                    } else {
                                        let p = uri.to_file_path().unwrap_or_else(|_| PathBuf::from(uri.path()));
                                        let t = std::fs::read_to_string(&p).unwrap_or_default();
                                        (p, t)
                                    };
                                    let nav = state.nav_engine.clone();
                                    let root = state.project_root.clone();
                                    let sender = connection.sender.clone();
                                    let in_flight = state.in_flight.clone();
                                    let req_id = req.id.clone();
                                    std::thread::spawn(move || {
                                        let resp = match nav.find_references(&path, &uri, &text, pos, inc_decl, root.as_deref(), Some(&cancel_token)) {
                                            Ok(res) => Response::new_ok(req_id.clone(), res),
                                            Err(e) => Response::new_err(req_id.clone(), ErrorCode::InternalError as i32, e),
                                        };
                                        let _ = sender.send(resp.into());
                                        if let Ok(mut map) = in_flight.lock() {
                                            map.remove(&req_id);
                                        }
                                    });
                                } else if let Ok(mut map) = state.in_flight.lock() {
                                    map.remove(&req.id);
                                }
                            }
                            "textDocument/hover" => {
                                let cancel_token = Arc::new(AtomicBool::new(false));
                                if let Ok(mut map) = state.in_flight.lock() {
                                    map.insert(req.id.clone(), cancel_token.clone());
                                }
                                if let Ok(params) = serde_json::from_value::<HoverParams>(req.params) {
                                    let uri = params.text_document_position_params.text_document.uri;
                                    let pos = params.text_document_position_params.position;
                                    let (path, text) = if let Some(doc) = state.documents.get(&uri) {
                                        (doc.path.clone(), doc.text.clone())
                                    } else {
                                        let p = uri.to_file_path().unwrap_or_else(|_| PathBuf::from(uri.path()));
                                        let t = std::fs::read_to_string(&p).unwrap_or_default();
                                        (p, t)
                                    };
                                    let nav = state.nav_engine.clone();
                                    let root = state.project_root.clone();
                                    let sender = connection.sender.clone();
                                    let in_flight = state.in_flight.clone();
                                    let req_id = req.id.clone();
                                    std::thread::spawn(move || {
                                        let resp = match nav.hover(&path, &uri, &text, pos, root.as_deref(), Some(&cancel_token)) {
                                            Ok(res) => Response::new_ok(req_id.clone(), res),
                                            Err(e) => Response::new_err(req_id.clone(), ErrorCode::InternalError as i32, e),
                                        };
                                        let _ = sender.send(resp.into());
                                        if let Ok(mut map) = in_flight.lock() {
                                            map.remove(&req_id);
                                        }
                                    });
                                } else if let Ok(mut map) = state.in_flight.lock() {
                                    map.remove(&req.id);
                                }
                            }
                            "textDocument/documentHighlight" => {
                                if let Ok(params) = serde_json::from_value::<DocumentHighlightParams>(req.params) {
                                    let uri = params.text_document_position_params.text_document.uri;
                                    let pos = params.text_document_position_params.position;
                                    let text = if let Some(doc) = state.documents.get(&uri) {
                                        doc.text.clone()
                                    } else {
                                        let p = uri.to_file_path().unwrap_or_else(|_| PathBuf::from(uri.path()));
                                        std::fs::read_to_string(&p).unwrap_or_default()
                                    };
                                    let resp = match state.nav_engine.document_highlight(&text, pos) {
                                        Ok(res) => Response::new_ok(req.id, res),
                                        Err(e) => Response::new_err(req.id, ErrorCode::InternalError as i32, e),
                                    };
                                    connection.sender.send(resp.into())?;
                                }
                            }
                            "textDocument/completion" => {
                                if let Ok(params) = serde_json::from_value::<CompletionParams>(req.params) {
                                    let uri = params.text_document_position.text_document.uri;
                                    let pos = params.text_document_position.position;
                                    let text = if let Some(doc) = state.documents.get(&uri) {
                                        doc.text.clone()
                                    } else {
                                        let p = uri.to_file_path().unwrap_or_else(|_| PathBuf::from(uri.path()));
                                        std::fs::read_to_string(&p).unwrap_or_default()
                                    };
                                    let items = state.completion_engine.complete(&text, pos);
                                    let resp = Response::new_ok(req.id, items);
                                    connection.sender.send(resp.into())?;
                                }
                            }
                            "textDocument/formatting" => {
                                let cancel_token = Arc::new(AtomicBool::new(false));
                                if let Ok(mut map) = state.in_flight.lock() {
                                    map.insert(req.id.clone(), cancel_token.clone());
                                }
                                if let Ok(params) = serde_json::from_value::<DocumentFormattingParams>(req.params) {
                                    let uri = params.text_document.uri;
                                    let text = if let Some(doc) = state.documents.get(&uri) {
                                        doc.text.clone()
                                    } else {
                                        let p = uri.to_file_path().unwrap_or_else(|_| PathBuf::from(uri.path()));
                                        std::fs::read_to_string(&p).unwrap_or_default()
                                    };
                                    let formatter = state.formatting_engine.clone();
                                    let sender = connection.sender.clone();
                                    let in_flight = state.in_flight.clone();
                                    let req_id = req.id.clone();
                                    std::thread::spawn(move || {
                                        let resp = match formatter.format(&text, &params.options, Some(&cancel_token)) {
                                            Ok(edits) => Response::new_ok(req_id.clone(), edits),
                                            Err(e) => Response::new_err(req_id.clone(), ErrorCode::InternalError as i32, e),
                                        };
                                        let _ = sender.send(resp.into());
                                        if let Ok(mut map) = in_flight.lock() {
                                            map.remove(&req_id);
                                        }
                                    });
                                } else if let Ok(mut map) = state.in_flight.lock() {
                                    map.remove(&req.id);
                                }
                            }
                            _ => {
                                let err = Response::new_err(
                                    req.id,
                                    ErrorCode::MethodNotFound as i32,
                                    format!("Method not found: {}", req.method),
                                );
                                connection.sender.send(err.into())?;
                            }
                        }
                    }
                    Message::Notification(notif) => {
                        match notif.method.as_str() {
                            "initialized" => {
                                if std::env::var("NIMONY_LSP_DEBUG").is_ok() {
                                    eprintln!("[nimony-lsp] Client initialized notification received.");
                                }
                            }
                            "exit" => {
                                crate::diagnostics::cleanup_all_active_shadows();
                                if let Some(ref root) = state.project_root {
                                    crate::diagnostics::clean_stray_shadow_files(root);
                                    crate::diagnostics::clean_stray_shadow_files(&root.join("tests/e2e/fixtures/basic_project"));
                                }
                                if let Ok(cwd) = std::env::current_dir() {
                                    crate::diagnostics::clean_stray_shadow_files(&cwd);
                                }
                                if state.shutdown_received {
                                    return Ok(());
                                } else {
                                    std::process::exit(1);
                                }
                            }
                            "$/cancelRequest" => {
                                if let Ok(params) = serde_json::from_value::<CancelParams>(notif.params) {
                                    let req_id = match params.id {
                                        NumberOrString::Number(n) => RequestId::from(n),
                                        NumberOrString::String(s) => RequestId::from(s),
                                    };
                                    if let Ok(map) = state.in_flight.lock() {
                                        if let Some(token) = map.get(&req_id) {
                                            token.store(true, Ordering::SeqCst);
                                        }
                                    }
                                }
                            }
                            "textDocument/didOpen" => {
                                if let Ok(params) = serde_json::from_value::<DidOpenTextDocumentParams>(notif.params) {
                                    let uri = params.text_document.uri;
                                    let version = params.text_document.version;
                                    let text = params.text_document.text;
                                    let doc = Document::new(uri.clone(), version, text);
                                    state.documents.insert(uri.clone(), doc);

                                    // Trigger 350ms debounce
                                    let _ = trigger_tx.send(DebounceEvent { uri, version });
                                }
                            }
                            "textDocument/didChange" => {
                                if let Ok(params) = serde_json::from_value::<DidChangeTextDocumentParams>(notif.params) {
                                    let uri = params.text_document.uri;
                                    let version = params.text_document.version;
                                    if let Some(doc) = state.documents.get_mut(&uri) {
                                        doc.apply_changes(version, params.content_changes);
                                    }

                                    // Trigger 350ms debounce
                                    let _ = trigger_tx.send(DebounceEvent { uri, version });
                                }
                            }
                            "textDocument/didSave" => {
                                if let Ok(params) = serde_json::from_value::<DidSaveTextDocumentParams>(notif.params) {
                                    let uri = params.text_document.uri;
                                    let (path, text, version) = if let Some(doc) = state.documents.get(&uri) {
                                        (doc.path.clone(), doc.text.clone(), doc.version)
                                    } else {
                                        let path = uri.to_file_path().unwrap_or_else(|_| PathBuf::from(uri.path()));
                                        let text = std::fs::read_to_string(&path).unwrap_or_default();
                                        (path, text, 0)
                                    };

                                    let engine = state.diag_engine.clone();
                                    let project_root = state.project_root.clone();
                                    let sender = connection.sender.clone();
                                    std::thread::spawn(move || {
                                        if let Ok(parsed) = engine.check_on_save(
                                            &path,
                                            &uri,
                                            &text,
                                            project_root.as_deref(),
                                            None,
                                        ) {
                                            for (u, diags) in parsed.by_uri {
                                                let notif = Notification {
                                                    method: "textDocument/publishDiagnostics".to_string(),
                                                    params: serde_json::to_value(PublishDiagnosticsParams {
                                                        uri: u,
                                                        diagnostics: diags,
                                                        version: Some(version),
                                                    })
                                                    .unwrap_or_default(),
                                                };
                                                let _ = sender.send(notif.into());
                                            }
                                        }
                                    });
                                }
                            }
                            "textDocument/didClose" => {
                                if let Ok(params) = serde_json::from_value::<DidCloseTextDocumentParams>(notif.params) {
                                    let uri = params.text_document.uri;
                                    state.documents.remove(&uri);

                                    // Clear diagnostics for closed document
                                    let clear_params = PublishDiagnosticsParams {
                                        uri,
                                        diagnostics: vec![],
                                        version: None,
                                    };
                                    let clear_notif = Notification {
                                        method: "textDocument/publishDiagnostics".to_string(),
                                        params: serde_json::to_value(clear_params).unwrap_or_default(),
                                    };
                                    let _ = connection.sender.send(clear_notif.into());
                                }
                            }
                            _ => {}
                        }
                    }
                    Message::Response(_) => {}
                }
            }
            recv(debounce_rx) -> debounce_evt => {
                if let Ok(evt) = debounce_evt {
                    if let Some(doc) = state.documents.get(&evt.uri) {
                        if doc.version == evt.version {
                            let engine = state.diag_engine.clone();
                            let doc_clone = doc.clone();
                            let project_root = state.project_root.clone();
                            let sender = connection.sender.clone();
                            std::thread::spawn(move || {
                                if let Ok(parsed) = engine.check_live_shadow(
                                    &doc_clone.path,
                                    &doc_clone.uri,
                                    &doc_clone.text,
                                    project_root.as_deref(),
                                    None,
                                ) {
                                    for (u, diags) in parsed.by_uri {
                                        let notif = Notification {
                                            method: "textDocument/publishDiagnostics".to_string(),
                                            params: serde_json::to_value(PublishDiagnosticsParams {
                                                uri: u,
                                                diagnostics: diags,
                                                version: Some(doc_clone.version),
                                            })
                                            .unwrap_or_default(),
                                        };
                                        let _ = sender.send(notif.into());
                                    }
                                }
                            });
                        }
                    }
                }
            }
        }
    }

    crate::diagnostics::cleanup_all_active_shadows();
    if let Some(ref root) = state.project_root {
        crate::diagnostics::clean_stray_shadow_files(root);
        crate::diagnostics::clean_stray_shadow_files(&root.join("tests/e2e/fixtures/basic_project"));
    }
    if let Ok(cwd) = std::env::current_dir() {
        crate::diagnostics::clean_stray_shadow_files(&cwd);
    }

    Ok(())
}
