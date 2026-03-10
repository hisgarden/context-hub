---
name: webauthn
description: "WebAuthn Level 3 and Passkeys - Web Authentication API for phishing-resistant passwordless authentication"
metadata:
  languages: "javascript"
  versions: "3.0.0"
  revision: 2
  updated-on: "2026-03-09"
  source: community
  tags: "webauthn,passkeys,fido2,authentication,passwordless,mfa,biometric"
---

# WebAuthn & Passkeys - JavaScript Implementation Guide

## Golden Rule

**ALWAYS use the Web Authentication API (`navigator.credentials.create` / `navigator.credentials.get`) for passkey registration and authentication.**

**DO NOT:**
- Implement custom public key cryptography for WebAuthn flows
- Store private keys on the server (only store public keys and credential IDs)
- Skip server-side validation of challenges, origins, and signatures
- Use `attestation: "direct"` unless you have a specific enterprise need (prefer `"none"`)
- Hardcode challenges or reuse them across ceremonies

**Specification references:**
- W3C WebAuthn Level 3: https://w3c.github.io/webauthn/
- Passkeys developer guide: https://passkeys.dev/
- WebAuthn guide: https://webauthn.guide/

---

## Overview

Web Authentication (WebAuthn) is a W3C specification that enables web applications to use public key cryptography for user authentication. Passkeys are the user-facing term for WebAuthn discoverable credentials that replace passwords with biometric-backed, phishing-resistant authentication.

**Key security properties:**
- **Phishing-resistant**: Credentials are scoped to the relying party's origin. A credential registered at `example.com` cannot be used at `evil-example.com`.
- **Breach-resistant**: Servers store only public keys. Private keys never leave the user's device or authenticator.
- **No shared secrets**: Unlike passwords, there is no secret that both client and server know.
- **Replay-resistant**: Every ceremony uses a unique server-generated challenge.

---

## Key Concepts

### Relying Party (RP)

The web application requesting credential creation or authentication. The RP is identified by its domain (`rp.id`), which must be a registrable domain suffix of the current origin.

### Authenticator

A cryptographic entity (hardware or software) that generates key pairs, stores credentials, and produces assertions. Types:

- **Platform Authenticator**: Built into the user's device (Touch ID, Face ID, Windows Hello, Android biometrics). Low friction but device-bound unless synced.
- **Cross-Platform / Roaming Authenticator**: External devices (USB security keys, NFC keys, phones via Bluetooth). Portable across devices.

### Credential

A public key credential (asymmetric key pair) bound to a specific RP. The authenticator holds the private key; the RP stores the public key and credential ID.

### Attestation

Evidence provided during registration about the authenticator's origin and capabilities. Includes attestation statements and certificates verifying the authenticator's manufacture. Most implementations should use `attestation: "none"` for privacy.

### Assertion

The cryptographically signed response from an authenticator during authentication, proving the user controls the credential's private key.

### Discoverable Credential (Resident Key)

A credential stored on the authenticator itself, enabling authentication without the server providing a list of credential IDs. This is what makes "passkeys" possible - users can authenticate by selecting a credential from the authenticator's UI.

---

## Passkey Types

### Synced Passkeys

Discoverable credentials synchronized across a user's devices through a platform credential manager (iCloud Keychain, Google Password Manager, etc.). The sync servers never have access to the private keys.

- Available on: iOS 16+, Android 9+, macOS 13+, Windows
- Backed up and recoverable if a device is lost
- Flagged via Backup Eligibility (BE) and Backup State (BS) bits in authenticator data

### Device-Bound Passkeys

Discoverable credentials restricted to a single authenticator. Cannot be synced or backed up. Examples include FIDO2 hardware security keys (YubiKey, etc.).

- Higher security assurance (no cloud sync)
- Risk of lockout if device is lost
- Common in enterprise/high-security scenarios

---

## Platform & Browser Support

Source: https://passkeys.dev/device-support/ (last updated February 2, 2026)

### Synced Passkeys by Platform

| Platform | Synced Passkeys | Third-Party Providers |
|----------|----------------|-----------------------|
| Android | 9+ | 14+ |
| iOS/iPadOS | 16+ | 17+ |
| macOS | 13+ | 14+ |
| Windows | Planned | Browser Extensions |
| Chrome OS | 129+ | Browser Extensions |
| Ubuntu | Browser Extensions | Browser Extensions |

### Browser Autofill UI (Conditional Get)

| Platform | Chrome | Safari | Firefox | Edge |
|----------|--------|--------|---------|------|
| Android | 108+ | — | Supported | 122+ |
| iOS/iPadOS | 16.1+ | 16.1+ | 16.1+ | 16.1+ |
| macOS | 108+ | 16.1+ | 122+ | 122+ |
| Ubuntu | 108+ | — | 122+ | 122+ |

