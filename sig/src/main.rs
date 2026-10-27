//! INTERIM host implementation (Rust). synapse-claims-sig: Ed25519 keygen / sign / verify for the
//! synapse-claims ledger. Exists only because seeded Omega at the pinned omega-mv has no Ed25519
//! unit; see ../../docs/EXTENSION-PROPOSALS.md. did:key encoding reuses synapse-core.
//!
//! Signing follows synapse-auth's domain-tag pattern: the signed message is
//! `AIEN_CLAIMS_EVENT_V1\0 ++ raw32(event hash)`; verification uses `verify_strict`.
//!
//! keygen DIR      create DIR/ledger.key (hex seed, 0600, never overwritten) and DIR/ledger.pub
//!                 (`did:key:z...`); print the did:key. The seed is never printed.
//! sign KEYFILE    stdin: one 64-hex hash per line; stdout: one 128-hex signature per line.
//! verify PUBFILE  stdin: `<64 hex hash> <128 hex sig>` per line; stdout `ok N` (exit 0) or
//!                 `bad <line>` (1-based, exit 3) at the first failing line.
//! Exit codes: 0 ok, 3 bad signature, 64 usage, 65 malformed input, 70 internal/io error.

use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::process::exit;
use synapse_core::{decode_did_key_ed25519, encode_did_key_ed25519};

/// Domain tag for signing a claims ledger event hash.
const DOMAIN_CLAIMS_EVENT_V1: &[u8] = b"AIEN_CLAIMS_EVENT_V1\0";

fn die(code: i32, msg: &str) -> ! {
    eprintln!("synapse-claims-sig: {msg}");
    exit(code)
}

fn message(hash: &[u8; 32]) -> [u8; 53] {
    let mut m = [0u8; 53];
    m[..21].copy_from_slice(DOMAIN_CLAIMS_EVENT_V1);
    m[21..].copy_from_slice(hash);
    m
}

fn hex32(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 || s.bytes().any(|b| b.is_ascii_uppercase()) {
        return None;
    }
    let mut out = [0u8; 32];
    hex::decode_to_slice(s, &mut out).ok()?;
    Some(out)
}

fn keygen(dir: &Path) {
    let key_path = dir.join("ledger.key");
    let pub_path = dir.join("ledger.pub");
    if key_path.exists() || pub_path.exists() {
        die(70, "keygen: key already exists; refusing to overwrite");
    }
    fs::create_dir_all(dir).unwrap_or_else(|e| die(70, &format!("keygen: create dir: {e}")));
    let mut seed = [0u8; 32];
    fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut seed))
        .unwrap_or_else(|e| die(70, &format!("keygen: urandom: {e}")));
    let sk = SigningKey::from_bytes(&seed);
    let did = encode_did_key_ed25519(&sk.verifying_key().to_bytes());
    let mut kf = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&key_path)
        .unwrap_or_else(|e| die(70, &format!("keygen: create key: {e}")));
    let mut line = hex::encode(seed);
    line.push('\n');
    kf.write_all(line.as_bytes())
        .and_then(|_| kf.sync_all())
        .unwrap_or_else(|e| die(70, &format!("keygen: write key: {e}")));
    seed.fill(0);
    let mut pf = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o644)
        .open(&pub_path)
        .unwrap_or_else(|e| die(70, &format!("keygen: create pub: {e}")));
    pf.write_all(format!("{did}\n").as_bytes())
        .and_then(|_| pf.sync_all())
        .unwrap_or_else(|e| die(70, &format!("keygen: write pub: {e}")));
    println!("{did}");
}

fn load_seed(path: &Path) -> SigningKey {
    let text = fs::read_to_string(path).unwrap_or_else(|e| die(70, &format!("sign: read key: {e}")));
    let seed = hex32(text.trim_end()).unwrap_or_else(|| die(65, "sign: key file is not 64 lowercase hex"));
    SigningKey::from_bytes(&seed)
}

fn sign(keyfile: &Path) {
    let sk = load_seed(keyfile);
    let stdin = io::stdin();
    let mut out = io::BufWriter::new(io::stdout().lock());
    for (n, line) in stdin.lock().lines().enumerate() {
        let line = line.unwrap_or_else(|e| die(70, &format!("sign: stdin: {e}")));
        let hash = hex32(&line).unwrap_or_else(|| die(65, &format!("sign: line {}: not a 64-hex hash", n + 1)));
        let sig = sk.sign(&message(&hash));
        writeln!(out, "{}", hex::encode(sig.to_bytes())).unwrap_or_else(|e| die(70, &format!("sign: stdout: {e}")));
    }
    out.flush().unwrap_or_else(|e| die(70, &format!("sign: stdout: {e}")));
}

fn verify(pubfile: &Path) {
    let text = fs::read_to_string(pubfile).unwrap_or_else(|e| die(70, &format!("verify: read pub: {e}")));
    let raw = decode_did_key_ed25519(text.trim_end()).unwrap_or_else(|_| die(65, "verify: pub file is not an Ed25519 did:key"));
    let vk = VerifyingKey::from_bytes(&raw).unwrap_or_else(|_| die(65, "verify: pub key is not a valid point"));
    let stdin = io::stdin();
    let mut n = 0u64;
    for line in stdin.lock().lines() {
        let line = line.unwrap_or_else(|e| die(70, &format!("verify: stdin: {e}")));
        n += 1;
        let ok = line.split_once(' ').and_then(|(h, s)| {
            let hash = hex32(h)?;
            if s.len() != 128 || s.bytes().any(|b| b.is_ascii_uppercase()) {
                return None;
            }
            let mut sb = [0u8; 64];
            hex::decode_to_slice(s, &mut sb).ok()?;
            vk.verify_strict(&message(&hash), &Signature::from_bytes(&sb)).ok()
        });
        if ok.is_none() {
            println!("bad {n}");
            exit(3);
        }
    }
    println!("ok {n}");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match (args.get(1).map(String::as_str), args.get(2), args.len()) {
        (Some("keygen"), Some(d), 3) => keygen(Path::new(d)),
        (Some("sign"), Some(k), 3) => sign(Path::new(k)),
        (Some("verify"), Some(p), 3) => verify(Path::new(p)),
        _ => die(64, "usage: synapse-claims-sig keygen DIR | sign KEYFILE | verify PUBFILE"),
    }
}
