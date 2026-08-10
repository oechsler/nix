use std::time::{Duration, SystemTime, UNIX_EPOCH};

use reqwest::Client;
use serde_json::Value;

use crate::config::ChatGptConfig;
use crate::error::{Result, RouterError};

pub struct OpenAiAuth {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_ms: u64,
    pub account_id: String,
}

pub struct OpenAiAuthManager {
    client: Client,
    config: ChatGptConfig,
}

impl OpenAiAuthManager {
    pub fn new(config: ChatGptConfig) -> Self {
        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .expect("http client"),
            config,
        }
    }

    pub async fn get_auth(&self) -> Result<Option<OpenAiAuth>> {
        let auth = self.load_auth()?;
        let Some(mut auth) = auth else {
            return Ok(None);
        };

        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        if auth.expires_ms <= now_ms + 60_000 {
            self.refresh_token(&mut auth).await?;
            self.save_auth(&auth)?;
        }

        if auth.account_id.is_empty() {
            auth.account_id = decode_account_id(&auth.access_token, &self.config.account_claim_url);
        }

        if auth.account_id.is_empty() {
            return Ok(None);
        }

        Ok(Some(auth))
    }

    fn load_auth(&self) -> Result<Option<OpenAiAuth>> {
        let content = match std::fs::read_to_string(&self.config.auth_file) {
            Ok(c) => c,
            Err(_) => return Ok(None),
        };
        let data: Value = serde_json::from_str(&content)?;
        let openai = data.get("openai");
        let Some(openai) = openai else {
            return Ok(None);
        };
        if !openai.is_object() || openai.get("type").and_then(|t| t.as_str()) != Some("oauth") {
            return Ok(None);
        }

        let access_token = openai
            .get("access")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let refresh_token = openai
            .get("refresh")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let expires_ms = openai
            .get("expires")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let account_id = openai
            .get("accountId")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        Ok(Some(OpenAiAuth {
            access_token,
            refresh_token,
            expires_ms,
            account_id,
        }))
    }

    async fn refresh_token(&self, auth: &mut OpenAiAuth) -> Result<()> {
        let response = self
            .client
            .post(&self.config.token_url)
            .form(&[
                ("grant_type", "refresh_token"),
                ("refresh_token", &auth.refresh_token),
                ("client_id", &self.config.client_id),
            ])
            .header("Content-Type", "application/x-www-form-urlencoded")
            .send()
            .await?;
        if !response.status().is_success() {
            return Err(RouterError::Auth("OpenAI token refresh failed".to_string()));
        }
        let tokens: Value = response.json().await?;
        auth.access_token = tokens["access_token"]
            .as_str()
            .unwrap_or("")
            .to_string();
        auth.refresh_token = tokens["refresh_token"]
            .as_str()
            .unwrap_or("")
            .to_string();
        let expires_in = tokens["expires_in"].as_u64().unwrap_or(3600);
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        auth.expires_ms = now_ms + expires_in * 1000;
        Ok(())
    }

    fn save_auth(&self, auth: &OpenAiAuth) -> Result<()> {
        let content = std::fs::read_to_string(&self.config.auth_file).unwrap_or_else(|_| "{}".to_string());
        let mut data: Value = serde_json::from_str(&content).unwrap_or_else(|_| serde_json::json!({}));
        data["openai"] = serde_json::json!({
            "type": "oauth",
            "access": auth.access_token,
            "refresh": auth.refresh_token,
            "expires": auth.expires_ms,
            "accountId": auth.account_id,
        });
        std::fs::write(&self.config.auth_file, serde_json::to_string_pretty(&data).unwrap_or_default())?;
        Ok(())
    }
}

fn decode_account_id(token: &str, claim_url: &str) -> String {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() < 2 {
        return String::new();
    }
    let payload = parts[1];
    let padded = format!("{}{}", payload, "=".repeat((4 - payload.len() % 4) % 4));
    let decoded = match base64_decode(&padded) {
        Some(d) => d,
        None => return String::new(),
    };
    let json_str = String::from_utf8_lossy(&decoded);
    let json: Value = match serde_json::from_str(&json_str) {
        Ok(j) => j,
        Err(_) => return String::new(),
    };
    json.get(claim_url)
        .and_then(|c| c.get("chatgpt_account_id"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

fn base64_decode(input: &str) -> Option<Vec<u8>> {
    let table = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = Vec::new();
    let mut buf: u32 = 0;
    let mut bits = 0;
    for &byte in input.as_bytes() {
        if byte == b'=' {
            break;
        }
        let val = table.iter().position(|&b| b == byte)? as u32;
        buf = (buf << 6) | val;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            output.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }
    Some(output)
}
