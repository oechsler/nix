#![deny(unsafe_op_in_unsafe_fn)]

use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use std::ffi::{CStr, CString};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::ptr;

#[link(name = "ldap")]
#[link(name = "pam")]
unsafe extern "C" {}

const PAM_SUCCESS: c_int = 0;
const PAM_OPEN_ERR: c_int = 1;
const PAM_AUTH_ERR: c_int = 9;
const PAM_USER_UNKNOWN: c_int = 10;
const PAM_IGNORE: c_int = 25;
const PAM_AUTHTOK: c_int = 6;
const LDAP_SUCCESS: c_int = 0;
const LDAP_INVALID_CREDENTIALS: c_int = 49;
const LDAP_SERVER_DOWN: c_int = 81;
const LDAP_CONNECT_ERROR: c_int = 91;
const LDAP_TIMEOUT: c_int = 85;
const LDAP_LOCAL_ERROR: c_int = -2;
const LDAP_OPT_PROTOCOL_VERSION: c_int = 17;
const LDAP_OPT_X_TLS_CACERTFILE: c_int = 0x6002;
const LDAP_OPT_X_TLS_REQUIRE_CERT: c_int = 0x6006;
const LDAP_OPT_X_TLS_DEMAND: c_int = 2;
const LOG_AUTH: c_int = 32 << 3;
const LOG_ERR: c_int = 3;
const LOG_INFO: c_int = 6;

#[repr(C)]
pub struct PamHandle {
    _private: [u8; 0],
}

#[repr(C)]
struct Ldap {
    _private: [u8; 0],
}

#[derive(Clone, Copy)]
enum ConnectionMode {
    Plaintext,
    Tls,
}

impl ConnectionMode {
    fn from_uri(uri: &str) -> Option<Self> {
        match uri {
            value if value.starts_with("ldap://") => Some(Self::Plaintext),
            value if value.starts_with("ldaps://") => Some(Self::Tls),
            _ => None,
        }
    }

    fn uses_tls(self) -> bool {
        matches!(self, Self::Tls)
    }
}

unsafe extern "C" {
    fn openlog(ident: *const c_char, option: c_int, facility: c_int);
    fn syslog(priority: c_int, format: *const c_char, ...);
    fn pam_get_user(handle: *mut PamHandle, user: *mut *const c_char, prompt: *const c_char) -> c_int;
    fn pam_get_authtok(
        handle: *mut PamHandle,
        item: c_int,
        token: *mut *const c_char,
        prompt: *const c_char,
    ) -> c_int;
    fn ldap_initialize(handle: *mut *mut Ldap, uri: *const c_char) -> c_int;
    fn ldap_set_option(handle: *mut Ldap, option: c_int, value: *const c_void) -> c_int;
    fn ldap_simple_bind_s(handle: *mut Ldap, dn: *const c_char, password: *const c_char) -> c_int;
    fn ldap_err2string(error: c_int) -> *const c_char;
    fn ldap_unbind_ext_s(
        handle: *mut Ldap,
        server_controls: *const *mut c_void,
        client_controls: *const *mut c_void,
    ) -> c_int;

}

fn log_message(priority: c_int, message: &'static [u8]) {
    unsafe {
        openlog(ptr::null(), 0x01, LOG_AUTH);
        syslog(priority, message.as_ptr() as *const c_char);
    }
}

fn log_status(status: c_int) {
    static FORMAT: &[u8] = b"pam_lldap: LDAP bind failed with status %d (%s)\0";
    unsafe {
        openlog(ptr::null(), 0x01, LOG_AUTH);
        let description = ldap_err2string(status);
        syslog(LOG_ERR, FORMAT.as_ptr() as *const c_char, status, description);
    }
}

fn log_step(step: &'static [u8], status: c_int) {
    static FORMAT: &[u8] = b"pam_lldap: %s returned %d (%s)\0";
    unsafe {
        openlog(ptr::null(), 0x01, LOG_AUTH);
        syslog(
            LOG_ERR,
            FORMAT.as_ptr() as *const c_char,
            step.as_ptr() as *const c_char,
            status,
            ldap_err2string(status),
        );
    }
}

struct Options {
    uri: CString,
    connection_mode: ConnectionMode,
    user_dn: CString,
    cache: String,
    user: CString,
}

