use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use hkdf::Hkdf;
use sha2::Sha256;
use x25519_dalek::{PublicKey, StaticSecret};

const HKDF_SALT: &[u8] = b"ferlay-e2e";
const HKDF_INFO: &[u8] = b"aes-256-gcm-key";

/// Holds the derived AES-256-GCM cipher for encrypting/decrypting relay payloads.
pub struct CryptoState {
    cipher: Aes256Gcm,
    aes_key: [u8; 32],
}

impl CryptoState {
    pub fn from_shared_secret(shared_secret: &[u8; 32]) -> Self {
        let hkdf = Hkdf::<Sha256>::new(Some(HKDF_SALT), shared_secret);
        let mut aes_key = [0u8; 32];
        hkdf.expand(HKDF_INFO, &mut aes_key)
            .expect("HKDF expand failed");

        let key = Key::<Aes256Gcm>::from_slice(&aes_key);
        let cipher = Aes256Gcm::new(key);

        Self { cipher, aes_key }
    }

    pub fn from_aes_key(aes_key: [u8; 32]) -> Self {
        let key = Key::<Aes256Gcm>::from_slice(&aes_key);
        let cipher = Aes256Gcm::new(key);
        Self { cipher, aes_key }
    }

    /// Encrypts plaintext and returns base64(nonce[12] + ciphertext + auth_tag[16]).
    pub fn encrypt(&self, plaintext: &[u8]) -> Result<String, String> {
        let mut nonce_bytes = [0u8; 12];
        rand::fill(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        let ciphertext = self
            .cipher
            .encrypt(nonce, plaintext)
            .map_err(|e| format!("encryption failed: {e}"))?;

        let mut combined = Vec::with_capacity(12 + ciphertext.len());
        combined.extend_from_slice(&nonce_bytes);
        combined.extend_from_slice(&ciphertext);

        Ok(BASE64.encode(&combined))
    }

    /// Decrypts base64(nonce[12] + ciphertext + auth_tag[16]) and returns plaintext.
    pub fn decrypt(&self, encoded: &str) -> Result<Vec<u8>, String> {
        let combined = BASE64
            .decode(encoded)
            .map_err(|e| format!("base64 decode failed: {e}"))?;

        if combined.len() < 12 + 16 {
            return Err("ciphertext too short".to_string());
        }

        let (nonce_bytes, ciphertext) = combined.split_at(12);
        let nonce = Nonce::from_slice(nonce_bytes);

        self.cipher
            .decrypt(nonce, ciphertext)
            .map_err(|e| format!("decryption failed: {e}"))
    }

    /// Saves the derived AES key to ~/.config/ferlay/keys/aes.key with mode 600.
    pub fn save_key(&self) -> Result<(), String> {
        let dir = dirs::config_dir()
            .ok_or("no config dir")?
            .join("ferlay")
            .join("keys");
        std::fs::create_dir_all(&dir).map_err(|e| format!("mkdir failed: {e}"))?;

        let path = dir.join("aes.key");
        std::fs::write(&path, self.aes_key).map_err(|e| format!("write failed: {e}"))?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))
                .map_err(|e| format!("chmod failed: {e}"))?;
        }

        tracing::info!("Encryption key saved to {}", path.display());
        Ok(())
    }

    /// Loads a previously saved AES key.
    pub fn load_key() -> Option<Self> {
        let path = dirs::config_dir()?.join("ferlay").join("keys").join("aes.key");
        let bytes = std::fs::read(&path).ok()?;
        let aes_key: [u8; 32] = bytes.try_into().ok()?;
        Some(Self::from_aes_key(aes_key))
    }
}

/// Generates an X25519 keypair.
pub fn generate_keypair() -> (StaticSecret, PublicKey) {
    let mut secret_bytes = [0u8; 32];
    rand::fill(&mut secret_bytes);
    let secret = StaticSecret::from(secret_bytes);
    let public = PublicKey::from(&secret);
    (secret, public)
}