### Passkey Upgrades (Conditional Create)

| Platform | Chrome | Safari | Firefox | Edge |
|----------|--------|--------|---------|------|
| Android | 142+ | — | — | — |
| iOS/iPadOS | 18+ | 18+ | 18+ | 18+ |
| macOS | 136+ | 18+ | — | — |
| Ubuntu | 136+ | — | — | — |
| Windows | 136+ | — | — | — |

### Cross-Device Authentication

| Platform | As Authenticator | As Client |
|----------|-----------------|-----------|
| Android | 9+ | 9+ |
| iOS/iPadOS | 16+ | 16+ |
| macOS | — | 13+ |
| Chrome OS | — | 108+ |
| Ubuntu | — | Chrome, Edge |
| Windows | — | 23H2+ |

### Client Hints & Related Origin Requests

| Platform | Chrome | Firefox | Edge |
|----------|--------|---------|------|
| Android | 128+ | 128+ | — |
| Chrome OS | 128+ | 128+ | — |
| macOS | 128+ | — | 128+ |
| Ubuntu | 128+ | — | 128+ |
| Windows | 128+ | — | 128+ |

---

## Feature Detection

```javascript
// Check if WebAuthn is supported
if (window.PublicKeyCredential) {
  console.log("WebAuthn is supported");
}

// Check if platform authenticator with user verification is available
const uvpaAvailable =
  await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();

// Check if conditional mediation (autofill UI) is available
const cmAvailable =
  await PublicKeyCredential.isConditionalMediationAvailable();
```

---

## Registration Ceremony (Creating a Passkey)

### Server: Generate Registration Options

The server must generate a cryptographically random challenge and provide relying party and user information.

**Server-side requirements:**
- Generate a minimum 16-byte cryptographically random challenge
- Challenges MUST be single-use and time-limited
- Store the challenge in the user's session for later verification
- The `user.id` should be an opaque identifier (not email or username) - max 64 bytes

### PublicKeyCredentialCreationOptions

```javascript
const publicKeyCredentialCreationOptions = {
  // Cryptographically random bytes from the server (required)
  challenge: new Uint8Array([/* server-generated random bytes */]),

  // Relying Party information (required)
  rp: {
    id: "example.com",       // Domain - must be registrable domain suffix of origin
    name: "Example Corp"     // Human-readable display name
  },

  // User account information (required)
  user: {
    id: new Uint8Array([/* opaque user identifier, max 64 bytes */]),
    name: "user@example.com",    // Username, email, or phone number
    displayName: "Jane Doe"      // Human-friendly display name
  },

  // Acceptable public key algorithms in preference order (required)
  pubKeyCredParams: [
    { alg: -8,   type: "public-key" },  // EdDSA
    { alg: -7,   type: "public-key" },  // ES256 (ECDSA w/ SHA-256) - widely supported
    { alg: -257, type: "public-key" }   // RS256 (RSASSA-PKCS1-v1_5 w/ SHA-256)
  ],

  // Authenticator selection criteria (optional but recommended)
  authenticatorSelection: {
    // "platform" = built-in, "cross-platform" = external device
    // Omit to allow both
    authenticatorAttachment: "platform",

    // Discoverable credential (passkey) requirement
    // "required" = must be discoverable (recommended for passkeys)
    // "preferred" = discoverable if possible
    // "discouraged" = non-discoverable
    residentKey: "required",

    // Whether to require user verification (biometric/PIN)
    // "required" = must verify identity
    // "preferred" = verify if available (recommended)
    // "discouraged" = skip verification
    userVerification: "preferred"
  },

  // Attestation conveyance preference (optional)
  // "none" = no attestation (recommended for most use cases)
  // "indirect" = anonymized attestation
  // "direct" = raw attestation from authenticator
  // "enterprise" = enterprise attestation
  attestation: "none",

  // Credentials to exclude (prevent re-registration)
  excludeCredentials: [
    {
      id: new Uint8Array([/* existing credential ID */]),
      type: "public-key",
      transports: ["internal", "hybrid"]  // Hint for transport
    }
  ],

  // Extensions (optional)
  extensions: {
    credProps: true  // Request credential properties (e.g., is it discoverable?)
  },

  // Timeout in milliseconds (optional)
  timeout: 300000
};
```

### Client: Create Credential

