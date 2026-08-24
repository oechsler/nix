use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

use crate::ffi;

pub(crate) fn matches(path: &Path, password: &[u8]) -> bool {
    let Ok(hash) = fs::read_to_string(path) else {
        return false;
    };
    let Ok(hash) = PasswordHash::new(hash.trim()) else {
        return false;
    };
    Argon2::default().verify_password(password, &hash).is_ok()
}

// Write a fresh Argon2id verifier to a temporary file, then rename it. The
// rename prevents a crash from leaving a partially written authentication
// cache.
pub(crate) fn update(path: &Path, password: &[u8]) -> bool {
    if let Some(parent) = path.parent() {
        if fs::create_dir_all(parent).is_err() {
            ffi::log_error(b"pam_lldap: cache directory creation failed\0");
            return false;
        }
    }
    let Ok(password) = std::str::from_utf8(password) else {
        ffi::log_error(b"pam_lldap: Argon2 cache hash failed\0");
        return false;
    };
    let salt = password_hash::SaltString::generate(&mut password_hash::rand_core::OsRng);
    let Ok(hash) = Argon2::default().hash_password(password.as_bytes(), &salt) else {
        ffi::log_error(b"pam_lldap: Argon2 cache hash failed\0");
        return false;
    };

    let temporary = path.with_extension("new");
    let Ok(mut file) = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)
    else {
        ffi::log_error(b"pam_lldap: cache temporary file open failed\0");
        return false;
    };
    if file.write_all(hash.to_string().as_bytes()).is_err() || file.write_all(b"\n").is_err() {
        ffi::log_error(b"pam_lldap: cache temporary file write failed\0");
        return false;
    }
    if fs::rename(temporary, path).is_err() {
        ffi::log_error(b"pam_lldap: cache rename failed\0");
        return false;
    }
    true
}
