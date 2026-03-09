use anyhow::Result;
use clap::Parser;
use tracing::info;
use tracing_subscriber::EnvFilter;

/// rdesk signaling and relay server entrypoint.
#[derive(Debug, Parser)]
#[command(name = "rdesk-server")]
#[command(about = "Stub signaling and relay server for rdesk MVP")]
struct Args {
    #[arg(long, default_value = "0.0.0.0")]
    host: String,
    #[arg(long, default_value_t = 21116)]
    signaling_port: u16,
    #[arg(long, default_value_t = 21117)]
    relay_port: u16,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    info!(
        host = %args.host,
        signaling_port = args.signaling_port,
        relay_port = args.relay_port,
        "starting rdesk server stub"
    );

    tokio::signal::ctrl_c().await?;
    info!("shutdown signal received");
    Ok(())
}
