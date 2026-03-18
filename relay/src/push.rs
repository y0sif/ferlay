#![allow(dead_code)]
/// FCM push notification forwarding (stub).
///
/// In the future, when a paired device is offline and has an FCM token,
/// the relay can send a push notification to wake the app.
///
/// For now, this is a no-op placeholder.
pub async fn send_push_notification(_fcm_token: &str, _payload: &str) {
    // TODO: Implement FCM push notification via reqwest
    // let fcm_key = std::env::var("FCM_SERVER_KEY").ok();
    // if let Some(key) = fcm_key {
    //     reqwest::Client::new()
    //         .post("https://fcm.googleapis.com/fcm/send")
    //         .header("Authorization", format!("key={}", key))
    //         .json(&serde_json::json!({
    //             "to": fcm_token,
    //             "data": { "payload": payload }
    //         }))
    //         .send()
    //         .await
    //         .ok();
    // }
    tracing::debug!("Push notification stub called (not implemented)");
}
