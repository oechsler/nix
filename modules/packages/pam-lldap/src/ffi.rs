use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

#[link(name = "ldap")]
#[link(name = "pam")]
unsafe extern "C" {}

pub(crate) const PAM_SUCCESS: c_int = 0;
pub(crate) const PAM_OPEN_ERR: c_int = 1;
pub(crate) const PAM_AUTH_ERR: c_int = 9;
pub(crate) const PAM_USER_UNKNOWN: c_int = 10;
pub(crate) const PAM_IGNORE: c_int = 25;
pub(crate) const PAM_AUTHTOK: c_int = 6;

pub(crate) const LDAP_SUCCESS: c_int = 0;
pub(crate) const LDAP_INVALID_CREDENTIALS: c_int = 49;
pub(crate) const LDAP_SERVER_DOWN: c_int = 81;
pub(crate) const LDAP_CONNECT_ERROR: c_int = 91;
pub(crate) const LDAP_TIMEOUT: c_int = 85;
pub(crate) const LDAP_LOCAL_ERROR: c_int = -2;
pub(crate) const LDAP_OPT_PROTOCOL_VERSION: c_int = 17;
pub(crate) const LDAP_OPT_X_TLS_CACERTFILE: c_int = 0x6002;
pub(crate) const LDAP_OPT_X_TLS_REQUIRE_CERT: c_int = 0x6006;
pub(crate) const LDAP_OPT_X_TLS_DEMAND: c_int = 2;

const LOG_AUTH: c_int = 32 << 3;
const LOG_ERR: c_int = 3;
const LOG_INFO: c_int = 6;

#[repr(C)]
pub(crate) struct PamHandle {
    _private: [u8; 0],
}

#[repr(C)]
pub(crate) struct Ldap {
    _private: [u8; 0],
}

unsafe extern "C" {
    pub(crate) fn openlog(ident: *const c_char, option: c_int, facility: c_int);
    pub(crate) fn syslog(priority: c_int, format: *const c_char, ...);
    pub(crate) fn pam_get_user(handle: *mut PamHandle, user: *mut *const c_char, prompt: *const c_char) -> c_int;
    pub(crate) fn pam_get_authtok(
        handle: *mut PamHandle,
        item: c_int,
        token: *mut *const c_char,
        prompt: *const c_char,
    ) -> c_int;
    pub(crate) fn ldap_initialize(handle: *mut *mut Ldap, uri: *const c_char) -> c_int;
    pub(crate) fn ldap_set_option(handle: *mut Ldap, option: c_int, value: *const c_void) -> c_int;
    pub(crate) fn ldap_simple_bind_s(handle: *mut Ldap, dn: *const c_char, password: *const c_char) -> c_int;
    pub(crate) fn ldap_err2string(error: c_int) -> *const c_char;
    pub(crate) fn ldap_unbind_ext_s(handle: *mut Ldap, server_controls: *const *mut c_void, client_controls: *const *mut c_void) -> c_int;
}

pub(crate) fn log_info(message: &'static [u8]) {
    unsafe {
        openlog(ptr::null(), 0x01, LOG_AUTH);
        syslog(LOG_INFO, message.as_ptr() as *const c_char);
    }
}

pub(crate) fn log_error(message: &'static [u8]) {
    unsafe {
        openlog(ptr::null(), 0x01, LOG_AUTH);
        syslog(LOG_ERR, message.as_ptr() as *const c_char);
    }
}

pub(crate) fn log_status(step: &'static [u8], status: c_int) {
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
