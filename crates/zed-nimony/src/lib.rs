use zed::settings::LspSettings;
use zed_extension_api::{self as zed, LanguageServerId, Result};

struct NimonyExtension;

impl zed::Extension for NimonyExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let binary_settings = LspSettings::for_worktree(language_server_id.as_ref(), worktree)
            .ok()
            .and_then(|lsp_settings| lsp_settings.binary);

        let (path, args) = if let Some(settings) = binary_settings {
            (settings.path, settings.arguments.unwrap_or_default())
        } else {
            (None, Vec::new())
        };

        let command = match path {
            Some(p) => p,
            None => worktree
                .which("nimony-lsp")
                .ok_or_else(|| "nimony-lsp binary not found in PATH. Ensure nimony-lsp is installed or configured in Zed settings.".to_string())?,
        };

        Ok(zed::Command {
            command,
            args,
            env: Default::default(),
        })
    }

    fn language_server_workspace_configuration(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<zed::serde_json::Value>> {
        let settings = LspSettings::for_worktree(language_server_id.as_ref(), worktree)
            .ok()
            .and_then(|lsp_settings| lsp_settings.settings.clone())
            .unwrap_or_default();

        Ok(Some(zed::serde_json::json!({
            "nimony": settings
        })))
    }
}

zed::register_extension!(NimonyExtension);