```javascript
try {
  const credential = await navigator.credentials.create({
    publicKey: publicKeyCredentialCreationOptions
  });

  // credential is a PublicKeyCredential object
  const {
    id,         // Base64url-encoded credential ID
    rawId,      // ArrayBuffer credential ID
    response,   // AuthenticatorAttestationResponse
    type,       // Always "public-key"
    authenticatorAttachment  // "platform" or "cross-platform"
  } = credential;

  // Extract response data
  const attestationResponse = {
    id: credential.id,
    rawId: bufferToBase64url(credential.rawId),
    type: credential.type,
    response: {
      clientDataJSON: bufferToBase64url(credential.response.clientDataJSON),
      attestationObject: bufferToBase64url(credential.response.attestationObject),
      // Available transports for future authentication hints
      transports: credential.response.getTransports()
    },
    // Extension results
    clientExtensionResults: credential.getClientExtensionResults()
  };

  // Send to server for validation and storage
  await fetch("/api/register/verify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(attestationResponse)
  });

} catch (error) {
  if (error.name === "InvalidStateError") {
    // Credential already exists for this user on this authenticator
    console.error("Credential already registered");
  } else if (error.name === "NotAllowedError") {
    // User cancelled or timed out
    console.error("User cancelled registration");
  } else if (error.name === "NotSupportedError") {
    // No suitable authenticator available
    console.error("No supported authenticator found");
  }
}
```

### Registration Response Structure

```javascript
// The credential object returned from navigator.credentials.create()
PublicKeyCredential {
  id: "ADSUllKQmbqdGtpu4sjseh4cg2TxSvrbcHDTBsv4NSSX9...",
  rawId: ArrayBuffer(59),
  response: AuthenticatorAttestationResponse {
    clientDataJSON: ArrayBuffer(121),
    attestationObject: ArrayBuffer(306)
  },
  type: "public-key"
}
```

### Parsing clientDataJSON

```javascript
const utf8Decoder = new TextDecoder("utf-8");
const decodedClientData = utf8Decoder.decode(
  credential.response.clientDataJSON
);
const clientDataObj = JSON.parse(decodedClientData);

// Result:
// {
//   challenge: "p5aV2uHXr0AOqUk7HQitvi-Ny1....",
//   origin: "https://example.com",
//   type: "webauthn.create"
// }
```

### Parsing attestationObject (CBOR-encoded)

```javascript
// Requires a CBOR library (e.g., cbor-x, @levischuck/tiny-cbor)
const decodedAttestationObject = CBOR.decode(
  credential.response.attestationObject
);

// Result:
// {
//   authData: Uint8Array(196),      // Authenticator data
//   fmt: "packed",                   // Attestation format
//   attStmt: {                       // Attestation statement
//     sig: Uint8Array(70),
//     x5c: Array(1)                  // Certificate chain (if direct attestation)
//   }
// }
```

### Server: Validate Registration

The server MUST perform these validation steps:

1. Verify `clientDataJSON.type` is `"webauthn.create"`
2. Verify `clientDataJSON.origin` matches the expected origin
3. Verify `clientDataJSON.challenge` matches the stored challenge
4. Verify `rpIdHash` in authenticator data matches SHA-256 of expected RP ID
5. Verify User Present (UP) flag is set in authenticator data
6. Verify User Verified (UV) flag if `userVerification` was `"required"`
7. Verify attestation statement (if attestation is not `"none"`)
8. Store credential ID, public key, sign counter, and transports in database

---

## Authentication Ceremony (Using a Passkey)

### Server: Generate Authentication Options

```javascript
// Server generates options
const publicKeyCredentialRequestOptions = {
  // Cryptographically random bytes from the server (required)
  challenge: new Uint8Array([/* server-generated random bytes */]),

  // RP domain - must match what was used during registration
  rpId: "example.com",

  // Timeout in milliseconds (optional)
  timeout: 300000,

  // User verification requirement
  // "preferred" is recommended for most use cases
  userVerification: "preferred",

  // Allowed credentials (optional)
  // Empty array or omit for discoverable credential (passkey) flow
  // Populate for non-discoverable credential flow
  allowCredentials: [
    // For non-discoverable flow, list user's registered credentials:
    // {
    //   id: new Uint8Array([/* credential ID */]),
    //   type: "public-key",
    //   transports: ["internal", "hybrid"]  // From registration response
    // }
  ],

  // Hints for the browser UI about which authenticator to suggest
  hints: ["client-device"],  // "security-key", "client-device", "hybrid"

  // Extensions (optional)
  extensions: {}
};
```

### Client: Get Assertion

```javascript
try {
  const assertion = await navigator.credentials.get({
    publicKey: publicKeyCredentialRequestOptions
  });

  const assertionResponse = {
    id: assertion.id,
    rawId: bufferToBase64url(assertion.rawId),
    type: assertion.type,
    response: {
      authenticatorData: bufferToBase64url(assertion.response.authenticatorData),
      clientDataJSON: bufferToBase64url(assertion.response.clientDataJSON),
      signature: bufferToBase64url(assertion.response.signature),
      userHandle: assertion.response.userHandle
        ? bufferToBase64url(assertion.response.userHandle)
        : null
    },
    authenticatorAttachment: assertion.authenticatorAttachment
  };

  // Send to server for validation
  const result = await fetch("/api/authenticate/verify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(assertionResponse)
  });

} catch (error) {
  if (error.name === "NotAllowedError") {
    console.error("User cancelled or no matching credential found");
  } else if (error.name === "AbortError") {
    console.error("Authentication was aborted");
  }
}
```

