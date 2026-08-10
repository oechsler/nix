use thiserror::Error;

#[derive(Error, Debug)]
pub enum RouterError {
    #[error("config: {0}")]
    Config(String),

    #[error("bad request: {0}")]
    BadRequest(String),

    #[error("model not found: {0}")]
    ModelNotFound(String),

    #[error("unsupported provider: {0}")]
    UnsupportedProvider(String),

    #[error("all models failed")]
    AllModelsFailed,

    #[error("upstream {url}: HTTP {status}: {body}")]
    Upstream {
        status: u16,
        body: String,
        url: String,
    },

    #[error("backend unavailable: {provider}: {detail}")]
    BackendUnavailable { provider: String, detail: String },

    #[error("classification failed: {0}")]
    ClassificationFailed(String),

    #[error("auth error: {0}")]
    Auth(String),

    #[error("http: {0}")]
    Http(#[from] reqwest::Error),

    #[error("json: {0}")]
    Json(#[from] serde_json::Error),

    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error("toml: {0}")]
    Toml(#[from] toml::de::Error),

    #[error("timeout: {0}")]
    Timeout(String),
}

pub type Result<T> = std::result::Result<T, RouterError>;

impl RouterError {
    pub fn status_code(&self) -> u16 {
        match self {
            Self::Config(_) | Self::BadRequest(_) | Self::ModelNotFound(_) | Self::ClassificationFailed(_) => 400,
            Self::BackendUnavailable { .. } | Self::Upstream { .. } | Self::Http(_) => 502,
            Self::Auth(_) => 401,
            Self::UnsupportedProvider(_) => 501,
            Self::AllModelsFailed => 503,
            Self::Json(_) | Self::Io(_) => 500,
            Self::Toml(_) => 400,
            Self::Timeout(_) => 504,
        }
    }
}

impl axum::response::IntoResponse for RouterError {
    fn into_response(self) -> axum::response::Response {
        let status = axum::http::StatusCode::from_u16(self.status_code())
            .unwrap_or(axum::http::StatusCode::INTERNAL_SERVER_ERROR);
        let body = serde_json::json!({
            "error": self.to_string(),
        });
        (status, axum::Json(body)).into_response()
    }
}
