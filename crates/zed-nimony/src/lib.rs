use zed_extension_api as zed;

struct NimonyExtension;

impl zed::Extension for NimonyExtension {
    fn new() -> Self {
        Self
    }
}

zed::register_extension!(NimonyExtension);
