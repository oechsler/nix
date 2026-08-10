use std::sync::Arc;
use std::time::Duration;

use axum::routing::{get, post};
use axum::Router;
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use opencode_router::backend::chatgpt::ChatGptBackend;
use opencode_router::backend::litellm::LiteLlmBackend;
use opencode_router::backend::ollama::OllamaBackend;
use opencode_router::config::load_config;
use opencode_router::handlers::{chat, health, models};
use opencode_router::state::SharedState;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,opencode_router=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config_path = std::env::var("OPENCODER_CONFIG")
        .unwrap_or_else(|_| "/etc/opencode-router/config.toml".to_string());
    let config = load_config(std::path::Path::new(&config_path))?;
    info!(path = config_path, "loaded configuration");

    let litellm_url = std::env::var("LITELLM_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:8000/v1".to_string());
    let litellm_key = std::env::var("LITELLM_API_KEY").unwrap_or_default();

    let litellm_backend = LiteLlmBackend::new(
        litellm_url,
        litellm_key,
        Duration::from_secs(120),
    );

    let chatgpt_backend = ChatGptBackend::new(
        config.chatgpt.responses_url.clone(),
        String::new(),
        Duration::from_secs(300),
    );

    let ollama_backend = OllamaBackend::new(
        config.classifier.local.url.clone(),
        Duration::from_secs(30),
    );

    let state = SharedState::new(config, litellm_backend, chatgpt_backend, ollama_backend);
    let state = Arc::new(state);

    let host = &state.config.server.host;
    let port = state.config.server.port;
    let addr = format!("{}:{}", host, port);

    let app = Router::new()
        .route("/health", get(health::health))
        .route("/v1/models", get(models::list_models))
        .route("/v1/chat/completions", post(chat::chat_completions))
        .with_state(state);

    info!(addr = addr, "starting server");
    let listener = TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
