use std::{
    ffi,
    fs::{DirBuilder, OpenOptions},
    io::Write,
    os::unix::fs::{DirBuilderExt, OpenOptionsExt},
    path::Path,
};

// TODO: check error codes.
// Has been verified for memory safety.
// Still, must create tests.
fn get_shadow_hash(username: &str) -> Option<String> {
    // Do not free, data is owned by shadow.
    let spwd: *mut libc::spwd = {
        let user = ffi::CString::new(username).unwrap();
        unsafe { libc::getspnam(user.as_ptr()) }
    };
    if spwd.is_null() {
        return None;
    }

    let pwdp = unsafe { (*spwd).sp_pwdp };
    if pwdp.is_null() {
        return None;
    }

    let hash = unsafe { ffi::CStr::from_ptr(pwdp) }.to_str().unwrap();

    Some(hash.to_owned())
}

pub(super) fn duplicate_shadow(username: &str, path: &Path) -> () {
    if let Some(dir) = path.parent() {
        DirBuilder::new()
            .recursive(true)
            .mode(0)
            .create(dir)
            .unwrap();
    }

    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .mode(0)
        .open(path)
        .unwrap();
    file.write_all((get_shadow_hash(username).unwrap() + "\n").as_bytes())
        .unwrap();
    file.flush().unwrap()
}
