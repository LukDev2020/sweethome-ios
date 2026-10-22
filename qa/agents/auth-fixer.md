# Agent: Auth Fixer — Login Issues + Google Auth Integration

## Purpose
Fix existing login issues and add Google Sign-In as a secondary auth provider.
Core rule: **Google users MUST still bind a valid phone number before signup completes.**
After binding, users can log in with either Google or phone number interchangeably.

---

## Part 1: Current Login Issues to Fix

### Issue L-001: Title Shows "ShouDeng" on Onboarding, "Vela" on Login
- Onboarding screen 1 says "ShouDeng Is Not an Emerg..." (truncated)
- Login screen says "Vela" / "守灯"
- **Fix**: Unify to "Vela" everywhere. Update DisclaimerCopy.swift onboarding titles.

### Issue L-002: Notification Permission Dialog Covers Onboarding
- Screenshot shows notification prompt overlapping disclaimer text (step1_current.png)
- **Fix**: Defer notification permission request until AFTER onboarding completes (after role selection).

### Issue L-003: Location Permission Fires Too Early
- Screenshot shows location dialog on login screen (step5_fresh_install.png)
- **Fix**: Request location only after user selects "Protected Person" role and grants location consent in feature disclosure.

### Issue L-004: 404 Redirect Lacks User Feedback
- When login returns 404 (user not found), silently redirects to signup
- User doesn't understand what happened
- **Fix**: Show brief toast "Account not found, let's create one" before redirect.

### Issue L-005: Lockout Timer in UserDefaults Only
- 5-attempt lockout stored locally — user can reinstall app to bypass
- **Fix for MVP**: Acceptable. Add server-side rate limiting as P2 follow-up.

---

## Part 2: Google Auth Integration — Complete Logic Design

### 2.1 User Flow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    LOGIN SCREEN                          │
│                                                          │
│    ┌──────────────────────────────────┐                  │
│    │  🇨🇦 +1  │ Phone number          │                  │
│    └──────────────────────────────────┘                  │
│    ┌──────────────────────────────────┐                  │
│    │          Get Code                │                  │
│    └──────────────────────────────────┘                  │
│                                                          │
│    ──────────── or ────────────                          │
│                                                          │
│    ┌──────────────────────────────────┐                  │
│    │  G  Continue with Google         │                  │
│    └──────────────────────────────────┘                  │
│                                                          │
│    Don't have an account? Sign Up                        │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Login with Google — Existing User (has phone bound)

```
User taps "Continue with Google"
         ↓
GoogleSignIn SDK → Google OAuth consent screen
         ↓
Google returns googleIdToken + email + name
         ↓
POST /v1/auth/google-login { googleIdToken }
         ↓
Backend verifies googleIdToken with Google
         ↓
Look up users collection: googleEmail == email
         ↓
  ┌── Found (has phone bound) ──→ Generate JWT → Return tokens → LOGIN SUCCESS
  │
  └── Not found ──→ Return 404 { error: "user_not_found", googleEmail, googleName }
                            ↓
                    Redirect to SIGNUP (pre-fill name)
```

### 2.3 Signup with Google — New User (must bind phone)

```
┌─────────────────────────────────────────────────────────┐
│                   SIGNUP SCREEN                          │
│                                                          │
│  Step 1: Google info confirmed                           │
│    ┌──────────────────────────────────┐                  │
│    │  ✓ Google: chenhao@gmail.com     │  (read-only)     │
│    │    Chen Hao                      │                  │
│    └──────────────────────────────────┘                  │
│                                                          │
│  Step 2: Bind phone number (REQUIRED)                    │
│    ┌──────────────────────────────────┐                  │
│    │  🇨🇦 +1  │ Phone number          │                  │
│    └──────────────────────────────────┘                  │
│    ┌──────────────────────────────────┐                  │
│    │          Send Code               │                  │
│    └──────────────────────────────────┘                  │
│    ┌──────────────────────────────────┐                  │
│    │          Verification code       │                  │
│    └──────────────────────────────────┘                  │
│                                                          │
│  Step 3: Role selection                                  │
│    ┌──────────────────────────────────┐                  │
│    │  ○ Protected   ○ Guardian        │                  │
│    └──────────────────────────────────┘                  │
│                                                          │
│  Step 4: Display name (pre-filled from Google)           │
│    ┌──────────────────────────────────┐                  │
│    │  Chen Hao                        │  (editable)      │
│    └──────────────────────────────────┘                  │
│    ┌──────────────────────────────────┐                  │
│    │          Complete                │                  │
│    └──────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────┘
```