### Authentication Response Structure

```javascript
PublicKeyCredential {
  id: "ADSUllKQmbqdGtpu4sjseh4cg2TxSvrbcHDTBsv4NSSX9...",
  rawId: ArrayBuffer(59),
  response: AuthenticatorAssertionResponse {
    authenticatorData: ArrayBuffer(191),  // RP ID hash + flags + counter
    clientDataJSON: ArrayBuffer(118),     // Challenge, origin, type
    signature: ArrayBuffer(70),           // Signed by credential private key
    userHandle: ArrayBuffer(10)           // user.id from registration
  },
  type: "public-key"
}
```

### Server: Validate Authentication

The server MUST perform these validation steps:

1. Look up the credential by credential ID in the database
2. Verify `clientDataJSON.type` is `"webauthn.get"`
3. Verify `clientDataJSON.origin` matches expected origin
4. Verify `clientDataJSON.challenge` matches stored challenge
5. Verify `rpIdHash` in authenticator data matches SHA-256 of expected RP ID
6. Verify User Present (UP) flag is set
7. Verify User Verified (UV) flag if required
8. Verify signature over `authenticatorData + SHA-256(clientDataJSON)` using stored public key
9. Verify and update sign counter (detect cloned authenticators)
10. Authenticate the user identified by `userHandle`

### Server: Signature Verification (Pseudo-code)

```javascript
const storedCredential = await getCredentialFromDatabase(credentialId);

const signedData = Buffer.concat([
  authenticatorDataBytes,
  crypto.createHash("sha256").update(clientDataJSON).digest()
]);

const isValid = crypto.verify(
  "sha256",
  signedData,
  storedCredential.publicKey,  // PEM or JWK format
  signature
);

if (isValid) {
  // Update sign counter
  if (authData.signCount > storedCredential.signCount) {
    await updateSignCount(credentialId, authData.signCount);
  } else if (authData.signCount > 0 || storedCredential.signCount > 0) {
    // Possible cloned authenticator - handle according to policy
    console.warn("Sign counter did not increment - possible clone");
  }
  // Authenticate user
} else {
  throw new Error("Signature verification failed");
}
```

---

## Conditional UI (Autofill Integration)

Conditional UI allows passkeys to appear in the browser's autofill dropdown alongside saved passwords. This provides a non-intrusive passkey experience.

### HTML Setup

```html
<!-- The autocomplete attribute MUST include "webauthn" -->
<input
  type="text"
  id="username"
  name="username"
  autocomplete="username webauthn"
  placeholder="Enter your username"
/>
```

### JavaScript: Conditional Mediation

```javascript
// Start conditional UI on page load
async function initConditionalUI() {
  // Feature detection
  if (!window.PublicKeyCredential ||
      !PublicKeyCredential.isConditionalMediationAvailable) {
    return;
  }

  const cmAvailable =
    await PublicKeyCredential.isConditionalMediationAvailable();
  if (!cmAvailable) {
    return;
  }

  // Fetch authentication options from server
  const authOptions = await fetch("/api/authenticate/options").then(r => r.json());

  try {
    // This call will NOT show a modal immediately.
    // Instead, it waits for the user to interact with an autofill-enabled input.
    const assertion = await navigator.credentials.get({
      mediation: "conditional",  // Key: enables autofill UI
      publicKey: {
        challenge: base64urlToBuffer(authOptions.challenge),
        rpId: authOptions.rpId,
        allowCredentials: [],   // Empty for discoverable credentials
        userVerification: "preferred",
        timeout: 300000
      }
    });

    // User selected a passkey from autofill - verify on server
    await verifyAssertion(assertion);

  } catch (error) {
    // User may have selected a password instead, or cancelled
    console.log("Conditional UI flow ended:", error.message);
  }
}

// Call on page load
document.addEventListener("DOMContentLoaded", initConditionalUI);
```

---

## Cross-Device Authentication (Hybrid Transport)

Cross-device authentication (CDA) allows a passkey stored on one device (e.g., phone) to authenticate on another device (e.g., laptop). This is powered by the FIDO CTAP hybrid transport protocol.

### How It Works

1. The client device (laptop) displays a QR code
2. The user scans the QR code with their authenticator device (phone)
3. A Bluetooth Low Energy (BLE) proximity check confirms both devices are nearby
4. The authenticator device performs user verification and signs the challenge
5. The assertion is transmitted back to the client device