// PAM passes module arguments as key=value strings. Missing or malformed
// arguments are a configuration error, never a reason to guess defaults.
fn options(argc: c_int, argv: *const *const c_char) -> Option<Options> {
    if argc < 0 || (argc > 0 && argv.is_null()) {
        return None;
    }
    let mut uri: Option<(CString, ConnectionMode)> = None;
    let mut user_dn = None;
    let mut cache = None;
    let mut user = None;
    for index in 0..argc {
        let argument = unsafe { *argv.add(index as usize) };
        if argument.is_null() {
            return None;
        }
        let value = unsafe { CStr::from_ptr(argument) }.to_str().ok()?;
        if let Some(value) = value.strip_prefix("uri=") {
            let mode = ConnectionMode::from_uri(value)?;
            uri = Some((CString::new(value).ok()?, mode));
        } else if let Some(value) = value.strip_prefix("user_dn=") {
            user_dn = CString::new(value).ok();
        } else if let Some(value) = value.strip_prefix("cache=") {
            cache = Some(value.to_owned());
        } else if let Some(value) = value.strip_prefix("user=") {
            user = CString::new(value).ok();
        }
    }
    Some(Options {
        uri: uri.as_ref().map(|(uri, _)| uri.clone())?,
        connection_mode: uri.map(|(_, mode)| mode)?,
        user_dn: user_dn?,
        cache: cache?,
        user: user?,
    })
}

// Return the LDAP status unchanged: an invalid online password must never
// fall through to the offline cache.
fn ldap_status(options: &Options, password: &[u8]) -> c_int {
    let mut handle = ptr::null_mut();
    let mut version: c_int = 3;
    let password = match CString::new(password) {
        Ok(password) => password,
        Err(_) => return LDAP_INVALID_CREDENTIALS,
    };
    let status = unsafe {
        // OpenLDAP needs TLS defaults before creating an ldaps:// handle.
        // Plain ldap:// deliberately skips this block entirely.
        if options.connection_mode.uses_tls() {
            let global_ca = ldap_set_option(
                ptr::null_mut(),
                LDAP_OPT_X_TLS_CACERTFILE,
                b"/etc/ssl/certs/ca-certificates.crt\0".as_ptr() as *const c_void,
            );
            if global_ca != LDAP_SUCCESS {
                log_step(b"ldap_set_option(CACERTFILE)\0", global_ca);
            }
        }
        let mut status = ldap_initialize(&mut handle, options.uri.as_ptr());
        if status != LDAP_SUCCESS {
            log_step(b"ldap_initialize\0", status);
        }
        if status == LDAP_SUCCESS {
            status = ldap_set_option(handle, LDAP_OPT_PROTOCOL_VERSION, &version as *const _ as *const c_void);
            if status != LDAP_SUCCESS {
                log_step(b"ldap_set_option(PROTOCOL_VERSION)\0", status);
            }
        }
        if status == LDAP_SUCCESS && options.connection_mode.uses_tls() {
            let tls: c_int = LDAP_OPT_X_TLS_DEMAND;
            status = ldap_set_option(handle, LDAP_OPT_X_TLS_REQUIRE_CERT, &tls as *const _ as *const c_void);
            if status != LDAP_SUCCESS {
                log_step(b"ldap_set_option(REQUIRE_CERT)\0", status);
            }
        }
        if status == LDAP_SUCCESS {
            status = ldap_simple_bind_s(handle, options.user_dn.as_ptr(), password.as_ptr());
            if status == LDAP_SUCCESS {
                log_message(LOG_INFO, b"pam_lldap: LDAP password accepted\0");
            } else if status == LDAP_INVALID_CREDENTIALS {
                log_message(LOG_INFO, b"pam_lldap: LDAP password rejected\0");
            } else {
                log_status(status);
            }
        }
        if !handle.is_null() {
            ldap_unbind_ext_s(handle, ptr::null(), ptr::null());
        }
        status
    };
    status
}

fn cache_matches(path: &Path, password: &[u8]) -> bool {
    let Ok(hash) = fs::read_to_string(path) else { return false };
    let Ok(hash) = PasswordHash::new(hash.trim()) else { return false };
    Argon2::default().verify_password(password, &hash).is_ok()
}

