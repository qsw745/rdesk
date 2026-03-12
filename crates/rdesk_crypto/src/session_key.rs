//! Session key derivation.
//!
//! Derives a 32-byte symmetric session key from a shared secret and a
//! context string using an HKDF-like construction built on SHA-256.
//!
//! The construction follows the "extract-then-expand" paradigm of RFC 5869:
//!
//!   1. **Extract**: `prk = HMAC-SHA256(salt, shared_secret)`
//!      where `salt` is a fixed domain-separation string.
//!   2. **Expand**: `okm = HMAC-SHA256(prk, context || 0x01)`
//!      truncated to 32 bytes (one block, so a single iteration suffices).

use tracing::debug;

/// Fixed salt used during the extract step for domain separation.
const HKDF_SALT: &[u8] = b"rdesk-session-key-v1";

/// Derive a 32-byte session key from `shared_secret` and `context`.
///
/// * `shared_secret` -- the raw key material (e.g. from a DH exchange).
/// * `context` -- application-specific context bytes (e.g. "client-to-server").
///
/// The output is deterministic for a given `(shared_secret, context)` pair.
pub fn derive_session_key(shared_secret: &[u8], context: &[u8]) -> [u8; 32] {
    // Extract
    let prk = hmac_sha256(HKDF_SALT, shared_secret);

    // Expand (single iteration -- we only need 32 bytes)
    let mut info = Vec::with_capacity(context.len() + 1);
    info.extend_from_slice(context);
    info.push(0x01);

    let okm = hmac_sha256(&prk, &info);

    debug!(context_len = context.len(), "derived 32-byte session key");

    okm
}

// ---------------------------------------------------------------------------
// HMAC-SHA256  (RFC 2104)
// ---------------------------------------------------------------------------

/// Compute `HMAC-SHA256(key, message)`.
fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; 32] {
    const BLOCK_SIZE: usize = 64;

    // If the key is longer than the block size, hash it first.
    let key_block = if key.len() > BLOCK_SIZE {
        let h = sha256(key);
        let mut kb = [0u8; BLOCK_SIZE];
        kb[..32].copy_from_slice(&h);
        kb
    } else {
        let mut kb = [0u8; BLOCK_SIZE];
        kb[..key.len()].copy_from_slice(key);
        kb
    };

    // Inner and outer padded keys.
    let mut i_key_pad = [0x36u8; BLOCK_SIZE];
    let mut o_key_pad = [0x5cu8; BLOCK_SIZE];
    for i in 0..BLOCK_SIZE {
        i_key_pad[i] ^= key_block[i];
        o_key_pad[i] ^= key_block[i];
    }

    // inner = SHA256(i_key_pad || message)
    let mut inner_data = Vec::with_capacity(BLOCK_SIZE + message.len());
    inner_data.extend_from_slice(&i_key_pad);
    inner_data.extend_from_slice(message);
    let inner_hash = sha256(&inner_data);

    // outer = SHA256(o_key_pad || inner)
    let mut outer_data = Vec::with_capacity(BLOCK_SIZE + 32);
    outer_data.extend_from_slice(&o_key_pad);
    outer_data.extend_from_slice(&inner_hash);
    sha256(&outer_data)
}

// ---------------------------------------------------------------------------
// SHA-256  (same implementation as auth.rs, duplicated here to keep modules
// self-contained; a future refactor could extract it into a shared internal
// module).
// ---------------------------------------------------------------------------

const H_INIT: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

fn sha256(data: &[u8]) -> [u8; 32] {
    let mut state = H_INIT;
    let bit_len = (data.len() as u64) * 8;

    // Pad the message.
    let mut padded = data.to_vec();
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0x00);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    // Process each 64-byte block.
    for chunk in padded.chunks_exact(64) {
        let block: [u8; 64] = chunk.try_into().unwrap();
        compress(&mut state, &block);
    }

    let mut out = [0u8; 32];
    for (i, word) in state.iter().enumerate() {
        out[i * 4..(i + 1) * 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

fn compress(state: &mut [u32; 8], block: &[u8; 64]) {
    let mut w = [0u32; 64];
    for i in 0..16 {
        w[i] = u32::from_be_bytes([
            block[i * 4],
            block[i * 4 + 1],
            block[i * 4 + 2],
            block[i * 4 + 3],
        ]);
    }
    for i in 16..64 {
        let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
        let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16]
            .wrapping_add(s0)
            .wrapping_add(w[i - 7])
            .wrapping_add(s1);
    }

    let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = *state;

    for i in 0..64 {
        let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
        let ch = (e & f) ^ ((!e) & g);
        let temp1 = h
            .wrapping_add(s1)
            .wrapping_add(ch)
            .wrapping_add(K[i])
            .wrapping_add(w[i]);
        let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let temp2 = s0.wrapping_add(maj);

        h = g;
        g = f;
        f = e;
        e = d.wrapping_add(temp1);
        d = c;
        c = b;
        b = a;
        a = temp1.wrapping_add(temp2);
    }

    state[0] = state[0].wrapping_add(a);
    state[1] = state[1].wrapping_add(b);
    state[2] = state[2].wrapping_add(c);
    state[3] = state[3].wrapping_add(d);
    state[4] = state[4].wrapping_add(e);
    state[5] = state[5].wrapping_add(f);
    state[6] = state[6].wrapping_add(g);
    state[7] = state[7].wrapping_add(h);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sha256_known_vector() {
        // SHA256("abc") = ba7816bf...
        let hash = sha256(b"abc");
        let hex: String = hash.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(
            hex,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn test_hmac_sha256_known_vector() {
        // RFC 4231 Test Case 2:
        // Key  = "Jefe"
        // Data = "what do ya want for nothing?"
        // HMAC = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
        let mac = hmac_sha256(b"Jefe", b"what do ya want for nothing?");
        let hex: String = mac.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(
            hex,
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
    }

    #[test]
    fn test_derive_session_key_deterministic() {
        let secret = b"shared-secret-material";
        let ctx = b"client-to-server";

        let key1 = derive_session_key(secret, ctx);
        let key2 = derive_session_key(secret, ctx);
        assert_eq!(key1, key2);
    }

    #[test]
    fn test_derive_session_key_different_contexts() {
        let secret = b"shared-secret-material";

        let key_a = derive_session_key(secret, b"context-a");
        let key_b = derive_session_key(secret, b"context-b");
        assert_ne!(key_a, key_b);
    }

    #[test]
    fn test_derive_session_key_different_secrets() {
        let ctx = b"same-context";

        let key_a = derive_session_key(b"secret-1", ctx);
        let key_b = derive_session_key(b"secret-2", ctx);
        assert_ne!(key_a, key_b);
    }
}
