---
name: digital-credentials-api
description: "W3C Digital Credentials API for requesting and issuing verifiable digital credentials via the browser using OpenID4VP and OpenID4VCI protocols."
metadata:
  languages: "javascript"
  versions: "1.0.0"
  revision: 1
  updated-on: "2026-03-09"
  source: community
  tags: "digital-credentials,verifiable-credentials,oid4vp,oid4vci,w3c,identity,mdoc,sd-jwt"
---

# Digital Credentials API - JavaScript Implementation Guide

## Golden Rule

**ALWAYS use the browser-native `navigator.credentials.get()` / `navigator.credentials.create()` with the `digital` option for verifiable credential presentation and issuance.**

**DO NOT:**
- Build custom credential exchange protocols when the Digital Credentials API is available
- Skip transient user activation — the API requires it for every call
- Use `mediation` values other than `"required"` (will throw `TypeError`)
- Send PII in unencrypted request payloads — requests are unencrypted, responses must be encrypted
- Assume protocol support without checking `DigitalCredential.userAgentAllowsProtocol()`

**Specification references:**
- W3C Digital Credentials API: https://www.w3.org/TR/digital-credentials/
- Developer guide: https://digitalcredentials.dev/
- OpenID4VP 1.0 (Final): https://openid.net/specs/openid-4-verifiable-presentations-1_0.html
- OpenID4VCI 1.0 (Final): https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html

---

## Overview

The Digital Credentials API is a W3C specification that extends the Credential Management API to enable web applications to request and issue verifiable digital credentials (VDCs). It bridges websites with platform-level credential managers (digital wallets) through a protocol-agnostic browser API.

**Key properties:**
- **Protocol-agnostic**: Supports multiple presentation/issuance protocols (OpenID4VP, ISO 18013-7)
- **Privacy-preserving**: Browser mediates all credential exchanges; requests are inspectable by the user agent
- **Platform-integrated**: Leverages OS-level credential managers (Google Credential Manager, Apple Wallet)
- **Cross-device capable**: Uses FIDO CTAP 2.2 hybrid transports for credentials on another device

**Entities:**
- **Holder**: Person who possesses credentials in a wallet/credential manager
- **Issuer**: Organization that creates and signs credentials
- **Verifier**: Website or app that requests credential presentations

---

## Feature Detection

```javascript
// Check if the Digital Credentials API is available
if ("DigitalCredential" in window) {
  console.log("Digital Credentials API supported");
}

// Check if a specific protocol is allowed by the user agent
const supportsOID4VP = DigitalCredential.userAgentAllowsProtocol("openid4vp-v1-unsigned");
const supportsMdoc = DigitalCredential.userAgentAllowsProtocol("org-iso-mdoc");
```

---

## Credential Presentation (Requesting Credentials)

Use `navigator.credentials.get()` with the `digital` option to request a verifiable credential presentation from the user's wallet.

### Basic Presentation Request

```javascript
const controller = new AbortController();

try {
  const credential = await navigator.credentials.get({
    signal: controller.signal,
    mediation: "required", // MUST be "required"
    digital: {
      requests: [
        {
          protocol: "openid4vp-v1-unsigned",
          data: {
            nonce: crypto.randomUUID(),
            client_id: "https://verifier.example.com",
            client_id_scheme: "web-origin",
            response_type: "vp_token",
            dcql_query: {
              credentials: {
                my_credential: {
                  format: "vc+sd-jwt",
                  "vc+sd-jwt": {
                    vct: "https://credentials.example.com/identity_credential"
                  },
                  claims: [
                    { path: ["given_name"] },
                    { path: ["family_name"] }
                  ]
                }
              }
            }
          }
        }
      ]
    }
  });

  // credential.protocol — the protocol used (e.g., "openid4vp-v1-unsigned")
  // credential.data — the response object (protocol-specific, typically encrypted)
  console.log("Protocol:", credential.protocol);
  console.log("Response:", credential.data);
} catch (err) {
  if (err.name === "AbortError") {
    console.log("User cancelled");
  } else if (err.name === "NotAllowedError") {
    console.log("No transient user activation or permission denied");
  } else {
    console.error("Presentation failed:", err);
  }
}
```

### Multiple Protocol Support

Specify multiple protocols to maximize wallet compatibility. The browser selects the first supported protocol.

