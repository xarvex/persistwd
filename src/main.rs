mod bindings;
mod cli;
mod config;
mod shadow;

use std::process::Stdio;

use anyhow::{Context, Result};
use clap::Parser;
use cli::{Cli, Command};
use config::Config;
use futures::{SinkExt, StreamExt};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use shadow::{populate_shadow, populate_shadow_hash, shadow_path};
use tokio::process;

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::read(cli.config.as_deref())?;

    let shadow_path = shadow_path();

    match cli.command {
        Command::PopulateHashes { passwd } => {
            for (username, path) in &config.users {
                if passwd {
                    match process::Command::new("passwd")
                        .arg(username)
                        .stdin(Stdio::inherit())
                        .status()
                        .await
                    {
                        Ok(status) => {
                            if let Some(code) = status.code() {
                                if let Some(message) = match code {
                                    0 => None,
                                    1 => Some("No permission"),
                                    2 => Some("Invalid options"),
                                    3 => Some("Unexpected failure"),
                                    4 => Some("passwd file missing"),
                                    5 => Some("passwd file busy"),
                                    6 => Some("Invalid argument to option"),
                                    _ => Some("Unknown failure"),
                                } {
                                    eprintln!("Error setting passwd for {}: {}", username, message);
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("Error setting passwd for {}: {}", username, e);
                        }
                    }
                }
                if let Err(e) = populate_shadow_hash(username, path) {
                    eprintln!("Error populating shadow entry for {}: {}", username, e)
                }
            }
        }
        Command::PopulateShadow => {
            if let Err(e) = populate_shadow(&config.users) {
                eprintln!("Error populating shadow: {}", e);
            }
        }
        Command::Watch => {
            for (username, path) in &config.users {
                if let Err(e) = populate_shadow_hash(username, path) {
                    eprintln!("Error populating shadow entry for {}: {}", username, e)
                }
            }

            let (mut sender, mut receiver) = futures::channel::mpsc::channel(1);

            let mut watcher = RecommendedWatcher::new(
                move |res| {
                    futures::executor::block_on(async {
                        if let Err(e) = sender.send(res).await {
                            eprintln!("Error sending response: {}", e);
                        };
                    })
                },
                notify::Config::default(),
            )
            .context("Failed initializing watcher")?;

            watcher
                .watch(shadow_path, RecursiveMode::NonRecursive)
                .context(format!(
                    "Failed to watch shadow file {}",
                    shadow_path.display()
                ))?;

            while let Some(res) = receiver.next().await {
                match res {
                    Ok(event) => {
                        if event.kind.is_create()
                            || event.kind.is_modify()
                            || event.kind.is_remove()
                        {
                            if event.kind.is_remove() {
                                // Not actually a race condition, as the removal is
                                // file /etc/shadow being overwritten by /etc/nshadow.
                                // Must create new watch as file descriptor has changed.
                                watcher
                                    .watch(shadow_path, RecursiveMode::NonRecursive)
                                    .context(format!(
                                        "Failed to watch shadow file {}",
                                        shadow_path.display()
                                    ))?;
                            }

                            for (username, path) in &config.users {
                                if let Err(e) = populate_shadow_hash(username, path) {
                                    eprintln!(
                                        "Error duplicating shadow entry for {}: {}",
                                        username, e
                                    )
                                }
                            }
                        }
                    }
                    Err(e) => eprintln!("Error watching shadow file: {}", e),
                }
            }
        }
    };

    Ok(())
}