```
POST /v1/auth/google-signup {
    googleIdToken,
    phoneIdToken,       // Firebase phone verification token
    displayName,
    role,
    countryCode
}
         ↓
Backend:
  1. Verify googleIdToken → extract email, name
  2. Verify phoneIdToken → extract phone number
  3. Check no existing user with same email OR phone
  4. Create user doc with BOTH auth methods:
     {
       userId: auto-generated,
       displayName,
       role,
       phone,
       googleEmail,
       googleSub,        // Google unique ID
       authProviders: ["phone", "google"],
       countryCode,
       timeZone,
       createdAt
     }
  5. Generate JWT tokens
  6. Return AuthResponse
```

### 2.4 Login with Phone — Existing User (also has Google bound)

```
Works exactly as today — NO changes needed.
Phone login path is completely unchanged.
User who signed up with Google+Phone can login with just phone.
```

### 2.5 Login Flow Decision Tree

```
           ┌── Phone path ──→ Firebase OTP ──→ POST /v1/auth/login { idToken }
           │                                         ↓
           │                              ┌── 200: user found ──→ JWT tokens ──→ LOGGED IN
           │                              └── 404: not found ──→ redirect signup
User ──────┤
           │
           └── Google path ──→ GoogleSignIn SDK ──→ POST /v1/auth/google-login { googleIdToken }
                                                         ↓
                                              ┌── 200: user found + phone bound ──→ JWT tokens ──→ LOGGED IN
                                              ├── 200: user found + NO phone ──→ IMPOSSIBLE (signup requires phone)
                                              └── 404: not found ──→ redirect google-signup (with phone binding)
```

---

## Part 3: Data Model Changes

### 3.1 Firestore `users` Collection — New Fields

```typescript
// Existing fields (unchanged)
{
  userId: string,
  displayName: string,
  role: "protected" | "guardian",
  phone: string,              // E.164, e.g. "+14165550137"
  countryCode: string,        // "CA"
  timeZone: string,           // "America/Toronto"
  avatarInitial: string,
  createdAt: Timestamp,
  // ...other existing fields
}

// NEW fields for Google Auth
{
  googleEmail: string | null,    // "chenhao@gmail.com"
  googleSub: string | null,      // Google unique user ID (never changes)
  authProviders: string[],       // ["phone"] or ["phone", "google"]
}
```

### 3.2 New Firestore Index

```
Collection: users
Fields: googleEmail (ASC)
Purpose: Look up user by Google email on google-login
```

### 3.3 Migration

Existing users get:
```
googleEmail: null
googleSub: null
authProviders: ["phone"]
```

No migration script needed — null fields are handled as "not set" in code.

---

## Part 4: Backend API Changes

### 4.1 New Endpoint: POST /v1/auth/google-login

```typescript
router.post("/google-login", createRateLimiter(RATE_LIMITS.auth), async (req, res) => {
  const { googleIdToken } = req.body;

  if (!googleIdToken) {
    return res.status(400).json({ error: "googleIdToken is required" });
  }

  // 1. Verify Google ID token
  const googlePayload = await verifyGoogleToken(googleIdToken);
  if (!googlePayload) {
    return res.status(401).json({ error: "Invalid Google token" });
  }

  const { email, sub: googleSub, name } = googlePayload;

  // 2. Look up user by googleEmail or googleSub
  const userSnapshot = await db.collection("users")
    .where("googleEmail", "==", email)
    .limit(1).get();

  if (userSnapshot.empty) {
    return res.status(404).json({
      error: "user_not_found",
      googleEmail: email,
      googleName: name,
    });
  }

  const userDoc = userSnapshot.docs[0];
  const userData = userDoc.data();

  // 3. Verify phone is bound (safety check — should always be true)
  if (!userData.phone) {
    return res.status(403).json({ error: "Phone number not bound. Complete signup first." });
  }

  // 4. Generate JWT tokens
  const tokens = generateTokens(userDoc.id);
  res.json({
    ...tokens,
    userId: userDoc.id,
    displayName: userData.displayName,
    role: userData.role,
  });
});
```

### 4.2 New Endpoint: POST /v1/auth/google-signup

