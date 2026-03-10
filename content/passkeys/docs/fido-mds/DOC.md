---
name: fido-mds
description: "FIDO Metadata Service v3.1 for authenticator metadata, attestation trust anchors, security status tracking, and certification validation."
metadata:
  languages: "http"
  versions: "3.1"
  revision: 1
  updated-on: "2026-03-09"
  source: community
  tags: "fido,mds,metadata,attestation,authenticator,passkeys,certification"
---

# FIDO Metadata Service (MDS) v3.1

The FIDO Metadata Service provides a standardized way for relying parties to access authenticator metadata — trust anchors for attestation validation, security status reports, and authenticator capability descriptions.

**Specification:** FIDO MDS v3.1 Proposed Standard (May 21, 2025)
**Spec suite:** https://fidoalliance.org/specs/mds/

## Specification Documents

| Document | URL |
|---|---|
| Metadata Service v3.1 | https://fidoalliance.org/specs/mds/fido-metadata-service-v3.1-ps-20250521.html |
| Metadata Statement v3.1 | https://fidoalliance.org/specs/mds/fido-metadata-statement-v3.1-ps-20250521.html |
| Convenience Metadata Service v1.0 | https://fidoalliance.org/specs/mds/fido-convenience-metadata-service-v1.0-ps-20250521.html |

**Review Draft (latest):** MDS v3.1.1-rd02 (February 13, 2026)

---

## Architecture

```
Authenticator Vendors → FIDO Alliance (publishes BLOB) → FIDO Server (downloads, verifies) → Relying Party (policy decisions)
```

1. Authenticator vendors submit metadata statements during FIDO certification
2. FIDO Alliance publishes a signed metadata BLOB at a well-known URL
3. FIDO servers download, cache, and verify the BLOB locally
4. Relying parties consume parsed entries for attestation validation and policy enforcement

---

## Metadata BLOB

The metadata BLOB is a **JSON Web Token (JWT)** containing all authenticator metadata entries.

Format: `Base64url(Header).Base64url(Payload).Base64url(Signature)`

### BLOB Verification Process

1. Decode the JWT header, extract the certificate chain from `x5c`
2. Validate the certificate chain to the FIDO Alliance root certificate
3. Verify the JWT signature using the leaf certificate's public key
4. Decode the payload as `MetadataBLOBPayload`
5. Verify the `no` (serial number) increments by exactly one from previous BLOB
6. Check `nextUpdate` date — re-fetch if expired

### MetadataBLOBPayload

```json
{
  "legalHeader": "https://fidoalliance.org/metadata/metadata-statement-legal-header/",
  "no": 42,
  "nextUpdate": "2026-04-01",
  "entries": [
    {
      "aaguid": "7a98c250-6808-11cf-b73b-00aa00b677a7",
      "metadataStatement": { ... },
      "statusReports": [ ... ],
      "timeOfLastStatusChange": "2025-12-15"
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `no` | Number | Serial number, strictly monotonically increasing |
| `nextUpdate` | String | ISO-8601 date of next scheduled BLOB update |
| `entries` | Array | Array of `MetadataBLOBPayloadEntry` objects |
| `legalHeader` | String | Legal agreement acceptance notice |

---

## MetadataBLOBPayloadEntry

Each entry identifies an authenticator model and its metadata. Authenticators are identified by exactly one of:

| Identifier | Protocol | Format |
|---|---|---|
| `aaid` | FIDO UAF | `VVVV#MMMM` (vendor#model hex) |
| `aaguid` | FIDO2/WebAuthn | UUID string (e.g., `"7a98c250-6808-..."`) |
| `attestationCertificateKeyIdentifiers` | FIDO U2F | Hex-encoded certificate key identifiers |

### Entry Fields

```json
{
  "aaguid": "7a98c250-6808-11cf-b73b-00aa00b677a7",
  "metadataStatement": {
    "description": "YubiKey 5 Series",
    "protocolFamily": "fido2",
    "authenticatorVersion": 50200,
    "authenticationAlgorithms": ["secp256r1_ecdsa_sha256_raw"],
    "publicKeyAlgAndEncodings": ["cose"],
    "attestationTypes": ["basic_full"],
    "userVerificationDetails": [[
      { "userVerificationMethod": "presence_internal" },
      { "userVerificationMethod": "passcode_internal",
        "caDesc": { "base": 10, "minLength": 4, "maxRetries": 8, "blockSlowdown": 0 }
      }
    ]],
    "keyProtection": ["hardware", "secure_element"],
    "matcherProtection": ["on_chip"],
    "attachmentHint": ["external", "wired", "nfc"],
    "isKeyRestricted": true,
    "cryptoStrength": 128,
    "icon": "data:image/png;base64,..."
  },
  "statusReports": [
    {
      "status": "FIDO_CERTIFIED_L1",
      "effectiveDate": "2025-06-15",
      "certificateNumber": "FIDO20020250615001",
      "certificationDescriptor": "YubiKey 5 FIPS Series",
      "certificationPolicyVersion": "1.4.0"
    }
  ],
  "timeOfLastStatusChange": "2025-06-15"
}
```