// Write a fresh Argon2id verifier to a temporary file, then rename it. The
// rename prevents a crash from leaving a partially written authentication
// cache.
fn cache_password(path: &Path, password: &[u8]) -> bool {
    if let Some(parent) = path.parent() {
        if fs::create_dir_all(parent).is_err() {
            log_message(LOG_ERR, b"pam_lldap: cache directory creation failed\0");
            return false;
        }
    }
    let Ok(password) = std::str::from_utf8(password) else {
        log_message(LOG_ERR, b"pam_lldap: Argon2 cache hash failed\0");
        return false;
    };
    let salt = password_hash::SaltString::generate(&mut password_hash::rand_core::OsRng);
    let Ok(hash) = Argon2::default().hash_password(password.as_bytes(), &salt) else {
        log_message(LOG_ERR, b"pam_lldap: Argon2 cache hash failed\0");
        return false;
    };
    let hash = hash.to_string();
    let temporary = path.with_extension("new");
    let Ok(mut file) = OpenOptions::new().create(true).truncate(true).write(true).mode(0o600).open(&temporary) else {
        log_message(LOG_ERR, b"pam_lldap: cache temporary file open failed\0");
        return false;
    };
    if file.write_all(hash.as_bytes()).is_err() || file.write_all(b"\n").is_err() {
        log_message(LOG_ERR, b"pam_lldap: cache temporary file write failed\0");
        return false;
    }
    if fs::rename(temporary, path).is_err() {
        log_message(LOG_ERR, b"pam_lldap: cache rename failed\0");
        return false;
    }
    true
}

#[no_mangle]
pub unsafe extern "C" fn pam_sm_authenticate(
    handle: *mut PamHandle,
    _flags: c_int,
    argc: c_int,
    argv: *const *const c_char,
) -> c_int {
    // This module authenticates one already-declared local Unix account. It
    // does not create users, resolve groups, or provide NSS functionality.
    let Some(options) = options(argc, argv) else {
        return PAM_OPEN_ERR;
    };
    let mut user = ptr::null();
    if unsafe { pam_get_user(handle, &mut user, ptr::null()) } != PAM_SUCCESS || user.is_null() {
        return PAM_USER_UNKNOWN;
    }
    if unsafe { CStr::from_ptr(user) } != options.user.as_c_str() {
        return PAM_IGNORE;
    }
    let mut token = ptr::null();
    if unsafe { pam_get_authtok(handle, PAM_AUTHTOK, &mut token, ptr::null()) } != PAM_SUCCESS
        || token.is_null()
    {
        return PAM_AUTH_ERR;
    }
    let password = unsafe { CStr::from_ptr(token) }.to_bytes();
    match ldap_status(&options, password) {
        LDAP_SUCCESS => {
            if cache_password(Path::new(&options.cache), password) {
                log_message(LOG_INFO, b"pam_lldap: offline cache updated\0");
            } else {
                log_message(LOG_ERR, b"pam_lldap: failed to update offline cache\0");
            }
            PAM_SUCCESS
        }
        LDAP_INVALID_CREDENTIALS => PAM_AUTH_ERR,
        // Only transport failures may use the cached verifier. A bad password
        // received from a reachable LDAP server is always rejected.
        LDAP_SERVER_DOWN | LDAP_CONNECT_ERROR | LDAP_TIMEOUT | LDAP_LOCAL_ERROR | -1 => {
            if cache_matches(Path::new(&options.cache), password) {
                log_message(LOG_INFO, b"pam_lldap: offline cache accepted\0");
                PAM_SUCCESS
            } else {
                log_message(LOG_ERR, b"pam_lldap: LDAP unavailable and offline cache rejected\0");
                PAM_AUTH_ERR
            }
        }
        _ => PAM_AUTH_ERR,
    }
}

#[no_mangle]
pub extern "C" fn pam_sm_setcred(_: *mut PamHandle, _: c_int, _: c_int, _: *const *const c_char) -> c_int { PAM_SUCCESS }

#[no_mangle]
pub extern "C" fn pam_sm_acct_mgmt(_: *mut PamHandle, _: c_int, _: c_int, _: *const *const c_char) -> c_int { PAM_SUCCESS }

#[no_mangle]
pub extern "C" fn pam_sm_open_session(_: *mut PamHandle, _: c_int, _: c_int, _: *const *const c_char) -> c_int { PAM_IGNORE }

#[no_mangle]
pub extern "C" fn pam_sm_close_session(_: *mut PamHandle, _: c_int, _: c_int, _: *const *const c_char) -> c_int { PAM_IGNORE }
