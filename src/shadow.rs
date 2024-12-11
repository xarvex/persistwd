use std::{
    collections::HashMap,
    ffi::{CStr, CString},
    fs::{self, DirBuilder, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    os::unix::fs::{DirBuilderExt, OpenOptionsExt},
    path::{Path, PathBuf},
    sync::OnceLock,
};

use anyhow::{anyhow, Context, Result};

use crate::bindings;

fn c_shadow_path() -> &'static CStr {
    static C_STR: OnceLock<&CStr> = OnceLock::new();
    C_STR.get_or_init(|| {
        CStr::from_bytes_with_nul(bindings::SHADOW)
            .unwrap_or_else(|_| panic!("Fatal parsing shadow path '{:?}'", bindings::SHADOW))
    })
}

pub fn shadow_path() -> &'static PathBuf {
    static PATH: OnceLock<PathBuf> = OnceLock::new();
    PATH.get_or_init(|| {
        Path::new(&c_shadow_path().to_str().unwrap_or_else(|_| {
            panic!(
                "Fatal decoding shadow path '{:?}'",
                c_shadow_path().to_string_lossy()
            )
        }))
        .to_path_buf()
    })
}

fn get_shadow(username: &str) -> Result<Option<bindings::spwd>> {
    let c_username = CString::new(username)
        .context(format!("Failed to create C-style string '{}'", username))?;
    let spwd = unsafe { bindings::getspnam(c_username.as_ptr()) };

    Ok(match spwd.is_null() {
        true => None,
        false => Some(unsafe { *spwd }),
    })
}

fn get_shadow_hash(username: &str) -> Result<Option<String>> {
    Ok(match get_shadow(username)? {
        Some(spwd) => match spwd.sp_pwdp.is_null() {
            true => None,
            false => Some(
                unsafe { CStr::from_ptr(spwd.sp_pwdp) }
                    .to_str()
                    .context(format!("Failed to parse shadow hash for {}", username))?
                    .to_owned(),
            ),
        },
        None => None,
    })
}

pub fn populate_shadow_hash(username: &str, path: &Path) -> Result<()> {
    if let Some(dir) = path.parent() {
        DirBuilder::new()
            .recursive(true)
            .mode(0o0)
            .create(dir)
            .context("Failed to create shadow hash directory")?;
    }

    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .mode(0o0)
        .open(path)
        .context(format!(
            "Failed to create shadow hash file for {}",
            username
        ))?;

    file.write_all(
        (get_shadow_hash(username)
            .context(format!("Failed to get shadow hash for {}", username))?
            .unwrap_or("".to_string())
            + "\n")
            .as_bytes(),
    )
    .context(format!("Failed to write shadow hash file for {}", username))?;
    file.flush()
        .context(format!("Failed to flush changes to disk for {}", username))?;

    Ok(())
}

pub fn populate_shadow(users: &HashMap<String, PathBuf>) -> Result<()> {
    let shadow_path = shadow_path();
    let new_shadow_name = format!("n{}", {
        let name = shadow_path.file_name().context(format!(
            "Failed to get file name from '{}'",
            shadow_path.display()
        ))?;
        name.to_str().context(format!(
            "Failed to encode file name '{}'",
            name.to_string_lossy()
        ))?
    });
    let new_shadow_path = shadow_path.with_file_name(&new_shadow_name);

    let c_stream = {
        let path = new_shadow_path.to_str().context(format!(
            "Failed to encode path string '{}'",
            new_shadow_path.display()
        ))?;
        let c_path =
            CString::new(path).context(format!("Failed to create C-style string '{}'", path))?;
        let ptr_path = c_path.as_ptr();

        let flags =
            (bindings::O_CREAT as i32) | (bindings::O_TRUNC as i32) | (bindings::O_WRONLY as i32);
        let fd = unsafe { bindings::open(ptr_path, flags, 0) };
        if fd == -1 {
            return Err(anyhow!("Could not open new shadow file"));
        }

        let mode = b"w\0".as_ptr() as *const i8;
        unsafe { bindings::fdopen(fd, mode) }
    };

    if !c_stream.is_null() {
        unsafe {
            bindings::setspent();
        }

        while let Some(mut entry) = {
            let spwd = unsafe { bindings::getspent() };
            if spwd.is_null() {
                None
            } else {
                Some(unsafe { *spwd })
            }
        } {
            let mut raw_hash: Option<*mut i8> = None;

            if let Ok(name) = unsafe { CStr::from_ptr(entry.sp_namp) }.to_str() {
                if let Some(path) = users.get(name) {
                    match File::open(path) {
                        Ok(file) => {
                            let mut reader = BufReader::new(file);
                            let mut hash = String::new();

                            match reader.read_line(&mut hash) {
                                Ok(_) => match CString::new(hash.trim_end_matches("\n")) {
                                    Ok(c_hash) => {
                                        let raw = c_hash.into_raw();
                                        entry.sp_pwdp = raw;
                                        raw_hash = Some(raw);
                                    }
                                    Err(e) => {
                                        eprintln!(
                                            "Error encoding shadow hash file for {}: {}",
                                            name, e
                                        )
                                    }
                                },
                                Err(e) => {
                                    eprintln!("Error reading shadow hash file for {}: {}", name, e)
                                }
                            }
                        }
                        Err(e) => eprintln!("Error opening shadow hash file for {}: {}", name, e),
                    }
                }
            }

            if unsafe { bindings::putspent(&entry, c_stream) } != 0 {
                eprintln!(
                    "Error populating shadow entry for {}",
                    unsafe { CStr::from_ptr(entry.sp_namp) }.to_string_lossy()
                );
            }

            if let Some(raw) = raw_hash {
                let _ = unsafe { CString::from_raw(raw) };
            }
        }

        unsafe {
            bindings::endspent();
            bindings::fclose(c_stream);
        }
    }

    fs::rename(&new_shadow_path, shadow_path).context("Failed to replace shadow file")?;
    Ok(())
}
