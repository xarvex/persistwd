use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub users: HashMap<String, PathBuf>,
}

impl Config {
    pub fn read(config: Option<&Path>) -> Result<Self> {
        let path = config.unwrap_or(Path::new("/etc/persistwd/config.toml"));

        toml::from_str(
            &fs::read_to_string(path)
                .context(format!("Failed to read config at {}", path.display()))?,
        )
        .context(format!("Failed to parse config at {}", path.display()))
    }
}
