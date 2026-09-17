use std::error::Error;
use lsp_server::Connection;

mod completion;
mod coords;
mod diagnostics;
mod formatting;
mod navigation;
mod server;
mod syntax;

fn main() -> Result<(), Box<dyn Error + Send + Sync>> {
    if std::env::var("NIMONY_LSP_DEBUG").is_ok() {
        eprintln!("[nimony-lsp] Starting Nimony Language Server...");
    }

    let (connection, io_threads) = Connection::stdio();
    server::run(connection)?;
    io_threads.join()?;

    if std::env::var("NIMONY_LSP_DEBUG").is_ok() {
        eprintln!("[nimony-lsp] Clean exit completed.");
    }
    Ok(())
}