```javascript
const credential = await navigator.credentials.get({
  mediation: "required",
  digital: {
    requests: [
      {
        protocol: "openid4vp-v1-unsigned",
        data: {
          nonce: crypto.randomUUID(),
          client_id: "https://verifier.example.com",
          client_id_scheme: "web-origin",
          response_type: "vp_token",
          dcql_query: {
            credentials: {
              pid: {
                format: "vc+sd-jwt",
                "vc+sd-jwt": {
                  vct: "https://issuer.example.com/pid"
                },
                claims: [
                  { path: ["age_over_18"] }
                ]
              }
            }
          }
        }
      },
      {
        protocol: "org-iso-mdoc",
        data: {
          // ISO 18013-7 Annex C request format
          // Required for iOS/Safari compatibility
        }
      }
    ]
  }
});
```

### Cancellation

```javascript
const controller = new AbortController();

// Cancel after 60 seconds
setTimeout(() => controller.abort(), 60_000);

// Or cancel on user action
document.getElementById("cancel-btn").addEventListener("click", () => {
  controller.abort();
});

const credential = await navigator.credentials.get({
  signal: controller.signal,
  mediation: "required",
  digital: { requests: [/* ... */] }
});
```

---

## Credential Issuance (Creating Credentials)

Use `navigator.credentials.create()` with the `digital` option to issue a credential to the user's wallet.

```javascript
const credential = await navigator.credentials.create({
  digital: {
    requests: [
      {
        protocol: "openid4vci-v1",
        data: {
          // OpenID4VCI credential offer data
          credential_issuer: "https://issuer.example.com",
          credential_configuration_ids: ["identity_credential"],
          grants: {
            "urn:ietf:params:oauth:grant-type:pre-authorized_code": {
              "pre-authorized_code": "oaKazRN8I0IbtZ0C7JuMn5"
            }
          }
        }
      }
    ]
  }
});

console.log("Issuance protocol:", credential.protocol);
console.log("Issuance response:", credential.data);
```

---

## DCQL (Digital Credentials Query Language)

DCQL is a JSON-based query language for expressing which credentials and claims a verifier needs. It is defined as part of OpenID4VP.

### Requesting Specific Claims

```javascript
const dcqlQuery = {
  credentials: {
    identity: {
      format: "vc+sd-jwt",
      "vc+sd-jwt": {
        vct: "https://credentials.example.com/identity_credential",
        alg_values: ["ES256", "ES384"],
        hash_alg_values: ["SHA-256"]
      },
      purpose: "Identity verification for account creation",
      claims: [
        { path: ["given_name"] },
        { path: ["family_name"] },
        { path: ["email"] }
      ]
    }
  }
};
```

### Alternative Claims (require N of M)

```javascript
const dcqlQuery = {
  credentials: {
    age_check: {
      format: "vc+sd-jwt",
      "vc+sd-jwt": {
        vct: "https://credentials.example.com/identity_credential"
      },
      claims: [
        {
          // Require at least 1 of these alternatives
          required: 1,
          from: [
            { path: ["age_over_18"] },
            { path: ["birth_date"] }
          ]
        }
      ]
    }
  }
};
```

### Nested Claims

```javascript
const dcqlQuery = {
  credentials: {
    address_check: {
      format: "vc+sd-jwt",
      "vc+sd-jwt": {
        vct: "https://credentials.example.com/identity_credential"
      },
      claims: [
        { path: ["address", "street_address"] },
        { path: ["address", "locality"] },
        { path: ["address", "country"] }
      ]
    }
  }
};
```

### mdoc Format Claims

For ISO 18013-5 mdoc credentials, claims use namespace-based addressing:

```javascript
const dcqlQuery = {
  credentials: {
    mdl: {
      format: "mso_mdoc",
      "mso_mdoc": {
        doctype: "org.iso.18013.5.1.mDL"
      },
      claims: [
        { namespace: "org.iso.18013.5.1", claim_name: "given_name" },
        { namespace: "org.iso.18013.5.1", claim_name: "family_name" },
        { namespace: "org.iso.18013.5.1", claim_name: "portrait" },
        { namespace: "org.iso.18013.5.1", claim_name: "age_over_21" }
      ]
    }
  }
};
```

---

## Credential Formats

### SD-JWT VC (Selective Disclosure JWT Verifiable Credentials)

- DCQL format identifier: `vc+sd-jwt`
- JWT-based with selective disclosure via cryptographic commitments
- Hash-based privacy with salt values
- Standard JSON within JWT structures
- Widely supported on Android