```typescript
router.post("/google-signup", createRateLimiter(RATE_LIMITS.auth), async (req, res) => {
  const { googleIdToken, phoneIdToken, displayName, role, countryCode } = req.body;

  if (!googleIdToken || !phoneIdToken || !displayName || !role) {
    return res.status(400).json({ error: "Missing required fields" });
  }

  // 1. Verify Google token
  const googlePayload = await verifyGoogleToken(googleIdToken);
  if (!googlePayload) {
    return res.status(401).json({ error: "Invalid Google token" });
  }

  // 2. Verify phone token (Firebase phone auth)
  const phonePayload = await decodeIdToken(phoneIdToken);
  if (!phonePayload || !phonePayload.phone) {
    return res.status(401).json({ error: "Invalid phone verification" });
  }

  const { email: googleEmail, sub: googleSub, name: googleName } = googlePayload;
  const { phone } = phonePayload;

  // 3. Check no duplicate email
  const emailCheck = await db.collection("users")
    .where("googleEmail", "==", googleEmail)
    .limit(1).get();
  if (!emailCheck.empty) {
    return res.status(409).json({ error: "Google account already registered" });
  }

  // 4. Check no duplicate phone
  const phoneCheck = await db.collection("users")
    .where("phone", "==", phone)
    .limit(1).get();
  if (!phoneCheck.empty) {
    return res.status(409).json({ error: "Phone number already registered" });
  }

  // 5. Create user
  const country = countryCode || countryFromPhone(phone);
  const timeZone = timezoneFromCountry(country);
  const userId = db.collection("users").doc().id;

  await db.collection("users").doc(userId).set({
    displayName: displayName.trim(),
    role,
    phone,
    googleEmail,
    googleSub,
    authProviders: ["phone", "google"],
    countryCode: country,
    timeZone,
    avatarInitial: displayName.trim().charAt(0),
    createdAt: admin.firestore.Timestamp.now(),
  });

  // 6. Generate tokens
  const tokens = generateTokens(userId);
  res.status(201).json({
    ...tokens,
    userId,
    displayName: displayName.trim(),
    role,
  });
});
```

### 4.3 New Helper: verifyGoogleToken()

```typescript
import { OAuth2Client } from "google-auth-library";

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const googleClient = new OAuth2Client(GOOGLE_CLIENT_ID);

async function verifyGoogleToken(idToken: string): Promise<{
  email: string;
  sub: string;
  name: string;
  picture?: string;
} | null> {
  try {
    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    if (!payload || !payload.email || !payload.sub) return null;
    return {
      email: payload.email,
      sub: payload.sub,
      name: payload.name || "",
      picture: payload.picture,
    };
  } catch (error) {
    console.error("[Auth] Google token verification failed:", error);
    return null;
  }
}
```

### 4.4 Existing Endpoint Change: POST /v1/auth/login

Add Google email lookup as fallback:

```typescript
// After Firebase phone lookup fails with 404:
// Also check if this phone belongs to a Google-linked user
const phoneUser = await db.collection("users")
  .where("phone", "==", decodedToken.phone)
  .limit(1).get();
// This already works — no change needed.
// Phone login path remains unchanged.
```

### 4.5 New Endpoint: POST /v1/auth/bind-google (for existing phone-only users)

```typescript
router.post("/bind-google", authMiddleware, async (req, res) => {
  const uid = req.uid!;
  const { googleIdToken } = req.body;

  // 1. Verify Google token
  const googlePayload = await verifyGoogleToken(googleIdToken);
  if (!googlePayload) {
    return res.status(401).json({ error: "Invalid Google token" });
  }

  // 2. Check Google email not already bound to another user
  const existing = await db.collection("users")
    .where("googleEmail", "==", googlePayload.email)
    .limit(1).get();
  if (!existing.empty && existing.docs[0].id !== uid) {
    return res.status(409).json({ error: "Google account bound to another user" });
  }

  // 3. Bind Google to current user
  await db.collection("users").doc(uid).update({
    googleEmail: googlePayload.email,
    googleSub: googlePayload.sub,
    authProviders: admin.firestore.FieldValue.arrayUnion("google"),
  });

  res.json({ success: true, googleEmail: googlePayload.email });
});
```

---

## Part 5: iOS Changes

### 5.1 Dependencies