### Triggering Cross-Device Flow

```javascript
// Cross-device authentication is triggered automatically by the platform
// when the user selects "Use a phone or tablet" or similar option.
// You can hint at this with the hints parameter:
const options = {
  publicKey: {
    challenge: serverChallenge,
    rpId: "example.com",
    allowCredentials: [],
    userVerification: "preferred",
    // Suggest hybrid (cross-device) as an option
    hints: ["hybrid"]
  }
};

const assertion = await navigator.credentials.get(options);
```

### Persistent Linking

After a successful cross-device authentication, some platforms offer to create a persistent link between the authenticator and client, eliminating the need for QR scanning on subsequent authentications.

- Android to Windows 11 23H2+: Supported
- Other combinations: Typically require QR scanning each time

---

## Authenticator Data Structure

The authenticator data is a byte array returned in both registration and authentication responses:

```
Byte offset | Length  | Field
------------|---------|------------------------------------------
0           | 32      | rpIdHash (SHA-256 of RP ID)
32          | 1       | flags
33          | 4       | signCount (big-endian uint32)
37          | var     | attestedCredentialData (registration only)
var         | var     | extensions (CBOR-encoded, if present)
```

### Flags Byte

```
Bit 0 (0x01): User Present (UP)
Bit 2 (0x04): User Verified (UV)
Bit 3 (0x08): Backup Eligibility (BE) - credential CAN be backed up
Bit 4 (0x10): Backup State (BS) - credential IS currently backed up
Bit 6 (0x40): Attested Credential Data included (AT)
Bit 7 (0x80): Extension Data included (ED)
```

**Backup Eligibility (BE) and Backup State (BS)** are critical for passkey detection:
- `BE=1, BS=1`: Synced passkey (backed up and available across devices)
- `BE=1, BS=0`: Eligible for sync but not yet synced
- `BE=0, BS=0`: Device-bound passkey (hardware security key)

---

## COSE Algorithm Identifiers

| Algorithm | COSE ID | Description |
|-----------|---------|-------------|
| ES256 | -7 | ECDSA with P-256 and SHA-256 (most widely supported) |
| EdDSA | -8 | Edwards-curve Digital Signature Algorithm |
| ES384 | -35 | ECDSA with P-384 and SHA-384 |
| ES512 | -36 | ECDSA with P-521 and SHA-512 |
| RS256 | -257 | RSASSA-PKCS1-v1_5 with SHA-256 |

**Recommendation:** Always include at least ES256 (`-7`) as it has the broadest authenticator support. List algorithms in preference order with the most preferred first.

### Public Key in COSE Format (ES256 Example)

```javascript
// COSE key map for ES256
{
  1: 2,              // kty: EC2 (Elliptic Curve)
  3: -7,             // alg: ES256
  -1: 1,             // crv: P-256
  -2: Uint8Array(32), // x-coordinate
  -3: Uint8Array(32)  // y-coordinate
}
```

---

## Attestation Formats

| Format | Description |
|--------|-------------|
| `packed` | Self-contained attestation, most common format |
| `tpm` | Trusted Platform Module attestation with certificate chain |
| `android-key` | Android hardware keystore attestation |
| `android-safetynet` | Android device integrity attestation (deprecated) |
| `fido-u2f` | Legacy FIDO U2F backward-compatible format |
| `apple` | Apple Anonymous attestation (no device identification) |
| `none` | No attestation statement provided |

### Attestation Conveyance Preferences

```javascript
// In PublicKeyCredentialCreationOptions:
attestation: "none"       // Recommended: no attestation (best privacy)
attestation: "indirect"   // Anonymized/filtered attestation
attestation: "direct"     // Raw authenticator attestation
attestation: "enterprise" // Enterprise-specific attestation
```

**Best practice:** Use `"none"` unless you have a specific requirement to validate authenticator provenance. Direct attestation reduces user privacy and most relying parties do not need it.

---

## Extensions

### credProps (Credential Properties)

Returns information about the created credential.

```javascript
// Registration
const options = {
  publicKey: {
    // ... other options
    extensions: {
      credProps: true
    }
  }
};

const credential = await navigator.credentials.create(options);
const extensionResults = credential.getClientExtensionResults();
// extensionResults.credProps.rk === true means discoverable credential
```

### PRF (Pseudo-Random Function)

Derives symmetric keys from the credential for encryption use cases.

```javascript
// Authentication with PRF
const options = {
  publicKey: {
    // ... other options
    extensions: {
      prf: {
        eval: {
          first: new Uint8Array([/* salt */]),
          second: new Uint8Array([/* optional second salt */])
        }
      }
    }
  }
};

const assertion = await navigator.credentials.get(options);
const prfResults = assertion.getClientExtensionResults().prf;
// prfResults.results.first = derived key bytes
```

