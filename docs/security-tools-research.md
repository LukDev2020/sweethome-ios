# ShouDeng Military-Grade Security Tools Research Report

**Date**: 2026-10-29
**Scope**: Encryption, anti-forensics, secure communications, threat detection, compliance, and safety-app ecosystem
**Context**: ShouDeng handles real-time location, SOS alerts, medical info, family relationships, duress codes, and disguise modes for domestic violence victims

---

## 1. Encryption Engines

### 1.1 Post-Quantum Cryptography

#### Apple CryptoKit PQC (iOS 26+) — RECOMMENDED, NATIVE
- **What**: Apple's native post-quantum crypto APIs introduced at WWDC 2025. Implements ML-KEM (CRYSTALS-Kyber, FIPS 203) for key encapsulation and ML-DSA (CRYSTALS-Dilithium, FIPS 204) for digital signatures.
- **iOS compatibility**: iOS 26+ (native). ML-DSA has Secure Enclave support on supported hardware.
- **License**: Proprietary (Apple framework)
- **ShouDeng integration**: Upgrade all key exchange to ML-KEM hybrid HPKE. Sign all SOS payloads with ML-DSA via Secure Enclave. This is the **primary path** — no third-party dependency needed.
- **Source**: [WWDC25 Session 314](https://developer.apple.com/videos/play/wwdc2025/314/), [Post-Quantum Readiness Guide](https://medium.com/@bhishakS/post-quantum-readiness-a-developers-guide-to-ios-26-and-beyond-6bf949e4f957)

#### liboqs (Open Quantum Safe)
- **GitHub**: [open-quantum-safe/liboqs](https://github.com/open-quantum-safe/liboqs) (~3k stars)
- **What**: C library for quantum-safe KEM and signature algorithms. Implements ML-KEM, ML-DSA, SPHINCS+, and more.
- **iOS compatibility**: Via C bridging. Community Swift wrapper exists: [OliverBajus/iOSPqcDemoApp](https://github.com/OliverBajus/iOSPqcDemoApp) — SwiftUI demo with benchmarks.
- **License**: MIT
- **ShouDeng integration**: Fallback option for pre-iOS 26 devices. Useful if you need algorithms beyond ML-KEM/ML-DSA.

#### Swift Crypto (Server-Side)
- **What**: Apple's server-side crypto library, API-compatible with CryptoKit. Supports all the same PQC APIs.
- **ShouDeng integration**: Use on Firebase Cloud Functions (if migrating to Swift backend) for PQC interoperability with iOS clients.
- **Source**: [CryptoKit Quantum Guide](https://www.atelier-socle.com/en/articles/cryptokit-quantum-secure-guide)

---

### 1.2 Signal Protocol (Double Ratchet E2EE)

#### libsignal (Official)
- **GitHub**: [signalapp/libsignal](https://github.com/signalapp/libsignal) (6,096 stars, AGPL-3.0)
- **What**: The gold standard for end-to-end encrypted messaging. Implements X3DH key agreement + Double Ratchet protocol. Written in Rust with official Swift bindings.
- **iOS compatibility**: Full iOS support via CocoaPods (`LibSignalClient` pod). Latest tag: v0.106.0 (2026-10-23). Requires `-lc++` for BoringSSL.
- **License**: AGPL-3.0 (important — viral license, requires open-sourcing derivative works OR purchasing a commercial license)
- **ShouDeng integration**: Encrypt all family chat messages, SOS alert content, and location shares with forward secrecy. Each message gets unique keys — compromising one message doesn't expose others. **Integration effort: 2-4 weeks.**
- **Source**: [Signal GitHub](https://github.com/signalapp), [Integration Guide](https://medium.com/@ahmedcs1995/signal-protocol-implementation-in-ios-end-end-encryption-edb02d11268d)

#### libsignal-protocol-swift (Community)
- **GitHub**: [christophhagen/libsignal-protocol-swift](https://github.com/christophhagen/libsignal-protocol-swift)
- **What**: Older community Swift wrapper for libsignal-protocol-c.
- **Note**: Less actively maintained than the official Rust-based libsignal. Use the official library instead.

---

### 1.3 NaCl / libsodium

#### swift-sodium (Official Wrapper) — RECOMMENDED
- **GitHub**: [jedisct1/swift-sodium](https://github.com/jedisct1/swift-sodium) (556 stars)
- **What**: Safe, easy-to-use crypto for iOS/macOS. Wraps libsodium with Swift-native API. Precompiled for arm64, armv7, iOS simulator, watchOS, Catalyst.
- **iOS compatibility**: Full. SPM and CocoaPods.
- **License**: ISC (permissive)
- **ShouDeng integration**: Use for authenticated encryption (XSalsa20-Poly1305), key derivation, secure random, password hashing (Argon2), and Ed25519 signatures. Lighter-weight than CryptoKit for specific operations.
- **Source**: [swift-sodium GitHub](https://github.com/jedisct1/swift-sodium)

#### swift-ncal
- **GitHub**: [Kingpin-Apps/swift-ncal](https://github.com/Kingpin-Apps/swift-ncal)
- **What**: Modern Swift interface to libsodium with XChacha20-Poly1305 AEAD.
- **iOS compatibility**: iOS 13.0+, SPM
- **License**: MIT

---

### 1.4 Hardware-Backed Encryption (Secure Enclave)

#### Apple CryptoKit SecureEnclave — ALREADY PARTIALLY USED
- **What**: Hardware-isolated P-256 key generation, signing, and ECDH. Keys never leave the enclave. iOS 26+ adds ML-DSA Secure Enclave support.
- **Constraints**: P-256 only (classical). Keys are device-bound (no backup/sync). Always check `SecureEnclave.isAvailable`.
- **ShouDeng integration**: Generate SE-backed keys for duress code verification, SOS signing, biometric-gated decryption of sensitive data. Use `SecureEnclave.P256.KeyAgreement` for deriving encryption keys tied to biometric auth.

#### EllipticCurveKeyPair
- **GitHub**: [agens-no/EllipticCurveKeyPair](https://github.com/agens-no/EllipticCurveKeyPair)
- **What**: Sign, verify, encrypt, decrypt using Secure Enclave. Exports public keys as X.509 DER. Updated April 2026.
- **License**: MIT
- **ShouDeng integration**: Wrapper to simplify SE key management. Handles FaceID/TouchID prompts, key export for server verification.

#### iOSSecurityTools
- **GitHub**: [muhittincamdali/iOSSecurityTools](https://github.com/muhittincamdali/iOSSecurityTools)
- **What**: Zero-dependency Swift toolkit: Keychain, AES-GCM, ChaCha20, Secure Enclave, biometrics, certificate pinning, TOTP, log redaction.
- **License**: MIT
- **ShouDeng integration**: All-in-one security toolkit. Particularly useful for TOTP-based duress code timing and log redaction for sensitive data.

---

## 2. Anti-Forensics / Data Protection

### 2.1 Jailbreak / Root Detection

#### IOSSecuritySuite — RECOMMENDED
- **GitHub**: [securing/IOSSecuritySuite](https://github.com/securing/IOSSecuritySuite)
- **What**: Pure Swift library detecting jailbreak, emulators, debuggers, runtime hooks, and proxies. Harder to bypass than Obj-C equivalents because Swift methods aren't exposed to the Obj-C runtime.
- **iOS compatibility**: Full, pure Swift
- **License**: MIT
- **ShouDeng integration**: Check on app launch and periodically. If jailbreak detected: warn user that device security is compromised, disable sensitive features (duress code, disguise mode), log the event.
- **Source**: [IOSSecuritySuite GitHub](https://github.com/securing/IOSSecuritySuite)

### 2.2 Anti-Tampering / Anti-Debugging / Obfuscation

#### iXGuard (Guardsquare) — COMMERCIAL, RECOMMENDED FOR PRODUCTION
- **URL**: [guardsquare.com/ixguard](https://www.guardsquare.com/ixguard)
- **What**: Enterprise-grade iOS app protection. Code obfuscation (control flow, name, string encryption, code virtualization), anti-debugging, anti-hooking (blocks Frida), jailbreak detection, repackaging detection, method swizzling detection. Polymorphic — no two builds look the same.
- **iOS compatibility**: Swift, Obj-C, Flutter, React Native. Post-compilation — no source code changes needed.
- **License**: Commercial (contact for pricing)
- **ShouDeng integration**: Apply to release builds via Xcode build phase. Critical for protecting duress code logic, disguise mode switching, and encryption key handling from reverse engineering.
- **Source**: [Guardsquare Review 2026](https://appsecsanta.com/guardsquare)

### 2.3 Anti-Screenshot / Screen Recording

#### UIKit Secure Text Field Technique
- **What**: Setting `isSecureTextEntry = true` on a UITextField causes iOS to exclude the view from screenshots and screen recordings. Wrapping sensitive SwiftUI views in a UIKit host with this property provides screenshot protection.
- **Additional approaches**:
  - Blur overlay on `UIApplication.willResignActiveNotification`
  - Detect screenshots via `UIApplication.userDidTakeScreenshotNotification` — log, alert, or wipe displayed data
- **ShouDeng integration**: Apply to all sensitive screens: SOS status, location map, family member details, duress code settings, medical info. Critical for domestic violence scenarios where an abuser might screenshot the app.
- **Source**: [Screenshot Prevention Techniques](https://medium.com/@thakurneeshu280/screenshot-prevention-in-ios-advanced-techniques-inspired-by-banking-authenticator-apps-0d1900c2a1bb)

### 2.4 Secure Memory

#### Apple Memory Integrity Enforcement (MIE) — Hardware (A19+ / iPhone 17+)
- **What**: Hardware-level memory tagging (Enhanced Memory Tagging Extension) built into A19/A19 Pro chips. Stops buffer overflows and use-after-free vulnerabilities at the silicon level. Cannot be disabled or bypassed.
- **ShouDeng integration**: Automatically protects app memory on supported devices. For older devices, use `memset_s()` or `SecureBytes` patterns to zero sensitive data (passwords, keys, PINs) after use.

#### Manual Secure Memory Patterns
- Use `memset_s()` (guaranteed not to be optimized away) to zero sensitive buffers
- Use `Data` with `withUnsafeMutableBytes` for controlled lifetime
- Avoid storing sensitive strings as Swift `String` (interned, may persist in memory)
- Use `UnsafeMutableRawBufferPointer` + manual zeroing for duress codes and PINs

### 2.5 Plausible Deniability / Disguise Mode

#### Design Patterns (Not a Single Library)
- **Cryptee Ghost Folders**: Hide folders for domestic abuse survivors. Deniable encryption design. [cryptee.com](https://crypt.ee)
- **Vaultaire Pattern-Separated Vaults**: Different unlock patterns open different vaults. No vault registry visible. [vaultaire.app](https://vaultaire.app)
- **Key design principles for ShouDeng**:
  1. **Duress PIN** → opens a benign "decoy" interface (calculator, weather app, notes)
  2. **Real PIN** → opens full ShouDeng with all safety features
  3. **No forensic artifacts** should reveal the existence of the safety mode
  4. **App icon switching** — present as a utility app (already in ShouDeng's disguise mode concept)
  5. Store encrypted safety data in a generic container indistinguishable from app cache
- **Caveat**: True cryptographic deniability is extremely difficult on iOS. Cosmetic decoy modes work against casual snoops but may fail forensic examination. Design for the realistic threat model: an abusive partner, not a state forensic lab.
- **Source**: [Plausible Deniability in Apps](https://vaultaire.app/guides/plausible-deniability-apps/), [Decoy Vault Guide](https://altersend.com/vault/guides/decoy-vault)

---

## 3. Secure Communication Channels

### 3.1 Certificate Pinning

#### TrustKit — RECOMMENDED
- **GitHub**: [datatheorem/TrustKit](https://github.com/datatheorem/TrustKit) (2,143 stars)
- **What**: Dedicated SSL public key pinning and reporting framework. Configurable via Info.plist or programmatically. Latest: v3.0.7 (August 2026).
- **iOS compatibility**: iOS 12+, SPM and CocoaPods
- **License**: MIT
- **ShouDeng integration**: Pin Firebase API endpoints and backend server certificates. Configure backup pins and violation reporting. Prevents MITM interception of SOS alerts and location data.
- **Source**: [TrustKit on Swift Package Index](https://swiftpackageindex.com/datatheorem/TrustKit)

### 3.2 Onion Routing / Tor

#### swift-tor — RECOMMENDED FOR iOS 18+
- **GitHub**: [21-DOT-DEV/swift-tor](https://github.com/21-DOT-DEV/swift-tor)
- **What**: Swift-concurrency-first Tor wrapper. Embeds Tor in-process via libtor. Provides `TorClient` actor API, SOCKS5 proxy, ephemeral v3 onion services, and `URLSessionConfiguration` helpers.
- **iOS compatibility**: iOS 18+, macOS 15+. Requires Swift 6.1+.
- **License**: MIT
- **ShouDeng integration**: Route SOS alerts through Tor when user is in high-risk mode. Create ephemeral onion services for anonymous location sharing. Prevents network-level surveillance of safety communications.

#### Tor.framework (iCepa) — RECOMMENDED FOR BROADER COMPATIBILITY
- **GitHub**: [iCepa/Tor.framework](https://github.com/nicklama/Tor.framework)
- **What**: Established iOS/macOS Tor embedding framework. Includes both C-based Tor and Rust-based Arti. Supports Onionmasq for VPN-style apps.
- **iOS compatibility**: iOS 15+, macOS 11+
- **License**: MIT
- **ShouDeng integration**: Broader device support than swift-tor. Use Arti (modern Rust implementation) for better performance. Onionmasq variant useful if building a VPN-style privacy layer.

#### Orbot (Guardian Project)
- **What**: Free Tor proxy app for iOS/Android by Guardian Project.
- **ShouDeng integration**: Recommend to high-risk users as a system-wide Tor proxy. ShouDeng can detect if Orbot is running and route traffic through it.

### 3.3 Mesh Networking (Offline SOS)

#### Bridgefy SDK — RECOMMENDED
- **GitHub**: [bridgefy/sdk-ios](https://github.com/bridgefy/sdk-ios)
- **What**: BLE mesh networking SDK. Devices relay messages across multiple hops (100m per hop). Cross-platform (iOS + Android). 12.3M downloads.
- **iOS compatibility**: Full iOS SDK
- **License**: Commercial (free tier available)
- **ShouDeng integration**: Enable offline SOS relay when no internet/cellular available. Critical for domestic violence victims whose abuser controls the WiFi router. Broadcast SOS to nearby ShouDeng users who can relay to emergency services.
- **Source**: [Bridgefy iOS SDK Guide](https://www.blog.brightcoding.dev/2026/05/25/bridgefy-ios-sdk-revolutionize-offline-messaging-with-bluetooth-mesh)

#### Apple MultipeerConnectivity (Native)
- **What**: Apple's built-in framework for peer-to-peer communication via Bluetooth and WiFi Direct.
- **iOS compatibility**: Native, no dependencies
- **License**: Apple framework
- **ShouDeng integration**: Use as a fallback for Bridgefy. Limitation: iOS-to-iOS only (no Android interop). Suitable for nearby family member alerts.

### 3.4 Steganography

#### Pictograph — RECOMMENDED
- **GitHub**: [MrAdamBoyd/Pictograph](https://github.com/MrAdamBoyd/Pictograph)
- **What**: iOS/macOS steganography app. Hides messages and images in photos using LSB encoding. AES-256 encryption when enabled.
- **iOS compatibility**: Full, Swift, on App Store
- **License**: MIT
- **ShouDeng integration**: Allow victims to hide SOS messages inside innocent-looking photos that can be shared via any messaging app without detection. Abuser sees a normal photo; recipient extracts the hidden distress signal.

#### ISStego
- **GitHub**: [isena/ISStego](https://github.com/isena/ISStego)
- **What**: Obj-C steganography library. LSB + Sequential Color Cycle + Uniform Distribution. Well-documented API.
- **iOS compatibility**: iOS & macOS, bridgeable to Swift
- **License**: MIT
- **ShouDeng integration**: Library form factor better suited for embedding than Pictograph (which is an app).

---

## 4. Threat Detection

### 4.1 Stalkerware / Spyware Detection

#### MVT (Mobile Verification Toolkit) — Amnesty International
- **GitHub**: [mvt-project/mvt](https://github.com/mvt-project/mvt) (15,613 stars)
- **What**: Forensic toolkit for detecting Pegasus, Predator, RCS Lab, and 10+ commercial spyware families. Analyzes iOS backups against known IOCs (Indicators of Compromise).
- **iOS compatibility**: Runs on Mac/Linux, analyzes iOS device backups
- **License**: MVT License (restricted use — only for consensual forensic analysis)
- **ShouDeng integration**: Cannot be embedded directly. But ShouDeng can: (1) guide users through running MVT, (2) integrate MVT's published IOC databases (STIX format) for on-device lightweight checks, (3) check for suspicious MDM profiles, unknown VPN configurations, and certificate trust store anomalies.
- **Source**: [MVT Documentation](https://docs.mvt.re), [MVT GitHub](https://github.com/mvt-project/mvt)

#### On-Device Stalkerware Indicators (Custom Implementation)
ShouDeng can check for these indicators without external libraries:
- Unexpected MDM enrollment profiles (`Settings > General > VPN & Device Management`)
- Unknown VPN configurations in `NEVPNManager`
- Excessive location access by other apps (Settings audit prompt)
- Battery drain anomalies (could indicate background surveillance)
- Unknown certificate authorities in trust store
- Screen recording indicators (status bar orange/green dot monitoring)

### 4.2 MITM / Network Compromise Detection

#### Detection Techniques (Built-In)
- **Certificate chain inspection**: In `URLSessionDelegate.urlSession(_:didReceive:)`, validate the full certificate chain. Reject connections with unexpected intermediate CAs.
- **Proxy detection**: Check `CFNetworkCopySystemProxySettings()` for configured proxies. Alert user if HTTP/SOCKS proxy is detected during sensitive operations.
- **TLS fingerprinting**: Compare server TLS parameters against expected values.
- **DNS anomaly detection**: Resolve critical domains through multiple DNS providers and compare results.

#### swift-mitm (Research Tool)
- **GitHub**: [ul0gic/swift-mitm](https://github.com/ul0gic/swift-mitm)
- **What**: Embeddable Swift TLS interception proxy engine. Useful for understanding MITM mechanics.
- **Note**: This is an offensive tool, not defensive. Study its techniques to build detection.

---

## 5. Compliance Frameworks

### 5.1 FIPS 140-3

#### Apple Corecrypto — VALIDATED
- **Status**: iOS 18 corecrypto modules received FIPS 140-3 validation (Certificate #5184, validated 2026-03-11). iOS 26 modules are in "Review" status.
- **Secure Enclave**: SEP module validated at Level 2 with Physical Security Level 3 (Certificate #5305/#5306).
- **ShouDeng integration**: By using CryptoKit (which calls corecrypto), ShouDeng automatically benefits from FIPS 140-3 validated cryptography. No additional work needed. Document this in your compliance materials.
- **Source**: [Apple iOS Security Certifications](https://support.apple.com/guide/certifications/ios-security-certifications-apc3fa917cb49/web), [NIST CMVP](https://csrc.nist.gov/projects/cryptographic-module-validation-program)

#### SafeLogic CryptoComply (Alternative)
- **URL**: [safelogic.com](https://www.safelogic.com/blog/cryptocomply-openssl-3-fips-140-provider-for-ios-goes-ga)
- **What**: FIPS 140 validated OpenSSL 3 provider for iOS. For apps that need their own validated module independent of Apple's.
- **License**: Commercial

### 5.2 SOC 2 / ISO 27001 Audit Automation

#### Vanta — MARKET LEADER
- **URL**: [vanta.com](https://www.vanta.com/products/soc-2)
- **What**: Continuous compliance monitoring for SOC 2, ISO 27001, HIPAA, GDPR. 375+ integrations. AI-powered evidence collection. 15,000+ customers.
- **Pricing**: ~$10K-$80K/year
- **ShouDeng integration**: Automate evidence collection from Firebase, GitHub, AWS. Generate SOC 2 Type II audit trail. Critical for enterprise/government customers.

#### Drata
- **URL**: [drata.com](https://drata.com)
- **What**: Compliance automation with strong continuous monitoring. AI-powered TPRM. 200+ integrations.
- **Pricing**: ~$7.5K-$100K/year
- **ShouDeng integration**: Alternative to Vanta. Stronger multi-framework mapping if pursuing SOC 2 + ISO 27001 simultaneously.

### 5.3 NATO Restricted Clearance
- **Note**: iOS 26 devices are formally approved to process and store information classified up to NATO Restricted level, due to hardware-enforced trust (MIE + post-quantum encryption).
- **Source**: [Elcomsoft Blog on iOS 26 Security](https://blog.elcomsoft.com/2026/04/new-and-updated-security-features-in-ios-26-and-their-forensic-implications/)

---

## 6. Open-Source Safety App Ecosystem

### 6.1 Guardian Project Tools

#### Orbot (Tor Proxy)
- **What**: Free Tor proxy for iOS/Android. Routes all device traffic through Tor.
- **iOS**: Available on App Store
- **ShouDeng integration**: Recommend to high-risk users. Detect Orbot presence and leverage it.

#### ObscuraCam
- **What**: Android app for face anonymization in photos/videos. Auto-detects and blurs faces.
- **iOS**: No iOS version
- **ShouDeng integration**: Implement similar face-blurring using Vision framework for photos shared through ShouDeng.

### 6.2 Tella (Secure Documentation)
- **What**: Mobile app for human rights defenders. Encrypts and hides sensitive documentation. Offline-capable. Integrates with Uwazi for case building.
- **iOS**: Available on App Store
- **License**: Open source
- **ShouDeng integration**: Study Tella's encrypted camera roll design. Implement similar evidence-collection features for domestic violence documentation (timestamped photos, audio recordings, location logs) stored in encrypted containers.
- **Source**: [Tella + Uwazi Integration (2026)](https://huridocs.org/2026/01/the-new-tella-app-lets-uwazi-users-document-violations-safely-and-while-offline/)

### 6.3 Haven (Physical Security Monitoring)
- **GitHub**: [guardianproject/haven](https://github.com/guardianproject/haven)
- **What**: Uses device sensors (camera, microphone, accelerometer, light sensor) to detect physical intrusions. Co-developed with Edward Snowden / Freedom of the Press Foundation.
- **iOS**: Android only
- **License**: GPL-3.0
- **ShouDeng integration**: Port Haven's sensor monitoring concept to iOS. Use accelerometer + microphone to detect if someone picks up or moves a victim's phone. Alert the user or guardian circle.

### 6.4 Briar (P2P Messaging)
- **Status**: Entered maintenance mode July 2026. **No iOS version and none planned** (Apple's background process restrictions prevent P2P networking). Nearly shut down in 2025 due to lack of funding.
- **ShouDeng integration**: Not directly usable. But study Briar's Tor-based sync protocol for inspiration on censorship-resistant message delivery.
- **Source**: [Briar Maintenance Mode Announcement](https://alternativeto.net/news/2026/7/secure-messaging-app-briar-enters-maintenance-mode-will-only-receive-bug-and-security-fixes/)

### 6.5 Panic Button / Safety Apps (Competitive Landscape)

| App | Key Features | Open Source | iOS |
|-----|-------------|-------------|-----|
| **bSafe** | SOS button, live recording, guardian alerts, voice activation | No | Yes |
| **Circle of 6** | 6 trusted contacts, one-tap alerts, GPS sharing | No | Yes |
| **Noonlight** | Hold-to-be-safe button, auto-dispatch emergency | No | Yes |
| **Red Panic Button** | SMS/email SOS with GPS coordinates | No | Yes |
| **React Mobile** | BLE panic button hardware + app | No | Yes |
| **Life360** | Family tracking, crash detection, crime alerts | No | Yes |

**ShouDeng differentiators** vs. these apps:
1. Duress code / disguise mode (none of the above have this)
2. Post-quantum encryption (none)
3. BLE tracker integration (only React Mobile has BLE)
4. Multi-role architecture (protected + guardian)
5. Evidence documentation (only Tella does this, but it's not a safety app)
6. Offline mesh SOS relay (none)

---

## 7. Priority Integration Roadmap

### Tier 1 — Critical (Weeks 1-4)
| Tool | Purpose | Effort |
|------|---------|--------|
| **CryptoKit PQC (ML-KEM + ML-DSA)** | Post-quantum encryption for all data at rest and in transit | 1 week |
| **IOSSecuritySuite** | Jailbreak/debug/hook detection | 2 days |
| **TrustKit** | Certificate pinning for API endpoints | 2 days |
| **Secure Enclave key management** | Hardware-backed keys for duress code, SOS signing | 1 week |
| **Anti-screenshot protection** | Protect sensitive screens from capture | 3 days |

### Tier 2 — High Priority (Weeks 5-8)
| Tool | Purpose | Effort |
|------|---------|--------|
| **libsignal** | E2EE for all family messaging with forward secrecy | 2-4 weeks |
| **Bridgefy SDK** | Offline mesh SOS for no-connectivity scenarios | 1 week |
| **Stalkerware detection** | MDM/VPN/proxy anomaly checks | 1 week |
| **MITM detection** | Certificate chain + proxy detection | 3 days |

### Tier 3 — Enhanced Security (Weeks 9-12)
| Tool | Purpose | Effort |
|------|---------|--------|
| **swift-tor / Tor.framework** | Anonymous SOS routing for high-risk users | 2 weeks |
| **Steganography (ISStego)** | Hidden distress signals in photos | 1 week |
| **iXGuard** | Production-grade anti-tampering/obfuscation | 1 week (setup) |
| **Plausible deniability redesign** | Forensics-resistant disguise mode | 2 weeks |

### Tier 4 — Compliance & Certification (Ongoing)
| Tool | Purpose | Effort |
|------|---------|--------|
| **Vanta or Drata** | SOC 2 + ISO 27001 audit automation | Ongoing |
| **FIPS 140-3 documentation** | Document use of validated Apple corecrypto | 2 days |
| **MVT IOC integration** | Lightweight spyware indicator checks | 1 week |

---

## 8. License Summary

| Tool | License | Commercial Use OK | Viral? |
|------|---------|-------------------|--------|
| CryptoKit PQC | Apple proprietary | Yes (Apple ecosystem) | No |
| liboqs | MIT | Yes | No |
| libsignal | **AGPL-3.0** | **Requires open-sourcing or commercial license** | **Yes** |
| swift-sodium | ISC | Yes | No |
| IOSSecuritySuite | MIT | Yes | No |
| TrustKit | MIT | Yes | No |
| swift-tor | MIT | Yes | No |
| Tor.framework | MIT | Yes | No |
| Bridgefy SDK | Commercial | Requires license | N/A |
| Pictograph | MIT | Yes | No |
| ISStego | MIT | Yes | No |
| iXGuard | Commercial | Requires license | N/A |
| MVT | Restricted | **Consensual forensics only** | Special |
| Haven | GPL-3.0 | Yes (if you open-source) | Yes |
| EllipticCurveKeyPair | MIT | Yes | No |
| iOSSecurityTools | MIT | Yes | No |

**License risk**: libsignal's AGPL-3.0 is the biggest concern. Options: (1) open-source ShouDeng's messaging module, (2) negotiate a commercial license with Signal Foundation, or (3) implement Double Ratchet independently using CryptoKit primitives.

---

## 9. Key Architectural Recommendations

1. **Defense in depth**: Layer CryptoKit PQC (transport) + libsignal (message-level E2EE) + Secure Enclave (key storage) + iXGuard (binary protection)

2. **Threat-model-aware design**: The primary threat for DV victims is a coercive partner with physical access, not a nation-state. Prioritize disguise mode, anti-screenshot, and duress codes over Tor routing.

3. **Degrade gracefully**: Not all users will have iOS 26+. Use liboqs or standard AES-GCM as fallback. Mesh networking (Bridgefy) should supplement, not replace, cellular SOS.

4. **Compliance as a feature**: FIPS 140-3 validation (via Apple corecrypto) and SOC 2 certification are selling points for institutional partnerships (shelters, law enforcement, government programs).

5. **Open-source strategically**: Consider open-sourcing the encryption and safety protocol layers (builds trust with DV organizations) while keeping the UI and business logic proprietary.

---

*Report compiled 2026-10-29. All GitHub star counts and version numbers current as of this date.*