---

## Status Reports

The `statusReports` array tracks an authenticator's security and certification status. The **latest entry reflects the current status**; earlier entries document issue history.

### AuthenticatorStatus Values

#### Certification Statuses

| Status | Meaning |
|---|---|
| `NOT_FIDO_CERTIFIED` | No FIDO certification |
| `SELF_ASSERTION_SUBMITTED` | Vendor submitted self-certification checklist |
| `FIDO_CERTIFIED` | Passed FIDO functional certification (legacy) |
| `FIDO_CERTIFIED_L1` | FIDO Certified Level 1 |
| `FIDO_CERTIFIED_L2` | FIDO Certified Level 2 |
| `FIDO_CERTIFIED_L3` | FIDO Certified Level 3 |
| `FIDO_CERTIFIED_L3plus` | FIDO Certified Level 3+ |
| `FIPS140_CERTIFIED_L1` | FIPS 140 Level 1 |
| `FIPS140_CERTIFIED_L2` | FIPS 140 Level 2 |
| `FIPS140_CERTIFIED_L3` | FIPS 140 Level 3 |
| `FIPS140_CERTIFIED_L4` | FIPS 140 Level 4 |

#### Security Issue Statuses

| Status | Meaning | Action |
|---|---|---|
| `USER_VERIFICATION_BYPASS` | Malware can bypass user verification without consent | Increased risk — consider blocking |
| `ATTESTATION_KEY_COMPROMISE` | Attestation key known compromised | Use `batchCertificate` to identify affected batch |
| `USER_KEY_REMOTE_COMPROMISE` | Registered keys can be compromised remotely | Block or require re-registration |
| `USER_KEY_PHYSICAL_COMPROMISE` | Keys extractable by physical adversary | Risk-based decision |
| `REVOKED` | Should not be trusted (fraudulent/backdoored) | Block immediately |

#### Informational

| Status | Meaning |
|---|---|
| `UPDATE_AVAILABLE` | Firmware/software update published; addresses all prior reported issues |

**Important:** FIDO Servers MUST silently ignore unknown `AuthenticatorStatus` values for forward compatibility.

### StatusReport Fields

```json
{
  "status": "ATTESTATION_KEY_COMPROMISE",
  "effectiveDate": "2025-11-01",
  "batchCertificate": "MIIBfjCCASSgAwIBAgI...",
  "url": "https://vendor.example.com/security-advisory-2025",
  "authenticatorVersion": 50100,
  "certificateNumber": "FIDO20020250615001",
  "certificationPolicyVersion": "1.4.0",
  "certificationProfiles": ["consumer", "enterprise"]
}
```

---

## Metadata Statement

The `MetadataStatement` describes an authenticator's full capabilities.

### Required Fields

| Field | Type | Description |
|---|---|---|
| `description` | String | Brief human-readable description |
| `authenticatorVersion` | Number | Firmware/software version |
| `protocolFamily` | String | `"uaf"`, `"u2f"`, or `"fido2"` |
| `schema` | Number | Schema version |
| `upv` | Array | Supported protocol versions |
| `authenticationAlgorithms` | Array | Supported signing algorithms |
| `publicKeyAlgAndEncodings` | Array | Supported key formats |
| `attestationTypes` | Array | `"basic_full"`, `"basic_surrogate"`, `"attca"`, `"ecdaa"` |
| `userVerificationDetails` | Array | Verification method combinations |
| `keyProtection` | Array | `"software"`, `"hardware"`, `"tee"`, `"secure_element"` |
| `matcherProtection` | Array | `"software"`, `"tee"`, `"on_chip"` |
| `tcDisplay` | Array | Transaction confirmation display capabilities |

### Optional Fields

| Field | Type | Description |
|---|---|---|
| `friendlyNames` | Object | Localized trade names (IETF language codes → names) |
| `alternativeDescriptions` | Object | Localized descriptions |
| `attachmentHint` | Array | `"internal"`, `"external"`, `"wired"`, `"wireless"`, `"nfc"`, `"bluetooth"`, `"ble"`, `"lightning"` |
| `isKeyRestricted` | Boolean | Whether keys are restricted to specific uses |
| `isFreshUserVerificationRequired` | Boolean | Whether fresh verification needed per transaction |
| `cryptoStrength` | Number | Estimated cryptographic strength in bits |
| `icon` | String | Base64url-encoded PNG/SVG device icon |
| `extensionDescriptors` | Array | Supported FIDO extensions |