### largeBlob (Large Blob Storage)

Store and retrieve data (up to ~64KB) on the authenticator.

```javascript
// Write during authentication
extensions: {
  largeBlob: {
    write: new Uint8Array([/* data to store */])
  }
}

// Read during authentication
extensions: {
  largeBlob: {
    read: true
  }
}
```

### appid (FIDO U2F Backward Compatibility)

Allows authentication with credentials registered via the legacy FIDO U2F API.

```javascript
extensions: {
  appid: "https://example.com"  // Original U2F appId
}
```

---

## User Verification vs User Presence

### User Presence (UP)

A simple test that a human is physically interacting with the authenticator - typically a button press, tap, or touch. Does NOT verify the user's identity.

### User Verification (UV)

Cryptographic proof of the user's identity through biometric (fingerprint, face scan), PIN, or device password on the authenticator itself.

### UserVerificationRequirement Values

| Value | Behavior |
|-------|----------|
| `"required"` | Ceremony fails if UV is not available |
| `"preferred"` | Use UV if available, proceed without if not (recommended) |
| `"discouraged"` | Skip UV even if the authenticator supports it |

**Recommendation:** Use `"preferred"` for most use cases. It provides the best balance: devices with biometrics will use them, while devices without biometrics will not block the flow. Always verify the UV flag server-side and enforce it according to your security policy.

---

## Credential Storage (Server-Side)

For each registered credential, store the following in your database:

```
credential_id      BYTEA        -- The credential ID (from response.id/rawId)
public_key         BYTEA        -- The public key in COSE or PEM format
sign_count         BIGINT       -- The signature counter
user_id            BYTEA        -- Your internal user identifier
transports         TEXT[]       -- Transport hints (from getTransports())
backup_eligible    BOOLEAN      -- BE flag from authenticator data
backup_state       BOOLEAN      -- BS flag from authenticator data
authenticator_attachment TEXT   -- "platform" or "cross-platform"
created_at         TIMESTAMP    -- When the credential was registered
last_used_at       TIMESTAMP    -- When the credential was last used
```

**Important:** A user can have multiple credentials. Always support multiple passkeys per account (different devices, backup keys, etc.).

---

## Complete Registration Flow Example

```javascript
// === CLIENT SIDE ===

async function registerPasskey() {
  // 1. Get options from server
  const optionsResponse = await fetch("/api/register/options", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username: "user@example.com" })
  });
  const options = await optionsResponse.json();

  // 2. Decode server options (base64url -> ArrayBuffer)
  const publicKeyOptions = {
    challenge: base64urlToBuffer(options.challenge),
    rp: options.rp,
    user: {
      ...options.user,
      id: base64urlToBuffer(options.user.id)
    },
    pubKeyCredParams: options.pubKeyCredParams,
    authenticatorSelection: options.authenticatorSelection,
    attestation: options.attestation,
    excludeCredentials: (options.excludeCredentials || []).map(cred => ({
      ...cred,
      id: base64urlToBuffer(cred.id)
    })),
    extensions: options.extensions,
    timeout: options.timeout
  };

  // 3. Create credential
  const credential = await navigator.credentials.create({
    publicKey: publicKeyOptions
  });

  // 4. Encode response for transport (ArrayBuffer -> base64url)
  const registrationResponse = {
    id: credential.id,
    rawId: bufferToBase64url(credential.rawId),
    type: credential.type,
    response: {
      clientDataJSON: bufferToBase64url(credential.response.clientDataJSON),
      attestationObject: bufferToBase64url(credential.response.attestationObject),
      transports: credential.response.getTransports?.() || []
    },
    clientExtensionResults: credential.getClientExtensionResults(),
    authenticatorAttachment: credential.authenticatorAttachment
  };

  // 5. Send to server for verification
  const verifyResponse = await fetch("/api/register/verify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(registrationResponse)
  });

  return verifyResponse.json();
}

// === UTILITY FUNCTIONS ===

function bufferToBase64url(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlToBuffer(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}
```

---

## Complete Authentication Flow Example