```
// Add to Package.swift or Podfile:
GoogleSignIn (latest)        // Google Sign-In SDK
// Firebase already included — no change
```

### 5.2 AuthManager.swift — New Methods

```swift
// MARK: - Google Auth

func signInWithGoogle(presenting: UIViewController) async throws {
    let result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: presenting
    )
    guard let idToken = result.user.idToken?.tokenString else {
        throw AuthError.googleSignInFailed
    }

    self.googleIdToken = idToken
    self.googleEmail = result.user.profile?.email
    self.googleName = result.user.profile?.name

    // Try login first
    do {
        let response = try await api.post(
            "/v1/auth/google-login",
            body: ["googleIdToken": idToken]
        )
        handleAuthResponse(response)
    } catch APIError.notFound {
        // User not found — need signup with phone binding
        throw AuthError.googleUserNotFound(
            email: self.googleEmail ?? "",
            name: self.googleName ?? ""
        )
    }
}

func googleSignup(
    phoneCode: String,
    displayName: String,
    role: String,
    countryCode: String
) async throws {
    guard let googleIdToken = self.googleIdToken else {
        throw AuthError.noGoogleToken
    }

    // Step 1: Verify phone via Firebase OTP (same as existing)
    guard let verificationID = self.verificationID else {
        throw AuthError.noVerificationID
    }
    let credential = PhoneAuthProvider.provider()
        .credential(withVerificationID: verificationID, verificationCode: phoneCode)
    let authResult = try await Auth.auth().signIn(with: credential)
    let phoneIdToken = try await authResult.user.getIDToken()

    // Step 2: Call google-signup with both tokens
    let response = try await api.post(
        "/v1/auth/google-signup",
        body: [
            "googleIdToken": googleIdToken,
            "phoneIdToken": phoneIdToken,
            "displayName": displayName,
            "role": role,
            "countryCode": countryCode,
        ]
    )
    handleAuthResponse(response)
}

func bindGoogle(presenting: UIViewController) async throws {
    let result = try await GIDSignIn.sharedInstance.signIn(
        withPresenting: presenting
    )
    guard let idToken = result.user.idToken?.tokenString else {
        throw AuthError.googleSignInFailed
    }

    try await api.post(
        "/v1/auth/bind-google",
        body: ["googleIdToken": idToken]
    )
}
```

### 5.3 AuthError — New Cases

```swift
enum AuthError: LocalizedError {
    // ... existing cases ...
    case googleSignInFailed
    case googleUserNotFound(email: String, name: String)
    case noGoogleToken
    case googleAlreadyBound
}
```

### 5.4 LoginView.swift — Add Google Button

```swift
// After "Get Code" button, add:
Divider()
    .overlay(Text("or").foregroundColor(.secondary))

Button(action: { signInWithGoogle() }) {
    HStack {
        Image("google-logo")  // Add asset
            .resizable()
            .frame(width: 20, height: 20)
        Text("Continue with Google")
    }
}
.buttonStyle(.bordered)
.tint(.primary)
```

### 5.5 GoogleSignupView.swift — New View

```swift
struct GoogleSignupView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let googleEmail: String
    let googleName: String

    @State private var step = 1  // 1=phone, 2=OTP, 3=role+name
    @State private var phone = ""
    @State private var code = ""
    @State private var displayName: String
    @State private var selectedRole = ""
    @State private var countryCode: CountryCode = .default

    init(email: String, name: String) {
        self.googleEmail = email
        self.googleName = name
        self._displayName = State(initialValue: name)
    }

    var body: some View {
        VStack {
            // Google info banner (always visible)
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading) {
                    Text(googleEmail).font(.caption)
                    Text(googleName).font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            // Step 1: Phone entry
            // Step 2: OTP verification
            // Step 3: Role + Display name
            // (reuse existing SignupView step logic)
        }
    }
}
```

### 5.6 Settings — Bind/Unbind Google

```swift
// In SettingsView, add section:
Section("Login Methods") {
    if user.authProviders.contains("phone") {
        HStack {
            Image(systemName: "phone.fill")
            Text(user.phone ?? "")
            Spacer()
            Text("Bound").foregroundColor(.green)
        }
    }

    if user.authProviders.contains("google") {
        HStack {
            Image("google-logo")
            Text(user.googleEmail ?? "")
            Spacer()
            Text("Bound").foregroundColor(.green)
        }
    } else {
        Button("Bind Google Account") {
            bindGoogle()
        }
    }
}
```

