#![deny(unsafe_op_in_unsafe_fn)]

mod cache;
mod config;
mod ffi;
mod ldap;

use std::ffi::CStr;
use std::path::Path;
use std::ptr;

use config::Options;
use ffi::{PamHandle, PAM_AUTH_ERR, PAM_IGNORE, PAM_OPEN_ERR, PAM_SUCCESS, PAM_USER_UNKNOWN};

#[no_mangle]
pub unsafe extern "C" fn pam_sm_authenticate(
    handle: *mut PamHandle,
    _flags: i32,
    argc: i32,
    argv: *const *const std::os::raw::c_char,
) -> i32 {
    let Some(options) = (unsafe { Options::from_pam_args(argc, argv) }) else {
        return PAM_OPEN_ERR;
    };

    let mut user = ptr::null();
    if unsafe { ffi::pam_get_user(handle, &mut user, ptr::null()) } != PAM_SUCCESS || user.is_null() {
        return PAM_USER_UNKNOWN;
    }
    if unsafe { CStr::from_ptr(user) } != options.user.as_c_str() {
        return PAM_IGNORE;
    }

    let mut token = ptr::null();
    if unsafe { ffi::pam_get_authtok(handle, ffi::PAM_AUTHTOK, &mut token, ptr::null()) } != PAM_SUCCESS
        || token.is_null()
    {
        return PAM_AUTH_ERR;
    }

    let password = unsafe { CStr::from_ptr(token) }.to_bytes();
    match ldap::check_password(&options, password) {
        ffi::LDAP_SUCCESS => {
            if cache::update(Path::new(&options.cache), password) {
                ffi::log_info(b"pam_lldap: offline cache updated\0");
            } else {
                ffi::log_error(b"pam_lldap: failed to update offline cache\0");
            }
            PAM_SUCCESS
        }
        ffi::LDAP_INVALID_CREDENTIALS => PAM_AUTH_ERR,
        ffi::LDAP_SERVER_DOWN
        | ffi::LDAP_CONNECT_ERROR
        | ffi::LDAP_TIMEOUT
        | ffi::LDAP_LOCAL_ERROR
        | -1 => {
            if cache::matches(Path::new(&options.cache), password) {
                ffi::log_info(b"pam_lldap: offline cache accepted\0");
                PAM_SUCCESS
            } else {
                ffi::log_error(b"pam_lldap: LDAP unavailable and offline cache rejected\0");
                PAM_AUTH_ERR
            }
        }
        _ => PAM_AUTH_ERR,
    }
}

#[no_mangle]
pub extern "C" fn pam_sm_setcred(_: *mut PamHandle, _: i32, _: i32, _: *const *const std::os::raw::c_char) -> i32 {
    PAM_SUCCESS
}

#[no_mangle]
pub extern "C" fn pam_sm_acct_mgmt(_: *mut PamHandle, _: i32, _: i32, _: *const *const std::os::raw::c_char) -> i32 {
    PAM_SUCCESS
}

#[no_mangle]
pub extern "C" fn pam_sm_open_session(_: *mut PamHandle, _: i32, _: i32, _: *const *const std::os::raw::c_char) -> i32 {
    PAM_IGNORE
}

#[no_mangle]
pub extern "C" fn pam_sm_close_session(_: *mut PamHandle, _: i32, _: i32, _: *const *const std::os::raw::c_char) -> i32 {
    PAM_IGNORE
}
