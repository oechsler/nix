use std::ffi::CString;
use std::os::raw::c_void;
use std::ptr;

use crate::config::{ConnectionMode, Options};
use crate::ffi;

// Return the LDAP status unchanged: an invalid online password must never
// fall through to the offline cache.
pub(crate) fn check_password(options: &Options, password: &[u8]) -> i32 {
    let Ok(password) = CString::new(password) else {
        return ffi::LDAP_INVALID_CREDENTIALS;
    };
    let mut handle = ptr::null_mut();
    let mut version: i32 = 3;

    let status = unsafe {
        if options.connection_mode.uses_tls() {
            let status = ffi::ldap_set_option(
                ptr::null_mut(),
                ffi::LDAP_OPT_X_TLS_CACERTFILE,
                b"/etc/ssl/certs/ca-certificates.crt\0".as_ptr() as *const c_void,
            );
            if status != ffi::LDAP_SUCCESS {
                ffi::log_status(b"ldap_set_option(CACERTFILE)\0", status);
            }
        }

        let mut status = ffi::ldap_initialize(&mut handle, options.uri.as_ptr());
        if status != ffi::LDAP_SUCCESS {
            ffi::log_status(b"ldap_initialize\0", status);
        }
        if status == ffi::LDAP_SUCCESS {
            status = ffi::ldap_set_option(
                handle,
                ffi::LDAP_OPT_PROTOCOL_VERSION,
                &version as *const _ as *const c_void,
            );
        }
        if status == ffi::LDAP_SUCCESS && matches!(options.connection_mode, ConnectionMode::Tls) {
            let tls = ffi::LDAP_OPT_X_TLS_DEMAND;
            status = ffi::ldap_set_option(
                handle,
                ffi::LDAP_OPT_X_TLS_REQUIRE_CERT,
                &tls as *const _ as *const c_void,
            );
        }
        if status == ffi::LDAP_SUCCESS {
            status = ffi::ldap_simple_bind_s(handle, options.user_dn.as_ptr(), password.as_ptr());
        }
        if !handle.is_null() {
            ffi::ldap_unbind_ext_s(handle, ptr::null(), ptr::null());
        }
        status
    };

    if status == ffi::LDAP_SUCCESS {
        ffi::log_info(b"pam_lldap: LDAP password accepted\0");
    } else if status == ffi::LDAP_INVALID_CREDENTIALS {
        ffi::log_info(b"pam_lldap: LDAP password rejected\0");
    } else {
        ffi::log_status(b"ldap_simple_bind_s\0", status);
    }
    status
}
