use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Clone, Copy)]
pub(crate) enum ConnectionMode {
    Plaintext,
    Tls,
}

impl ConnectionMode {
    pub(crate) fn from_uri(uri: &str) -> Option<Self> {
        match uri {
            value if value.starts_with("ldap://") => Some(Self::Plaintext),
            value if value.starts_with("ldaps://") => Some(Self::Tls),
            _ => None,
        }
    }

    pub(crate) fn uses_tls(self) -> bool {
        matches!(self, Self::Tls)
    }
}

pub(crate) struct Options {
    pub(crate) uri: CString,
    pub(crate) connection_mode: ConnectionMode,
    pub(crate) user_dn: CString,
    pub(crate) cache: String,
    pub(crate) user: CString,
}

impl Options {
    // PAM passes module arguments as key=value strings. Missing or malformed
    // arguments are a configuration error, never a reason to guess defaults.
    pub(crate) unsafe fn from_pam_args(argc: i32, argv: *const *const c_char) -> Option<Self> {
        if argc < 0 || (argc > 0 && argv.is_null()) {
            return None;
        }
        let mut uri = None;
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
                uri = Some((CString::new(value).ok()?, ConnectionMode::from_uri(value)?));
            } else if let Some(value) = value.strip_prefix("user_dn=") {
                user_dn = CString::new(value).ok();
            } else if let Some(value) = value.strip_prefix("cache=") {
                cache = Some(value.to_owned());
            } else if let Some(value) = value.strip_prefix("user=") {
                user = CString::new(value).ok();
            }
        }
        Some(Self {
            uri: uri.as_ref().map(|(uri, _)| uri.clone())?,
            connection_mode: uri.map(|(_, mode)| mode)?,
            user_dn: user_dn?,
            cache: cache?,
            user: user?,
        })
    }
}
