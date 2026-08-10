use axum::extract::State;
use axum::response::IntoResponse;
use axum::Json;
use serde_json::json;
use std::sync::Arc;

use crate::state::SharedState;

pub async fn health(State(state): State<Arc<SharedState>>) -> impl IntoResponse {
    let uptime = state.uptime();
    let degraded = state.degraded_providers().await;
    let banned = state.banned_models().await;

    let response = json!({
        "status": "healthy",
        "uptime_seconds": uptime.as_secs(),
        "degraded_providers": degraded,
        "banned_models": banned,
    });
    Json(response)
}
