use axum::extract::State;
use axum::response::IntoResponse;
use axum::Json;
use serde_json::json;
use std::sync::Arc;

use crate::models::ModelRegistry;
use crate::state::SharedState;

pub async fn list_models(State(state): State<Arc<SharedState>>) -> impl IntoResponse {
    let registry = ModelRegistry::from_config(&state.config);
    let models = registry.list_visible_models(state.use_local_classifier);
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    let response = json!({
        "object": "list",
        "data": models.iter().map(|m| {
            json!({
                "id": m.id,
                "object": m.object,
                "created": now,
                "owned_by": m.owned_by,
            })
        }).collect::<Vec<_>>(),
    });
    Json(response)
}
