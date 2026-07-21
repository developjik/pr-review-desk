//! OS keychain integration for secret storage.
//!
//! Secrets (GitHub PAT, LLM API key) are stored in the OS keychain
//! (macOS Keychain / Windows Credential Manager / Linux Secret Service).
//! The on-disk config.json holds only boolean flags indicating storage.

use keyring::Entry;

const SERVICE: &str = "com.pr-review.app";
const GITHUB_PAT_ACCOUNT: &str = "github_pat";
const LLM_API_KEY_ACCOUNT: &str = "llm_api_key";

/// Error type for keychain operations.
#[derive(Debug)]
pub enum SecretError {
    Keyring(String),
    NotFound,
}

impl std::fmt::Display for SecretError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SecretError::Keyring(msg) => write!(f, "keychain error: {msg}"),
            SecretError::NotFound => write!(f, "secret not found in keychain"),
        }
    }
}

/// Store a secret in the OS keychain.
pub fn store(account: &str, value: &str) -> Result<(), SecretError> {
    let entry = Entry::new(SERVICE, account).map_err(|e| SecretError::Keyring(e.to_string()))?;
    entry.set_password(value).map_err(|e| SecretError::Keyring(e.to_string()))
}

/// Load a secret from the OS keychain.
pub fn load(account: &str) -> Result<String, SecretError> {
    let entry = Entry::new(SERVICE, account).map_err(|e| SecretError::Keyring(e.to_string()))?;
    entry.get_password().map_err(|e| match e {
        keyring::Error::NoEntry => SecretError::NotFound,
        other => SecretError::Keyring(other.to_string()),
    })
}

/// Store the GitHub PAT.
pub fn store_github_pat(pat: &str) -> Result<(), SecretError> {
    store(GITHUB_PAT_ACCOUNT, pat)
}

/// Load the GitHub PAT.
pub fn load_github_pat() -> Result<String, SecretError> {
    load(GITHUB_PAT_ACCOUNT)
}

/// Store the LLM API key.
pub fn store_llm_api_key(key: &str) -> Result<(), SecretError> {
    store(LLM_API_KEY_ACCOUNT, key)
}

/// Load the LLM API key.
pub fn load_llm_api_key() -> Result<String, SecretError> {
    load(LLM_API_KEY_ACCOUNT)
}
