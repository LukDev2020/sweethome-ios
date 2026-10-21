# App Privacy Labels — Luma (守灯) v1.0.0

Cross-reference: must match `ShouDeng/PrivacyInfo.xcprivacy` exactly.

## Data Linked to You

| Data Type | Purpose | Linked | Tracking | Manifest Key |
|-----------|---------|--------|----------|-------------|
| Precise Location | App Functionality | Yes | No | NSPrivacyCollectedDataTypePreciseLocation |
| Coarse Location | App Functionality | Yes | No | NSPrivacyCollectedDataTypeCoarseLocation |
| Phone Number | App Functionality | Yes | No | NSPrivacyCollectedDataTypePhoneNumber |
| Name | App Functionality | Yes | No | NSPrivacyCollectedDataTypeName |
| User ID | App Functionality | Yes | No | NSPrivacyCollectedDataTypeUserID |
| Device ID | App Functionality | Yes | No | NSPrivacyCollectedDataTypeDeviceID |
| Health | App Functionality | Yes | No | NSPrivacyCollectedDataTypeHealth |
| Contacts | App Functionality | Yes | No | NSPrivacyCollectedDataTypeContacts |
| Photos | App Functionality | Yes | No | NSPrivacyCollectedDataTypePhotosOrVideos |

## Data Not Linked to You

| Data Type | Purpose | Linked | Tracking | Manifest Key |
|-----------|---------|--------|----------|-------------|
| Crash Data | App Functionality | No | No | NSPrivacyCollectedDataTypeCrashData |

## Accessed API Types

| API Category | Reason Code | Usage |
|-------------|-------------|-------|
| User Defaults | CA92.1 | App preferences, widget data sharing, consent flags |
| File Timestamp | C617.1 | Consent log file management, cache cleanup |

## App Store Connect Answers

### Data Used to Track You
None. NSPrivacyTracking = false. No tracking domains.

### Data Linked to You
- **Location**: Precise location shared with user-chosen family members for emergency safety
- **Contact Info**: Phone number for authentication (OTP); name for display in family circle
- **Identifiers**: User ID (Firebase Auth), Device ID (push token for notifications)
- **Health & Fitness**: Medical card data (blood type, allergies, medications) — user-entered, shared only with linked guardians
- **Contacts**: Emergency contact info imported from device contacts
- **Photos**: Photos shared in family circle; claims evidence photos

### Data Not Linked to You
- **Diagnostics**: Crash reports via Firebase Crashlytics (no PII attached)

## Third-Party SDKs

| SDK | Data Accessed | Privacy Manifest |
|-----|--------------|-----------------|
| Firebase Auth | User ID, Phone Number | Included (firebase-ios-sdk) |
| Firebase Firestore | All app data | Included (firebase-ios-sdk) |
| Firebase Crashlytics | Crash data, device info | Included (firebase-ios-sdk) |
| Firebase Messaging | Device token | Included (firebase-ios-sdk) |
| GoogleUtilities | UserDefaults | Included |
| gRPC / Protobuf | Network data | Included |

All third-party SDKs ship their own PrivacyInfo.xcprivacy manifests.
