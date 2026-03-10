---
name: fido-uaf
description: "FIDO UAF v1.2 Universal Authentication Framework protocol for passwordless authentication using biometrics, PINs, and hardware authenticators."
metadata:
  languages: "http"
  versions: "1.2"
  revision: 1
  updated-on: "2026-03-09"
  source: community
  tags: "fido,uaf,authentication,passwordless,biometric,fido-alliance"
---

# FIDO UAF v1.2 Protocol

FIDO UAF (Universal Authentication Framework) enables passwordless authentication using device-based cryptographic credentials unlocked by biometrics, PINs, or other local user verification. The server never sees passwords or biometric data.

**Specification:** FIDO UAF v1.2 Proposed Standard (October 20, 2020)
**Full spec suite:** https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/

## Specification Documents

| Document | URL |
|---|---|
| Overview | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-overview-v1.2-ps-20201020.html |
| Protocol | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-protocol-v1.2-ps-20201020.html |
| Client API & Transport | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-client-api-transport-v1.2-ps-20201020.html |
| ASM API | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-asm-api-v1.2-ps-20201020.html |
| Authenticator Commands | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-authnr-cmds-v1.2-ps-20201020.html |
| Registration (AppID & Facets) | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-reg-v1.2-ps-20201020.html |
| APDU Commands | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-apdu-v1.2-ps-20201020.html |
| CBOR Encoding | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-apccbor-v1.2-ps-20201020.html |
| WebAuthn Binding | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/fido-uaf-webauthn-v1.2-ps-20201020.html |
| Complete PDF | https://fidoalliance.org/specs/fido-uaf-v1.2-ps-20201020/FIDO-UAF-COMPLETE-v1.2-ps-20201020.pdf |

---

## Architecture

### Components

- **FIDO UAF Client**: Implements client-side protocol, interacts with authenticators through the ASM abstraction layer, communicates with user agents (mobile apps, browsers)
- **FIDO UAF Server**: Validates authenticator attestations against metadata, manages credential-to-account associations, evaluates authentication responses
- **FIDO UAF Authenticator**: Secure entity that creates asymmetric key pairs bound to relying parties, provides cryptographic challenge-response and attestation
- **ASM (Authenticator-Specific Module)**: Abstraction layer providing a uniform API to authenticator cryptographic services, supports multi-vendor driver deployment

### Communication Flow

```
Relying Party App  ←→  FIDO UAF Client  ←→  ASM  ←→  Authenticator
       ↕
FIDO UAF Server
```

All protocol messages use JSON encoding with UTF-8 over TLS.

---

## Protocol Operations

### Operation Header

Every UAF message includes an `OperationHeader`:

```json
{
  "upv": { "major": 1, "minor": 2 },
  "op": "Reg",
  "appID": "https://example.com",
  "serverData": "opaque-server-session-data",
  "exts": []
}
```

- `op`: Operation type — `Reg` (Registration), `Auth` (Authentication), `Dereg` (Deregistration)
- `appID`: Application identifier (relying party origin)
- `serverData`: Opaque server session data (HMAC-protected, bound to challenge)

---

## 1. Registration

Registration creates a new authentication credential bound to a user account.

### Flow

1. Server generates a `RegistrationRequest` with challenge, policy, and username
2. Client filters available authenticators against the policy
3. Client computes `FinalChallengeParams` (appID + challenge + facetID + channel binding)
4. Authenticator generates a new key pair, signs Key Registration Data (KRD) with its attestation key
5. Client sends `RegistrationResponse` with base64url-encoded `FinalChallengeParams` and signed assertion
6. Server validates attestation signature against known authenticator metadata, stores public key and credential ID

### Registration Request

```json
[{
  "header": {
    "upv": { "major": 1, "minor": 2 },
    "op": "Reg",
    "appID": "https://example.com",
    "serverData": "..."
  },
  "challenge": "HQ1VkTUQC1NJDOo6OOWdxewrb9i5WthjfKIehFxpeuU",
  "username": "user@example.com",
  "policy": {
    "accepted": [
      [
        {
          "userVerification": 2,
          "keyProtection": 1,
          "authenticationAlgorithm": 1
        }
      ]
    ]
  }
}]
```

### Policy Matching

The `policy.accepted` field is a two-dimensional array:
- **Outer array**: OR alternatives (any one group must match)
- **Inner array**: AND combinations (all criteria in a group must match simultaneously)

`MatchCriteria` fields:

