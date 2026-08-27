//! End-to-end: a controller connects to a host over QUIC, completes the Noise
//! handshake, authenticates, and forwards an input event.
//!
//! Everything runs over loopback with real certificate verification — the
//! controller pins the host's generated trust anchor rather than disabling
//! verification, so these also serve as a check that the verifying path is
//! actually usable end to end.

use std::time::Duration;

use rdesk_common::config::AppConfig;
use rdesk_common::password::hash_password;
use rdesk_common::protos::message::message::Union;
use rdesk_core::{DirectTarget, RemoteClient, RemoteServer, SessionState};
use rdesk_net::{ServerCertificate, ServerVerification};

/// Name the host's generated certificate is issued for.
const HOST_NAME: &str = "host.rdesk.test";

const PASSWORD: &str = "correct horse battery staple";

/// Cap every handshake so a regression fails instead of hanging.
const TIMEOUT: Duration = Duration::from_secs(10);

fn host_config() -> AppConfig {
    AppConfig {
        device_id: "123456789".to_string(),
        permanent_password: Some(hash_password(PASSWORD).expect("hash the host password")),
        ..AppConfig::default()
    }
}

fn controller_config() -> AppConfig {
    AppConfig {
        device_id: "987654321".to_string(),
        ..AppConfig::default()
    }
}

/// Start a host and keep accepting connections for the test's duration.
async fn spawn_host(config: AppConfig) -> (std::sync::Arc<RemoteServer>, DirectTarget) {
    let server = RemoteServer::start(
        "127.0.0.1:0".parse().unwrap(),
        ServerCertificate::self_signed([HOST_NAME]),
        &config,
    )
    .await
    .expect("host starts listening");
    let server = std::sync::Arc::new(server);

    let target = DirectTarget::new(server.local_addr().unwrap(), HOST_NAME).with_verification(
        ServerVerification::CustomRoots(vec![server.self_signed_anchor().unwrap().clone()]),
    );

    let accepting = server.clone();
    tokio::spawn(async move {
        // Rejected logins surface here as errors; keep serving either way.
        while accepting.is_listening() {
            let _ = accepting.accept_connection().await;
        }
    });

    (server, target)
}

#[tokio::test]
async fn controller_with_the_right_password_reaches_an_active_session() {
    let (server, target) = spawn_host(host_config()).await;

    let client = tokio::time::timeout(
        TIMEOUT,
        RemoteClient::connect_direct(target, PASSWORD, &controller_config()),
    )
    .await
    .expect("connect settles")
    .expect("a correct password is accepted");

    assert_eq!(client.session().get_state(), SessionState::Active);

    client.disconnect().await;
    server.stop().await;
}

#[tokio::test]
async fn controller_with_the_wrong_password_is_rejected() {
    let (server, target) = spawn_host(host_config()).await;

    let err = tokio::time::timeout(
        TIMEOUT,
        RemoteClient::connect_direct(target, "not the password", &controller_config()),
    )
    .await
    .expect("connect settles")
    // `.err()` rather than `expect_err`: RemoteClient is not Debug.
    .err()
    .expect("a wrong password must not produce a session");

    let chain = format!("{err:#}");
    assert!(
        chain.contains("authentication"),
        "expected an authentication failure, got: {chain}"
    );
    // The host must not disclose *why* the attempt failed.
    assert!(
        !chain.contains("password did not match"),
        "rejection leaked the reason: {chain}"
    );

    server.stop().await;
}

#[tokio::test]
async fn input_events_reach_the_host_over_the_authenticated_channel() {
    let (server, target) = spawn_host(host_config()).await;

    let client = RemoteClient::connect_direct(target, PASSWORD, &controller_config())
        .await
        .expect("connect");

    // Find the host-side session that was just created.
    let session_id = {
        let mut id = None;
        for _ in 0..100 {
            if server.active_session_count().await > 0 {
                id = Some(());
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        id.expect("host registered the session");
        // Only one session exists in this test.
        server
            .session_ids()
            .await
            .into_iter()
            .next()
            .expect("one session id")
    };

    client.send_mouse_event(rdesk_common::protos::message::MouseEvent {
        x: 42,
        y: 99,
        mask: 1,
        modifiers: 0,
        event_type: 0,
    });

    let message = tokio::time::timeout(TIMEOUT, server.recv_control(&session_id))
        .await
        .expect("the event arrives")
        .expect("control message decodes");

    match message.union {
        Some(Union::MouseEvent(event)) => {
            assert_eq!((event.x, event.y, event.mask), (42, 99, 1));
        }
        other => panic!("expected a MouseEvent, got {other:?}"),
    }

    client.disconnect().await;
    server.stop().await;
}

#[tokio::test]
async fn a_host_without_a_password_refuses_to_listen() {
    let config = AppConfig {
        device_id: "123456789".to_string(),
        permanent_password: None,
        ..AppConfig::default()
    };

    let err = RemoteServer::start(
        "127.0.0.1:0".parse().unwrap(),
        ServerCertificate::self_signed([HOST_NAME]),
        &config,
    )
    .await
    .err()
    .expect("a host with no password must not accept connections");

    assert!(
        err.to_string().contains("permanent_password"),
        "got: {err:#}"
    );
}