---

## Part 6: Security Considerations

### 6.1 Token Verification
- Google ID token verified server-side via `google-auth-library`
- Never trust client-provided email — always extract from verified token
- `googleSub` (Google's unique ID) is immutable, use as primary lookup key

### 6.2 Account Linking Protection
- Phone and Google are independent login methods after binding
- Cannot unbind phone (always required as primary)
- Google can be unbound only if phone is still bound (always true by design)
- Bind-google checks email not already used by another user

### 6.3 Phone Binding During Signup
- Phone OTP verification happens via Firebase (same as existing flow)
- Both googleIdToken AND phoneIdToken required for google-signup
- Backend verifies BOTH tokens independently — no trust chain
- Prevents creating accounts with unverified phones

### 6.4 Rate Limiting
- google-login: same rate limit as auth (5/min)
- google-signup: same rate limit as auth (5/min)
- bind-google: same rate limit as general API (100/min)

---

## Part 7: Firestore Rules Update

```javascript
// Add to users collection rules:
match /users/{userId} {
  allow read: if isAuth() && (isOwner(userId) || isGuardianOf(userId));
  allow create: if isAuth();
  allow update: if isAuth() && isOwner(userId)
    // Prevent users from changing their own auth fields directly
    && !request.resource.data.diff(resource.data).affectedKeys()
        .hasAny(['googleSub', 'authProviders', 'phone']);
}
```

Users cannot modify `googleSub`, `authProviders`, or `phone` directly — only backend can.

---

## Part 8: Testing Checklist

### Backend Tests (Jest)
- [ ] google-login: valid token → 200 + JWT
- [ ] google-login: invalid token → 401
- [ ] google-login: unregistered email → 404 with email/name
- [ ] google-login: user without phone bound → 403
- [ ] google-signup: valid google + phone tokens → 201
- [ ] google-signup: duplicate email → 409
- [ ] google-signup: duplicate phone → 409
- [ ] google-signup: missing phone token → 400
- [ ] bind-google: already bound to another user → 409
- [ ] bind-google: success → authProviders includes "google"
- [ ] existing phone login still works for google-bound users
- [ ] rate limiting applies to google endpoints

### iOS Tests
- [ ] Google button visible on login screen
- [ ] Google sign-in flow opens consent screen
- [ ] 404 from google-login redirects to GoogleSignupView
- [ ] Phone binding required during Google signup (cannot skip)
- [ ] Pre-filled name from Google profile
- [ ] OTP verification works during Google signup
- [ ] After signup, can login with either Google or phone
- [ ] Settings shows bound providers
- [ ] Bind Google from settings works

---

## Part 9: Implementation Order

```
Phase 1 (Backend):
  1. Add google-auth-library dependency
  2. Add verifyGoogleToken() helper
  3. Add POST /v1/auth/google-login endpoint
  4. Add POST /v1/auth/google-signup endpoint
  5. Add POST /v1/auth/bind-google endpoint
  6. Add Firestore index on googleEmail
  7. Update Firestore rules for auth fields protection
  8. Write Jest tests for all 3 new endpoints

Phase 2 (iOS):
  1. Add GoogleSignIn SDK dependency
  2. Configure Google OAuth client ID in Info.plist + GIDClientID
  3. Add URL scheme for Google callback
  4. Add AuthError new cases
  5. Add AuthManager Google methods
  6. Update LoginView with Google button
  7. Create GoogleSignupView
  8. Update AppCoordinator for Google signup flow
  9. Add Settings bind/unbind UI

Phase 3 (Login Fixes):
  1. Fix L-001: Unify brand name to "Vela"
  2. Fix L-002: Defer notification permission
  3. Fix L-003: Defer location permission
  4. Fix L-004: Add toast for 404 redirect

Phase 4 (Testing):
  1. Run backend tests
  2. Test on simulator (both providers)
  3. Test cross-login (sign up with Google, log in with phone)
  4. Test edge cases (same email different phone, etc.)
```

---

## Environment Variables Needed

```
GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com   # Google OAuth client ID
GOOGLE_CLIENT_SECRET=xxx                            # (server-side only, optional for ID token flow)
```

## Dependencies to Add

**Backend:**
```json
"google-auth-library": "^9.0.0"
```

**iOS:**
```
GoogleSignIn ~> 8.0
```
