use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};

use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub shadow: Option<PathBuf>,
    pub users: HashMap<String, PathBuf>,
}

impl Config {
    pub fn read(config: Option<&Path>) -> Self {
        toml::from_str(
            &fs::read_to_string(config.unwrap_or(Path::new("/etc/persistwd/config.toml"))).unwrap(),
        )
        .unwrap()
    }
}
