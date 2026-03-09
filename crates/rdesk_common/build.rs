//! Build script for rdesk_common.
//!
//! Compiles protobuf definitions for the `rdesk.message` and `rdesk.rendezvous`
//! packages using `prost-build`, outputting generated Rust code to `OUT_DIR`.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_dir = "../../proto";

    let proto_files = &[
        format!("{}/message.proto", proto_dir),
        format!("{}/rendezvous.proto", proto_dir),
    ];

    // Re-run if any proto file changes.
    for proto in proto_files {
        println!("cargo:rerun-if-changed={}", proto);
    }

    prost_build::Config::new()
        .compile_protos(proto_files, &[proto_dir])?;

    Ok(())
}