### ISO 18013-5 mdoc (Mobile Document)

- DCQL format identifier: `mso_mdoc`
- CBOR encoding with COSE cryptographic operations
- Optimized for mobile and offline scenarios
- Supports QR, NFC, device-to-device
- Required format for iOS/iPadOS (Apple Wallet)
- Common doctypes: `org.iso.18013.5.1.mDL` (mobile driver's license)

### W3C Verifiable Credentials

- DCQL format identifiers: `jwt_vc_json`, `ldp_vc`
- JSON-LD format with JSON Web Signatures or Linked Data Proofs

---

## Protocol Identifiers

### Presentation Protocols

| Protocol ID | Description |
|---|---|
| `openid4vp-v1-unsigned` | OpenID4VP with unsigned request |
| `openid4vp-v1-signed` | OpenID4VP with signed request |
| `openid4vp-v1-multisigned` | OpenID4VP with multi-signed request |
| `org-iso-mdoc` | ISO 18013-7 Annex C (required for iOS) |

### Issuance Protocols

| Protocol ID | Description |
|---|---|
| `openid4vci-v1` | OpenID for Verifiable Credential Issuance |

---

## Permissions Policy

The Digital Credentials API is gated by permissions policy features:

```html
<!-- Default: allowed for same-origin only -->
<!-- To allow in cross-origin iframes: -->
<iframe src="https://verifier.example.com"
        allow="digital-credentials-get; digital-credentials-create">
</iframe>
```

Policy features:
- `digital-credentials-get` — controls `navigator.credentials.get()` with `digital` option
- `digital-credentials-create` — controls `navigator.credentials.create()` with `digital` option

Default allowlist for both: `'self'`

---

## Security Requirements

1. **Transient user activation**: Every `get()` or `create()` call requires a recent user gesture (click, tap, key press). Calls without activation throw `NotAllowedError`.

2. **Mediation must be "required"**: Setting `mediation` to any value other than `"required"` throws `TypeError`.

3. **Secure context**: API only available in secure contexts (HTTPS).

4. **Request transparency**: Request data is unencrypted so the browser can inspect it for user consent. Never include PII in request data.

5. **Response encryption**: Responses containing PII must be encrypted by the credential manager before returning to the website.

---

## Platform and Browser Support

### Browser Support

| Browser | Presentation | Issuance | Platforms |
|---|---|---|---|
| Chrome 141+ | Yes | Yes | Android, ChromeOS, macOS, Ubuntu, Windows |
| Safari 141+ | Yes | Yes | macOS only |
| Firefox | In development | In development | — |
| Edge | In development | In development | — |

### Mobile Platform Support

**Android:**
- Supports all protocols and credential formats
- Cross-device presentation (XDP) supported
- Uses Google Credential Manager API for wallet apps

**iOS/iPadOS (OS 26+):**
- Only supports ISO 18013-7 Annex C protocol for presentation
- Only supports ISO 18013-5 mdoc format
- Supported doctypes: `org.iso.18013.5.1.mDL`, `org.iso.23220.1.jp.mnc`, `org.iso.23220.photoid.1`, `eu.europa.ec.eudi.pid.1`
- OpenID4VP (Annex D) NOT supported
- Uses Apple Wallet

**Key limitation:** Safari on macOS only allows ISO 18013-7 Annex C requests, preventing other protocols from reaching cross-device wallets.

---

## Error Handling

```javascript
try {
  const credential = await navigator.credentials.get({
    mediation: "required",
    digital: { requests: [/* ... */] }
  });
} catch (err) {
  switch (err.name) {
    case "NotAllowedError":
      // No transient user activation, or user denied permission
      break;
    case "TypeError":
      // Invalid mediation value, or malformed request
      break;
    case "AbortError":
      // Request was aborted via AbortController
      break;
    case "NotSupportedError":
      // None of the requested protocols are supported
      break;
    case "SecurityError":
      // Not in a secure context, or permissions policy blocks usage
      break;
  }
}
```

---

## Complete Verifier Example

```javascript
async function requestIdentityCredential() {
  // 1. Check API support
  if (!("DigitalCredential" in window)) {
    throw new Error("Digital Credentials API not supported");
  }

  // 2. Check protocol support
  if (!DigitalCredential.userAgentAllowsProtocol("openid4vp-v1-unsigned")) {
    throw new Error("OpenID4VP not supported by this browser");
  }

  // 3. Generate nonce server-side (shown inline for brevity)
  const nonce = crypto.randomUUID();

  // 4. Request credential
  const controller = new AbortController();
  const credential = await navigator.credentials.get({
    signal: controller.signal,
    mediation: "required",
    digital: {
      requests: [
        {
          protocol: "openid4vp-v1-unsigned",
          data: {
            nonce: nonce,
            client_id: window.location.origin,
            client_id_scheme: "web-origin",
            response_type: "vp_token",
            dcql_query: {
              credentials: {
                identity: {
                  format: "vc+sd-jwt",
                  "vc+sd-jwt": {
                    vct: "https://credentials.example.com/identity_credential"
                  },
                  claims: [
                    { path: ["given_name"] },
                    { path: ["family_name"] },
                    { path: ["email"] }
                  ]
                }
              }
            }
          }
        }
      ]
    }
  });

  // 5. Send response to server for verification
  const response = await fetch("/api/verify-credential", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      protocol: credential.protocol,
      data: credential.data,
      nonce: nonce
    })
  });

  return response.json();
}

// Must be called from a user gesture handler
document.getElementById("verify-btn").addEventListener("click", async () => {
  try {
    const result = await requestIdentityCredential();
    console.log("Verification result:", result);
  } catch (err) {
    console.error("Credential request failed:", err);
  }
});
```

---

## OpenID DCP Specifications

The Digital Credentials API relies on protocols defined by the OpenID Digital Credentials Protocols (DCP) Working Group. These are the authoritative specifications.

### Final Specifications (1.0)

| Specification | URL | Purpose |
|---|---|---|
| OpenID for Verifiable Presentations (OID4VP) 1.0 | https://openid.net/specs/openid-4-verifiable-presentations-1_0.html | Presentation of verifiable credentials — defines the request/response protocol used with `navigator.credentials.get()` via `openid4vp-v1-*` protocol identifiers |
| OpenID for Verifiable Credential Issuance (OID4VCI) 1.0 | https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html | Issuance of verifiable credentials — defines the credential offer protocol used with `navigator.credentials.create()` via the `openid4vci-v1` protocol identifier |

### Implementer's Drafts

| Specification | URL | Purpose |
|---|---|---|
| OpenID4VC High Assurance Interoperability Profile (HAIP) | https://openid.net/specs/openid4vc-high-assurance-interoperability-profile-1_0-04.html | Constrained profile of OID4VP/OID4VCI for high-assurance use cases with SD-JWT VC and mdoc formats |

### Working Drafts

| Specification | URL | Purpose |
|---|---|---|
| Security and Trust in OpenID for Verifiable Credentials | https://openid.github.io/OpenID4VC_SecTrust/draft-oid4vc-security-and-trust.html | Trust architecture, security considerations, and ecosystem component requirements |
| OpenID for Verifiable Presentations over BLE | https://github.com/openid/openid4vp_ble | Bluetooth Low Energy transport for credential presentation (proximity scenarios) |

### How Specs Map to the API

```
navigator.credentials.get({ digital: { requests: [{ protocol: "openid4vp-v1-unsigned", data: {...} }] } })
                                                     ↑                                      ↑
                                                     OID4VP 1.0 defines this protocol        OID4VP 1.0 defines this payload format

navigator.credentials.create({ digital: { requests: [{ protocol: "openid4vci-v1", data: {...} }] } })
                                                       ↑                                     ↑
                                                       OID4VCI 1.0 defines this protocol     OID4VCI 1.0 defines credential offer format
```

The W3C Digital Credentials API spec defines the browser-level plumbing (`navigator.credentials` extension, `DigitalCredential` interface, permissions policy). The OID4VP and OID4VCI specs define what goes inside `protocol` and `data`.

---

## Related Open Source Projects

| Project | URL | Description |
|---|---|---|
| EU Digital Identity Wallet | https://github.com/eu-digital-identity-wallet | Reference wallet |
| OWF Identity Credential | https://github.com/openwallet-foundation-labs/identity-credential | Reference wallet + verifier |
| OpenCred | https://github.com/stateofca/opencred | Web-based verifier |
| CMWallet | https://github.com/digitalcredentialsdev/CMWallet | Sample Android wallet |
| Test Verifier | https://demo.digitalcredentials.dev | Live demo verifier |