### User Verification Methods

Verification methods use `USER_VERIFY` constants:

| Constant | Description |
|---|---|
| `presence_internal` | Physical presence test (button press) |
| `passcode_internal` | Device PIN/passcode |
| `passcode_external` | External PIN entry |
| `fingerprint_internal` | Built-in fingerprint sensor |
| `faceprint_internal` | Built-in face recognition |
| `voiceprint_internal` | Voice recognition |
| `eyeprint_internal` | Iris/retina scan |
| `handprint_internal` | Hand geometry |
| `pattern_internal` | Lock pattern (swipe) |
| `pattern_external` | External pattern entry |

### Accuracy Descriptors

**CodeAccuracyDescriptor** (for passcodes):

```json
{
  "base": 10,
  "minLength": 6,
  "maxRetries": 5,
  "blockSlowdown": 30
}
```

**BiometricAccuracyDescriptor** (for biometrics):

```json
{
  "selfAttestedFRR": 0.03,
  "selfAttestedFAR": 0.00002,
  "maxTemplates": 5,
  "maxRetries": 3,
  "blockSlowdown": 60
}
```

**PatternAccuracyDescriptor** (for patterns):

```json
{
  "minComplexity": 10000,
  "maxRetries": 5,
  "blockSlowdown": 30
}
```

---

## Biometric Status Reports

Tracks biometric component certification:

```json
{
  "certLevel": 1,
  "modality": "fingerprint_internal",
  "effectiveDate": "2025-03-01",
  "certificateNumber": "BIO-2025-001",
  "certificationDescriptor": "Fingerprint sensor evaluated per FIDO biometrics requirements",
  "certificationPolicyVersion": "1.1.0"
}
```

---

## Rogue List

Individual authenticator revocations (by ECDAA secret key):

```json
[
  {"sk": "MO-oaqbeJSSayzXaDUhh9LMKeT4Zio1bqn6W8kDaUfM", "date": "2025-06-07"},
  {"sk": "k96Npt4jJIq7NNoNSGH0swp5PhU6jVuyf5jyYNtxrNQ", "date": "2025-06-09"}
]
```

The `rogueListURL` in the entry points to this list; `rogueListHash` (base64url SHA-256) verifies integrity.

---

## Server Implementation Guide

### Fetching and Processing the BLOB

```
1. Download JWT BLOB from FIDO Alliance MDS endpoint
2. Decode JWT header → extract x5c certificate chain
3. Validate chain to FIDO Alliance root CA
4. Verify JWT signature with leaf certificate public key
5. Decode payload → MetadataBLOBPayload
6. Verify no > previous no (exactly +1)
7. Cache locally; re-fetch when nextUpdate expires
```

### Using Metadata for Attestation Validation

During WebAuthn registration:

```
1. Extract AAGUID from authenticator data
2. Look up entry in cached BLOB by AAGUID
3. Check statusReports — reject if REVOKED or key compromise
4. Extract metadataStatement.attestationTypes
5. Verify attestation signature against trust anchors from metadata
6. Apply RP policy based on:
   - keyProtection (require hardware?)
   - matcherProtection (require on_chip?)
   - certification level (require L1+?)
   - attachmentHint (platform vs external?)
```

### Policy Decision Matrix

| Status | Recommended Action |
|---|---|
| `FIDO_CERTIFIED_L1+` | Accept |
| `SELF_ASSERTION_SUBMITTED` | Accept with lower trust |
| `NOT_FIDO_CERTIFIED` | Risk-based decision |
| `UPDATE_AVAILABLE` | Accept, recommend user updates device |
| `USER_VERIFICATION_BYPASS` | Elevated risk — consider blocking or requiring re-enrollment |
| `ATTESTATION_KEY_COMPROMISE` | Check `batchCertificate` — block affected batch |
| `USER_KEY_REMOTE_COMPROMISE` | Block and require re-registration |
| `REVOKED` | Block immediately |

---

## Key Design Principles

- **No dual AAID/AAGUID**: Authenticators use either AAID (UAF) or AAGUID (FIDO2), never both
- **Batch attestation**: Attestation certificates shared across 100,000+ units for unlinkability
- **Forward compatibility**: Silently ignore unknown status values and fields
- **Monotonic versioning**: BLOB serial number must strictly increase — reject stale BLOBs
- **Integrity protection**: Rogue lists verified by hash; server data protected by HMAC
