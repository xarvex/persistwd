mod config;
mod shadow;

use std::path::{Path, PathBuf};

use clap::Parser;
use futures::{SinkExt, StreamExt};
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use shadow::duplicate_shadow;

use self::config::Config;

#[derive(Debug, Parser)]
#[command(version, about, long_about = None)]
struct Args {
    #[arg(short, long)]
    config: Option<PathBuf>,
}

fn main() {
    let args = Args::parse();
    let config = Config::read(args.config.as_deref());

    // Initial creation for each user.
    for (username, path) in &config.users {
        duplicate_shadow(username, path)
    }

    futures::executor::block_on(async {
        let (mut sender, mut receiver) = futures::channel::mpsc::channel(1);

        let mut watcher = RecommendedWatcher::new(
            move |res| {
                futures::executor::block_on(async {
                    sender.send(res).await.expect("Fatal sending response");
                })
            },
            notify::Config::default(),
        )
        .expect("Fatal initializing watcher");

        let shadow_path = config
            .shadow
            .unwrap_or(Path::new("/etc/shadow").to_path_buf());

        watcher
            .watch(shadow_path.as_path(), RecursiveMode::NonRecursive)
            .expect("Fatal watching path");

        while let Some(res) = receiver.next().await {
            match res {
                Ok(event) => {
                    if event.kind.is_create() || event.kind.is_modify() || event.kind.is_remove() {
                        if event.kind.is_remove() {
                            // Not actually a race condition, as the removal is
                            // file /etc/shadow being overwritten by /etc/nshadow.
                            // Must create new watch as file descriptor has changed.
                            watcher
                                .watch(&shadow_path, RecursiveMode::NonRecursive)
                                .expect("Fatal watching path");
                        }

                        // TODO: Possibly figure out which user changed?
                        for (username, path) in &config.users {
                            duplicate_shadow(username, path)
                        }
                    }
                }
                Err(e) => eprintln!("Watch error: {}", e),
            }
        }
    })
}