```javascript
// === CLIENT SIDE ===

async function authenticateWithPasskey() {
  // 1. Get options from server
  const optionsResponse = await fetch("/api/authenticate/options", {
    method: "POST",
    headers: { "Content-Type": "application/json" }
  });
  const options = await optionsResponse.json();

  // 2. Decode server options
  const publicKeyOptions = {
    challenge: base64urlToBuffer(options.challenge),
    rpId: options.rpId,
    allowCredentials: (options.allowCredentials || []).map(cred => ({
      ...cred,
      id: base64urlToBuffer(cred.id)
    })),
    userVerification: options.userVerification,
    timeout: options.timeout
  };

  // 3. Get assertion
  const assertion = await navigator.credentials.get({
    publicKey: publicKeyOptions
  });

  // 4. Encode response for transport
  const authenticationResponse = {
    id: assertion.id,
    rawId: bufferToBase64url(assertion.rawId),
    type: assertion.type,
    response: {
      authenticatorData: bufferToBase64url(assertion.response.authenticatorData),
      clientDataJSON: bufferToBase64url(assertion.response.clientDataJSON),
      signature: bufferToBase64url(assertion.response.signature),
      userHandle: assertion.response.userHandle
        ? bufferToBase64url(assertion.response.userHandle)
        : null
    },
    authenticatorAttachment: assertion.authenticatorAttachment
  };

  // 5. Verify on server
  const verifyResponse = await fetch("/api/authenticate/verify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(authenticationResponse)
  });

  return verifyResponse.json();
}
```

---

## Aborting a Ceremony

```javascript
const abortController = new AbortController();

// Start authentication with abort signal
const assertionPromise = navigator.credentials.get({
  publicKey: options,
  signal: abortController.signal
});

// Cancel after 30 seconds or on user action
setTimeout(() => abortController.abort(), 30000);
cancelButton.addEventListener("click", () => abortController.abort());

try {
  const assertion = await assertionPromise;
} catch (error) {
  if (error.name === "AbortError") {
    console.log("Authentication was cancelled");
  }
}
```

---

## Related Origin Requests (ROR)

Related Origin Requests allow a passkey to be created and used across a limited set of related origins. This is useful for organizations with multiple country-code TLDs (e.g., `shopping.com`, `shopping.co.uk`) or alternate branding domains sharing the same accounts.

### Configuration

Host a JSON file at `/.well-known/webauthn` on the RP ID domain:

```json
{
  "origins": [
    "https://myshoppingrewards.com",
    "https://myshoppingcreditcard.com",
    "https://shopping.co.uk",
    "https://shopping.co.jp",
    "https://shopping.ca"
  ]
}
```

Do NOT include the RP ID's own origin in the list. The WebAuthn client queries this file when the RP ID and the calling origin don't match, then re-evaluates the binding using the expanded origin set.

### Feature Detection

```javascript
const capabilities = await PublicKeyCredential.getClientCapabilities();
if (capabilities.relatedOrigins) {
  // Related Origin Requests are supported
}
```

### Deployment Limits

A "label" is the domain segment before the effective TLD (e.g., "shopping" in `shopping.co.uk`). Clients support a minimum of 5 unique labels. Multiple origins sharing one label (e.g., `shopping.com` and `shopping.co.uk`) count as a single label.

---

## Passkey Upgrades (Conditional Create)

Conditional create allows a relying party to silently create a passkey after a successful sign-in using another credential (password, OTP), without showing a modal dialog. The passkey is created in the background if the browser and platform support it.

```javascript
// After successful password sign-in, upgrade to passkey
const capabilities = await PublicKeyCredential.getClientCapabilities();
if (capabilities.conditionalCreate) {
  const credential = await navigator.credentials.create({
    publicKey: {
      challenge: serverChallenge,
      rp: { id: "example.com", name: "Example" },
      user: {
        id: userId,
        name: "user@example.com",
        displayName: "Jane Doe"
      },
      pubKeyCredParams: [
        { alg: -7, type: "public-key" },
        { alg: -257, type: "public-key" }
      ],
      authenticatorSelection: {
        residentKey: "required",
        userVerification: "preferred"
      },
      excludeCredentials: existingCredentials
    },
    mediation: "conditional"  // Key: silent upgrade
  });

  if (credential) {
    // Send to server for storage
    await registerCredential(credential);
  }
}
```

---

## Error Handling Reference

| Error Name | Ceremony | Cause |
|------------|----------|-------|
| `NotSupportedError` | Registration | No suitable authenticator available or algorithm not supported |
| `InvalidStateError` | Registration | Credential already exists for this user on this authenticator |
| `NotAllowedError` | Both | User declined consent, timed out, or no matching credential |
| `AbortError` | Both | Operation was aborted via AbortController signal |
| `SecurityError` | Both | RP ID does not match current origin's domain |
| `TypeError` | Both | Invalid options structure or missing required fields |

---

## UX Best Practices

1. **Feature detect before offering passkeys**: Check `isUserVerifyingPlatformAuthenticatorAvailable()` and `isConditionalMediationAvailable()` before showing passkey UI elements.

2. **Use conditional UI as default sign-in**: Implement autofill-based passkey authentication on the sign-in page rather than requiring users to click a dedicated button.

