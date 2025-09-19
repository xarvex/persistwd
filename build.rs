use std::{env, path::PathBuf};

use bindgen::Builder;

fn main() {
    let bindings = Builder::default()
        .header("bindings.h")
        .allowlist_function("endspent")
        .allowlist_function("fclose")
        .allowlist_function("fdopen")
        .allowlist_function("getspent")
        .allowlist_function("getspnam")
        .allowlist_function("open")
        .allowlist_function("putspent")
        .allowlist_function("setspent")
        .allowlist_type("spwd")
        .allowlist_var("O_CREAT")
        .allowlist_var("O_TRUNC")
        .allowlist_var("O_WRONLY")
        .allowlist_var("SHADOW")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("Failed to generate bindings");

    let out_path = PathBuf::from(env::var_os("OUT_DIR").expect("Failure using OUT_DIR, not set"));
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Failed to write bindings");
}