| Field | Description |
|---|---|
| `aaid` | Authenticator Attestation ID, format `VVVV#MMMM` (vendor#model) |
| `userVerification` | Bitflags: fingerprint (2), passcode (4), voiceprint (8), faceprint (16), etc. |
| `keyProtection` | Software (1), hardware (2), TEE (4), secure element (8) |
| `authenticationAlgorithm` | Signing algorithm (1=ALG_SIGN_SECP256R1_ECDSA_SHA256_RAW, etc.) |
| `assertionScheme` | Currently only `"UAFV1TLV"` |

All fields in a `MatchCriteria` object must match for the criteria to match an authenticator.

### FinalChallengeParams

The cryptographic binding between client and server:

```json
{
  "appID": "https://example.com",
  "challenge": "HQ1VkTUQC1NJDOo6OOWdxewrb9i5WthjfKIehFxpeuU",
  "facetID": "https://example.com",
  "channelBinding": {
    "serverEndPoint": "...",
    "tlsServerCertificate": "...",
    "tlsUnique": "...",
    "cid_pubkey": "..."
  }
}
```

The client serializes → UTF-8 encodes → base64url encodes this. The server hashes it; the authenticator signs the hash. This prevents MITM and replay attacks.

### Registration Response

```json
[{
  "header": {
    "upv": { "major": 1, "minor": 2 },
    "op": "Reg",
    "appID": "https://example.com",
    "serverData": "..."
  },
  "fcParams": "base64url-encoded-FinalChallengeParams",
  "assertions": [
    {
      "assertionScheme": "UAFV1TLV",
      "assertion": "base64url-encoded-KRD-with-attestation-signature"
    }
  ]
}]
```

### Server Validation

1. Verify `serverData` integrity (HMAC)
2. Decode and verify `fcParams` — check appID, challenge, facetID
3. Parse assertion TLV: extract AAID, KeyID, public key, counters
4. Verify attestation signature against known authenticator metadata certificates
5. Store (AAID, KeyID, public key, sign counter) associated with the user account

---

## 2. Authentication

Authentication proves the user controls a previously registered credential.

### Flow

1. Server sends `AuthenticationRequest` with challenge and policy
2. Client filters authenticators against policy, presents choices to user
3. User performs local verification (biometric, PIN)
4. Authenticator signs challenge hash with registered private key
5. Client returns signed assertion
6. Server verifies signature with stored public key

### Authentication Request

```json
[{
  "header": {
    "upv": { "major": 1, "minor": 2 },
    "op": "Auth",
    "appID": "https://example.com",
    "serverData": "..."
  },
  "challenge": "R29vZCBtb3JuaW5nIQ",
  "policy": {
    "accepted": [
      [{ "aaid": ["ABCD#0001"] }]
    ]
  }
}]
```

### Authentication Response

```json
[{
  "header": {
    "upv": { "major": 1, "minor": 2 },
    "op": "Auth",
    "appID": "https://example.com",
    "serverData": "..."
  },
  "fcParams": "base64url-encoded-FinalChallengeParams",
  "assertions": [
    {
      "assertionScheme": "UAFV1TLV",
      "assertion": "base64url-encoded-signed-assertion"
    }
  ]
}]
```

### Server Validation

1. Verify `serverData` integrity
2. Decode and verify `fcParams`
3. Parse assertion: extract AAID, KeyID, signature, counters
4. Look up stored public key by (AAID, KeyID)
5. Verify signature over `authenticatorData + SHA-256(FinalChallengeParams)`
6. Verify and update sign counter (detect cloned authenticators)
7. Authenticate the user

---

## 3. Transaction Confirmation

Extends authentication with a displayed message for "What You See Is What You Sign" (WYSIWYS). The authenticator presents transaction details to the user and signs them along with the challenge.

- Requires authenticators with transaction display capability
- Transaction content is passed through the protocol extensions
- Used for financial transactions, privileged operations, and authorization scenarios

---

## 4. Deregistration

Removes a credential from the authenticator. Triggered when accounts are cancelled, devices are lost/stolen, or users want to revoke access.

### Deregistration Request

```json
[{
  "header": {
    "upv": { "major": 1, "minor": 2 },
    "op": "Dereg",
    "appID": "https://example.com"
  },
  "authenticators": [
    {
      "aaid": "ABCD#0001",
      "keyID": "base64url-encoded-key-id"
    }
  ]
}]
```

The client forwards the (AAID, KeyID) tuple to the authenticator, which erases the key material. No response is returned to the server.

---

## Client APIs

### JavaScript (Web) — DOM API

```javascript
// Discover available authenticators
navigator.fido.uaf.discover(function(discoveryData) {
  // discoveryData.availableAuthenticators[] contains authenticator metadata
  // Each has: aaid, assertionScheme, authenticationAlgorithm,
  //           userVerification, keyProtection, supportedUAFVersions
}, function(errorCode) {
  console.error("Discovery failed:", errorCode);
});

// Process a UAF operation (registration, authentication)
var uafMessage = {
  uafProtocolMessage: JSON.stringify(serverRequest),
  additionalData: {}
};

navigator.fido.uaf.processUAFOperation(uafMessage, function(uafResponse) {
  // Send uafResponse.uafProtocolMessage to server for verification
  fetch("/uaf/response", {
    method: "POST",
    body: uafResponse.uafProtocolMessage
  });
}, function(errorCode) {
  console.error("Operation failed:", errorCode);
});

// Check if a policy can be satisfied without user interaction
navigator.fido.uaf.checkPolicy(uafMessage, function(errorCode) {
  if (errorCode === 0) {
    // Policy can be satisfied
  }
});

// Notify client of server result
navigator.fido.uaf.notifyUAFResult(resultCode, function() {
  // Server result acknowledged
});
```

### Android — Intent API

```java
// Create intent for FIDO UAF operation
Intent intent = new Intent("org.fidoalliance.intent.FIDO_OPERATION");
intent.setType("application/fido.uaf_client+json");
intent.putExtra("UAFIntentType", "UAF_OPERATION");
intent.putExtra("message", uafProtocolMessageJson);
intent.putExtra("channelBindings", channelBindingJson);

startActivityForResult(intent, FIDO_REQUEST_CODE);

// Handle response
@Override
protected void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode == FIDO_REQUEST_CODE && resultCode == RESULT_OK) {
        String uafResponse = data.getStringExtra("message");
        int errorCode = data.getIntExtra("errorCode", -1);
        // Send uafResponse to server for verification
    }
}
```

### iOS — Custom URL Scheme

```
FidoUAFClient1://x-callback-url/[UAFxType]
  ?x-success=[RelyingPartyURL]
  &key=[SecretKey]
  &state=[STATE]
  &json=[Base64URLEncodedJSON]
```

Responses are encrypted using JWE with the caller-provided secret key. The `sourceApplication` parameter provides the bundle ID for facet verification.

---

## Facet IDs

Facet IDs identify the calling application to the FIDO client:

| Platform | Format | Example |
|---|---|---|
| Web | Origin (scheme:host:port) | `https://example.com` |
| Android | `android:apk-key-hash:[hash]` | `android:apk-key-hash:Lir5oIjf552K...` |
| iOS | `ios:bundle-id` | `ios:bundle-id:com.example.app` |

The FIDO client validates facet IDs against the server's trusted facet list hosted at the appID URL.

### Trusted Facet List

```json
{
  "trustedFacets": [
    {
      "version": { "major": 1, "minor": 2 },
      "ids": [
        "https://example.com",
        "android:apk-key-hash:Lir5oIjf552K...",
        "ios:bundle-id:com.example.app"
      ]
    }
  ]
}
```

---

## Credential Identification

The `(AAID, KeyID)` tuple uniquely identifies a registered credential:

- **AAID** (Authenticator Attestation ID): Format `VVVV#MMMM` — 4-char hex vendor code + 4-char hex model code
- **KeyID**: Authenticator-generated, base64url-encoded, 32–2048 bytes

Servers return the KeyID during authentication and deregistration to direct operations to specific credentials.

---

## Error Codes

| Code | Name | Description |
|---|---|---|
| 0 | `NO_ERROR` | Operation completed successfully |
| 1 | `WAIT_USER_ACTION` | Waiting for user interaction |
| 2 | `INSECURE_TRANSPORT` | TLS required but not available |
| 3 | `USER_CANCELLED` | User declined the operation |
| 4 | `UNSUPPORTED_VERSION` | Protocol version not supported |
| 5 | `NO_SUITABLE_AUTHENTICATOR` | No authenticator matches the policy |
| 6 | `PROTOCOL_ERROR` | Malformed or invalid message |
| 7 | `UNTRUSTED_FACET_ID` | Facet ID not in trusted list |
| 255 | `UNKNOWN` | Unspecified error |

### Server Result Codes

| Code | Meaning |
|---|---|
| 1200 | Success |
| 1202 | Accepted (processing) |
| 1400 | Bad request |
| 1401 | Unauthorized |
| 1403 | Forbidden |
| 1404 | Not found |
| 1408 | Request timeout |
| 1480 | Unknown AAID |
| 1481 | Unknown KeyID |
| 1490 | Channel binding refused |
| 1491 | Invalid request |
| 1492 | Unacceptable authenticator |
| 1493 | Revoked authenticator |
| 1494 | Unacceptable key |
| 1495 | Unacceptable algorithm |
| 1496 | Unacceptable attestation |
| 1497 | Unacceptable client capabilities |
| 1498 | Unacceptable content |
| 1500 | Internal server error |

---

## Privacy Design

- **No global identifiers**: Unique asymmetric key pair per device-user-relying party combination
- **Local verification**: Biometric data and PINs never leave the device
- **Batch attestation**: Attestation certificates shared across minimum 100,000 units for unlinkability
- **Explicit consent**: User must approve every credential creation and authentication ceremony
- **Minimal data**: Server stores only public key and credential ID — no biometrics, no passwords

---

## Relationship to WebAuthn and FIDO2

FIDO UAF v1.2 includes a **WebAuthn binding** specification that maps UAF concepts to the W3C Web Authentication API:

- UAF Registration → WebAuthn `navigator.credentials.create()`
- UAF Authentication → WebAuthn `navigator.credentials.get()`
- UAF Authenticator → WebAuthn Authenticator
- UAF ASM → WebAuthn Platform/Cross-platform authenticator abstraction

For new web deployments, **WebAuthn/FIDO2 (passkeys)** is the recommended path. FIDO UAF remains relevant for:
- Native mobile apps with existing UAF integrations
- Deployments using UAF-specific authenticator types
- Systems requiring UAF's transaction confirmation capabilities
- Environments using the Android Intent or iOS URL scheme APIs