3. **Offer passkey creation after successful sign-in**: After a user signs in with a password or other method, prompt them to create a passkey for faster future sign-ins.

4. **Support multiple passkeys per account**: Users may have passkeys on different devices. Allow registering and managing multiple credentials.

5. **Provide fallback authentication**: Always offer an alternative sign-in method (password, OTP) for users whose devices do not support passkeys.

6. **Prompt cross-device users to create local passkeys**: When `authenticatorAttachment` returns `"cross-platform"` after authentication, suggest creating a platform passkey for a faster experience next time.

7. **Store transport hints**: Save the result of `getTransports()` during registration and pass them back in `allowCredentials[].transports` during authentication to speed up authenticator selection.

8. **Display meaningful credential names**: Let users name their passkeys (e.g., "iPhone 15", "YubiKey") for easier management in account settings.

---

## Security Considerations

1. **Challenge integrity**: Generate challenges server-side with a CSPRNG (minimum 16 bytes). Never reuse challenges. Bind challenges to sessions and enforce expiration.

2. **Origin validation**: Always verify the `origin` in `clientDataJSON` matches your expected origin exactly. This is the primary phishing defense.

3. **RP ID validation**: Verify the `rpIdHash` in authenticator data matches the SHA-256 hash of your RP ID.

4. **Sign counter monitoring**: Track the signature counter. If it does not increment (and is non-zero), the authenticator may have been cloned. Decide whether to flag the account, require re-authentication, or block access based on your risk tolerance.

5. **Backup state awareness**: Check the BE and BS flags. For high-security scenarios, you may want to require device-bound credentials (`BE=0`).

6. **Token binding**: If your deployment supports token binding, verify the `tokenBinding` field in `clientDataJSON`.

7. **User handle privacy**: The `user.id` field is stored on the authenticator and returned during authentication. Do not use PII (email, name) as the user ID - use an opaque random identifier.

---

## Terminology Quick Reference

Source: https://passkeys.dev/docs/reference/terms/

| Term | Definition |
|------|-----------|
| **Passkey** | User-facing term for a FIDO2/WebAuthn discoverable credential. Available in synced and device-bound variants. |
| **Synced Passkey** | Discoverable credential that can be used across multiple devices through cloud synchronization |
| **Device-bound Passkey** | Discoverable credential bound to a single authenticator (e.g., FIDO2 security keys) |
| **Relying Party (RP)** | The website trying to ascertain and verify the identity of the user |
| **Platform Authenticator** | FIDO authenticator built into the user's device (Touch ID, Face ID, Windows Hello) |
| **Roaming Authenticator** | External FIDO authenticator usable with any device (USB, NFC, BLE security key) |
| **UVRA** | User-Verifying Roaming Authenticator — roaming authenticator that can verify users via biometrics or device PIN |
| **Discoverable Credential** | FIDO2/WebAuthn credential usable without initially providing a user ID; all components stored on authenticator |
| **Autofill UI / Conditional UI** | Privacy-preserving list UI rendered by browser/OS on inputs with `autocomplete="webauthn"` |
| **Conditional Create** | WebAuthn capability to silently create a passkey after successful sign-in with another credential |
| **CDA** | Cross-Device Authentication — using a passkey from one device to sign in on another via FIDO CTAP hybrid transport |
| **CDA Client** | Device where the relying party is actively accessed during cross-device authentication |
| **CDA Authenticator** | Device generating the FIDO assertion during cross-device authentication |
| **Persistent Linking** | Relationship between CDA authenticator and client eliminating QR scanning on subsequent authentications |
| **Credential Exchange** | Standardized process to securely transfer passkeys between passkey providers |
| **Attestation** | Optional statement from authenticator verifying its provenance and capabilities |
| **Assertion** | Cryptographic proof of credential possession during authentication |
| **User Presence (UP)** | Test ensuring user is in local proximity to authenticator (button press, tap) |
| **User Verification (UV)** | Biometric gesture, device PIN, or password to authorize credential use |
| **BE/BS Flags** | Backup Eligibility / Backup State flags in authenticator data |
| **Credential Manager** | Software/hardware storing and managing passkeys, passwords, OTP seeds, and other credentials |
| **Passkey Provider** | App/service responsible for storing and managing passkeys (first-party or third-party) |
| **First-Party Provider** | Passkey provider from the OS vendor, often enabled by default (Windows Hello, Apple Passwords) |
| **Third-Party Provider** | Passkey provider that plugs into the OS via platform APIs (e.g., 1Password, Dashlane) |
| **Account Bootstrapping** | Authenticating a user without prior knowledge of their identity on the device |
| **Reauthentication** | Reconfirming user identity for sensitive operations when session already exists |
| **2FA** | Contract requiring at least two distinct authentication factors during bootstrap sign-in |