/// Encodes a public key as base64 for QR code / message transmission.
pub fn encode_public_key(key: &PublicKey) -> String {
    BASE64.encode(key.as_bytes())
}

/// Decodes a base64-encoded public key.
pub fn decode_public_key(encoded: &str) -> Result<PublicKey, String> {
    let bytes = BASE64
        .decode(encoded)
        .map_err(|e| format!("base64 decode: {e}"))?;
    let arr: [u8; 32] = bytes
        .try_into()
        .map_err(|_| "public key must be 32 bytes".to_string())?;
    Ok(PublicKey::from(arr))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_crypto() -> CryptoState {
        let shared_secret = [42u8; 32];
        CryptoState::from_shared_secret(&shared_secret)
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let crypto = test_crypto();
        let plaintext = b"hello ferlay";
        let encrypted = crypto.encrypt(plaintext).unwrap();
        let decrypted = crypto.decrypt(&encrypted).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn encrypt_produces_different_ciphertext_each_time() {
        let crypto = test_crypto();
        let plaintext = b"same input";
        let a = crypto.encrypt(plaintext).unwrap();
        let b = crypto.encrypt(plaintext).unwrap();
        assert_ne!(a, b, "random nonce should produce different ciphertext");
    }

    #[test]
    fn decrypt_corrupted_ciphertext_fails() {
        let crypto = test_crypto();
        let encrypted = crypto.encrypt(b"secret").unwrap();
        let mut bytes = BASE64.decode(&encrypted).unwrap();
        // Corrupt a byte in the ciphertext (after the 12-byte nonce)
        bytes[15] ^= 0xFF;
        let corrupted = BASE64.encode(&bytes);
        assert!(crypto.decrypt(&corrupted).is_err());
    }

    #[test]
    fn decrypt_too_short_fails() {
        let crypto = test_crypto();
        let short = BASE64.encode(&[0u8; 10]);
        let err = crypto.decrypt(&short).unwrap_err();
        assert!(err.contains("too short"));
    }

    #[test]
    fn decrypt_invalid_base64_fails() {
        let crypto = test_crypto();
        assert!(crypto.decrypt("not-valid-base64!!!").is_err());
    }

    #[test]
    fn from_aes_key_interoperates_with_from_shared_secret() {
        let shared_secret = [99u8; 32];
        let crypto1 = CryptoState::from_shared_secret(&shared_secret);
        let crypto2 = CryptoState::from_aes_key(crypto1.aes_key);

        let encrypted = crypto1.encrypt(b"cross-decrypt test").unwrap();
        let decrypted = crypto2.decrypt(&encrypted).unwrap();
        assert_eq!(decrypted, b"cross-decrypt test");
    }

    #[test]
    fn different_keys_cannot_decrypt() {
        let crypto1 = CryptoState::from_shared_secret(&[1u8; 32]);
        let crypto2 = CryptoState::from_shared_secret(&[2u8; 32]);
        let encrypted = crypto1.encrypt(b"private").unwrap();
        assert!(crypto2.decrypt(&encrypted).is_err());
    }

    #[test]
    fn generate_keypair_produces_distinct_keys() {
        let (_, pk1) = generate_keypair();
        let (_, pk2) = generate_keypair();
        assert_ne!(pk1.as_bytes(), pk2.as_bytes());
    }

    #[test]
    fn public_key_encode_decode_roundtrip() {
        let (_, pk) = generate_keypair();
        let encoded = encode_public_key(&pk);
        let decoded = decode_public_key(&encoded).unwrap();
        assert_eq!(pk.as_bytes(), decoded.as_bytes());
    }

    #[test]
    fn decode_public_key_wrong_length_fails() {
        let short = BASE64.encode(&[0u8; 16]);
        let err = decode_public_key(&short).unwrap_err();
        assert!(err.contains("32 bytes"));
    }

    #[test]
    fn ecdh_shared_secret_matches() {
        let (secret_a, public_a) = generate_keypair();
        let (secret_b, public_b) = generate_keypair();

        let shared_a = secret_a.diffie_hellman(&public_b);
        let shared_b = secret_b.diffie_hellman(&public_a);

        assert_eq!(shared_a.as_bytes(), shared_b.as_bytes());

        // Both sides can encrypt/decrypt
        let crypto_a = CryptoState::from_shared_secret(shared_a.as_bytes());
        let crypto_b = CryptoState::from_shared_secret(shared_b.as_bytes());

        let encrypted = crypto_a.encrypt(b"e2e test").unwrap();
        let decrypted = crypto_b.decrypt(&encrypted).unwrap();
        assert_eq!(decrypted, b"e2e test");
    }

    #[test]
    fn encrypt_empty_plaintext() {
        let crypto = test_crypto();
        let encrypted = crypto.encrypt(b"").unwrap();
        let decrypted = crypto.decrypt(&encrypted).unwrap();
        assert_eq!(decrypted, b"");
    }

    #[test]
    fn encrypt_large_plaintext() {
        let crypto = test_crypto();
        let large = vec![0xAB; 100_000];
        let encrypted = crypto.encrypt(&large).unwrap();
        let decrypted = crypto.decrypt(&encrypted).unwrap();
        assert_eq!(decrypted, large);
    }

    // =========================================================================
    // Cross-platform test vectors (must match Dart tests exactly)
    // =========================================================================

    /// Shared secret: bytes 0x01..0x20 (32 bytes).
    const TEST_VECTOR_SHARED_SECRET: [u8; 32] = [
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
    ];

    /// Expected AES-256 key derived from HKDF-SHA256(salt="ferlay-e2e", info="aes-256-gcm-key").
    const TEST_VECTOR_DERIVED_KEY_HEX: &str =
        "2e90c43fca2aa11bbb14df8f2ab1f04aad5786dde88f5db4478506e2c72052bb";

    /// Known nonce for encryption test vector.
    const TEST_VECTOR_NONCE: [u8; 12] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b];

    /// Plaintext for encryption test vector.
    const TEST_VECTOR_PLAINTEXT: &[u8] = b"hello ferlay e2e";

    /// Expected base64 ciphertext (nonce + ciphertext + tag) from Rust.
    const TEST_VECTOR_ENCRYPTED_B64: &str =
        "AAECAwQFBgcICQoLgK9jfCrkWqdHI0p3R6fcKthFmtSawxJI5XvOqQmMfsI=";

    #[test]
    fn cross_platform_hkdf_key_derivation() {
        let crypto = CryptoState::from_shared_secret(&TEST_VECTOR_SHARED_SECRET);
        let key_hex: String = crypto.aes_key.iter().map(|b| format!("{:02x}", b)).collect();
        assert_eq!(
            key_hex, TEST_VECTOR_DERIVED_KEY_HEX,
            "HKDF-derived AES key must match cross-platform test vector"
        );
    }

    #[test]
    fn cross_platform_encryption() {
        let crypto = CryptoState::from_shared_secret(&TEST_VECTOR_SHARED_SECRET);
        let nonce = Nonce::from_slice(&TEST_VECTOR_NONCE);
        let ciphertext = crypto.cipher.encrypt(nonce, TEST_VECTOR_PLAINTEXT).unwrap();

        let mut combined = Vec::with_capacity(12 + ciphertext.len());
        combined.extend_from_slice(&TEST_VECTOR_NONCE);
        combined.extend_from_slice(&ciphertext);
        let encrypted_b64 = BASE64.encode(&combined);

        assert_eq!(
            encrypted_b64, TEST_VECTOR_ENCRYPTED_B64,
            "Encrypted ciphertext must match cross-platform test vector"
        );
    }

    #[test]
    fn cross_platform_decryption() {
        let crypto = CryptoState::from_shared_secret(&TEST_VECTOR_SHARED_SECRET);
        let decrypted = crypto.decrypt(TEST_VECTOR_ENCRYPTED_B64).unwrap();
        assert_eq!(
            decrypted, TEST_VECTOR_PLAINTEXT,
            "Decrypted plaintext must match cross-platform test vector"
        );
    }
}
