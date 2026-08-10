use std::time::Duration;

use reqwest::Client;
use serde_json::Value;

use crate::error::{Result, RouterError};

pub struct ChatGptBackend {
    client: Client,
    base_url: String,
    api_key: String,
    _timeout: Duration,
}

impl ChatGptBackend {
    pub fn new(base_url: String, api_key: String, timeout: Duration) -> Self {
        Self {
            client: Client::builder()
                .timeout(timeout)
                .build()
                .expect("http client"),
            base_url,
            api_key,
            _timeout: timeout,
        }
    }

    pub async fn forward(
        &self,
        path: &str,
        body: Value,
    ) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.base_url.trim_end_matches('/'), path);
        let mut builder = self.client.post(&url).json(&body);
        if !self.api_key.is_empty() {
            builder = builder.header("Authorization", format!("Bearer {}", self.api_key));
        }
        let response = builder.send().await?;
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

    pub async fn forward_authorized(
        &self,
        path: &str,
        body: Value,
        auth: &str,
    ) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.base_url.trim_end_matches('/'), path);
        let mut builder = self.client.post(&url).json(&body);
        if !auth.is_empty() {
            builder = builder.header("Authorization", auth);
        } else if !self.api_key.is_empty() {
            builder = builder.header("Authorization", format!("Bearer {}", self.api_key));
        }
        let response = builder.send().await?;
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
