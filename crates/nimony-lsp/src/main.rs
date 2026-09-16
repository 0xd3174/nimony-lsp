use std::error::Error;
use lsp_server::Connection;

mod coords;
mod diagnostics;
mod server;

fn main() -> Result<(), Box<dyn Error + Send + Sync>> {
    eprintln!("[nimony-lsp] Starting Nimony Language Server...");

    let (connection, io_threads) = Connection::stdio();
    server::run(connection)?;
    io_threads.join()?;

    eprintln!("[nimony-lsp] Clean exit completed.");
    Ok(())
}
