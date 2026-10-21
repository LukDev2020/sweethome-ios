# Privacy Policy — Luma (守灯)
**DRAFT FOR LEGAL REVIEW**

*Last updated: 2026-10-20*
*Version: 1.0*

---

## English

### 1. Who We Are
Luma is operated by Vela Care Technology (15407168 Canada Inc.), Ontario, Canada. Contact: privacy@shoudeng.app

### 2. What We Collect and Why

| Data | Why | Retention | Shared With |
|------|-----|-----------|-------------|
| Phone number | Authentication (OTP login) | Until account deletion | Firebase Auth (Google) |
| Display name | Show your name to family members | Until account deletion | Family members you choose |
| Precise location | Share with chosen family in emergencies; safe-zone alerts | 30 days rolling | Chosen family members; Google Cloud (server processing) |
| Device push token | Deliver notifications (SOS alerts, check-in reminders) | Until token refresh or account deletion | Apple Push Notification service; Firebase Cloud Messaging (Google) |
| Medical card data | Emergency reference for guardians (blood type, allergies, medications) | Until account deletion | Linked guardians only |
| Motion sensor data | Fall detection (on-device only) | Not stored server-side | Not shared; on-device processing only |
| Photos | Family circle sharing; claims evidence | Until deleted by user | Family members in guardian relationship |
| Emergency contacts | Quick-dial and notification routing | Until account deletion | Not shared externally |
| Crash reports | App stability improvement | 90 days | Firebase Crashlytics (Google) — no PII attached |
| Ambient audio | Emergency SOS context (if enabled by user) | 48 hours | Linked guardians only |

### 3. How We Use Your Data
- To notify your chosen family members in emergencies
- To display your location and safety status to your guardians
- To deliver push notifications and voice calls during SOS escalation
- To improve app stability through anonymous crash reports

We do NOT use your data for advertising, profiling, or sale to third parties.

### 4. Third-Party Services

| Service | Provider | Purpose | Data Sent |
|---------|----------|---------|-----------|
| Firebase Auth | Google LLC | Phone OTP authentication | Phone number |
| Firebase Firestore | Google LLC | Data storage | All app data (encrypted at rest) |
| Firebase Crashlytics | Google LLC | Crash reporting | Device info, crash stack traces |
| Firebase Cloud Messaging | Google LLC | Push notifications | Device token, notification content |
| Twilio | Twilio Inc. | SMS and voice calls | Phone number, notification text |
| Apple APNs | Apple Inc. | Push delivery | Device token |

### 5. Data Security
- All data in transit uses TLS 1.2+
- Data at rest is encrypted by Google Cloud / Firebase
- Authentication tokens stored in iOS Keychain (hardware-backed)
- No raw coordinates or phone numbers in logs or crash reports

### 6. Your Rights
- **Access**: View all your data in-app (Settings > Profile)
- **Deletion**: Settings > Delete Account — removes auth user, all personal data, and family relationships. Audit logs are anonymized.
- **Portability**: Export your timeline and location history from Records tab
- **Withdraw consent**: Disable any sharing feature at any time (6-hour safety delay applies)

### 7. Children
Luma is not directed at children under 13. We do not knowingly collect data from children.

### 8. Changes
We will notify you of material changes via in-app notification and update the version number of this policy.

---

## Francais

### 1. Qui sommes-nous
Luma est exploite par Vela Care Technology (15407168 Canada Inc.), Ontario, Canada. Contact : privacy@shoudeng.app

### 2. Donnees collectees et finalites

| Donnees | Finalite | Conservation | Partagees avec |
|---------|----------|-------------|----------------|
| Numero de telephone | Authentification (OTP) | Jusqu'a suppression du compte | Firebase Auth (Google) |
| Nom d'affichage | Afficher votre nom aux membres de la famille | Jusqu'a suppression du compte | Membres de la famille choisis |
| Position precise | Partager avec la famille en cas d'urgence ; alertes de zone securisee | 30 jours glissants | Membres de la famille choisis ; Google Cloud |
| Jeton push | Livrer les notifications (alertes SOS, rappels) | Jusqu'au renouvellement ou suppression | Apple APNs ; Firebase Cloud Messaging (Google) |
| Carte medicale | Reference d'urgence pour les gardiens | Jusqu'a suppression du compte | Gardiens lies uniquement |
| Capteurs de mouvement | Detection de chutes (sur l'appareil uniquement) | Non stocke cote serveur | Non partage |
| Photos | Partage en cercle familial ; preuves de sinistre | Jusqu'a suppression par l'utilisateur | Famille dans la relation de tutelle |
| Rapports de plantage | Amelioration de la stabilite | 90 jours | Firebase Crashlytics (Google) — aucune donnee personnelle |

### 3. Vos droits
- **Acces** : Consultez toutes vos donnees dans l'application
- **Suppression** : Parametres > Supprimer le compte
- **Retrait du consentement** : Desactivez toute fonction de partage a tout moment

---

## 中文

### 1. 我们是谁
守灯由 Vela Care Technology (15407168 Canada Inc.) 运营，位于加拿大安大略省。联系方式：privacy@shoudeng.app

### 2. 我们收集什么数据以及为什么

| 数据 | 用途 | 保留期限 | 共享对象 |
|------|------|---------|---------|
| 手机号码 | 验证码登录 | 直到账户删除 | Firebase Auth (Google) |
| 显示名称 | 向家人显示你的名字 | 直到账户删除 | 你选择的家人 |
| 精确位置 | 紧急情况下与选定的家人共享；安全区通知 | 30 天滚动 | 你选择的家人；Google Cloud |
| 设备推送令牌 | 推送通知（SOS 警报、报平安提醒） | 直到刷新或账户删除 | Apple APNs；Firebase Cloud Messaging (Google) |
| 急救卡数据 | 守护者紧急参考（血型、过敏、用药） | 直到账户删除 | 仅关联的守护者 |
| 运动传感器 | 跌倒检测（仅在设备端处理） | 不存储在服务器 | 不共享 |
| 照片 | 家庭圈分享；理赔材料 | 直到用户删除 | 守护关系内的家人 |
| 崩溃报告 | 改善应用稳定性 | 90 天 | Firebase Crashlytics (Google) — 无个人信息 |

### 3. 你的权利
- **查看**：在应用内查看你的所有数据
- **删除**：设置 > 删除账户 — 删除认证用户、所有个人数据和家庭关系
- **撤销同意**：随时关闭任何共享功能（6 小时安全延迟适用）

### 4. 儿童
守灯不面向 13 岁以下儿童。我们不会有意收集儿童数据。
