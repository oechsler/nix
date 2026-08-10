use std::time::Duration;

use reqwest::Client;
use serde_json::Value;

use crate::error::{Result, RouterError};

pub struct OllamaBackend {
    client: Client,
    base_url: String,
    _timeout: Duration,
}

impl OllamaBackend {
    pub fn new(base_url: String, timeout: Duration) -> Self {
        Self {
            client: Client::builder()
                .timeout(timeout)
                .build()
                .expect("http client"),
            base_url,
            _timeout: timeout,
        }
    }

    pub async fn forward(
        &self,
        path: &str,
        body: Value,
    ) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.base_url.trim_end_matches('/'), path);
        let response = self.client.post(&url).json(&body).send().await?;
        let status = response.status();
        if !status.is_success() {
            return Err(RouterError::Upstream {
                status: status.as_u16(),
                body: response.text().await.unwrap_or_default(),
                url,
            });
        }
        Ok(response)
    }
}
