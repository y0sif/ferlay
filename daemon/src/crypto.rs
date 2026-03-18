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
