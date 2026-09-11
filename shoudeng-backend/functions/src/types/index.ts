// Shared type definitions matching iOS client models

export interface UserDoc {
  displayName: string;
  phone: string;
  role: "protected" | "guardian";
  avatarInitial: string;
  timeZone: string;
  countryCode: string;
  cityName: string;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface GuardianLinkDoc {
  guardianId: string;
  protectedPersonId: string;
  status: "pending" | "active" | "revoked";
  createdAt: FirebaseFirestore.Timestamp;
  acceptedAt: FirebaseFirestore.Timestamp | null;
  revokedAt: FirebaseFirestore.Timestamp | null;
  protectionLayers: string[];
}

export interface SOSEventDoc {
  protectedPersonId: string;
  triggeredAt: FirebaseFirestore.Timestamp;
  triggerMethod: string;
  latitude: number | null;
  longitude: number | null;
  accuracy: number | null;
  batteryLevel: number | null;
  escalationState: string;
  resolvedAt: FirebaseFirestore.Timestamp | null;
  resolvedBy: string | null;
  resolution: string | null;
  escalationLog: EscalationLogEntry[];
}

export interface EscalationLogEntry {
  hop: number;
  targetId: string;
  sentAt: FirebaseFirestore.Timestamp;
  deliveredAt: FirebaseFirestore.Timestamp | null;
  readAt: FirebaseFirestore.Timestamp | null;
  respondedAt: FirebaseFirestore.Timestamp | null;
  response: string | null;
}

export interface SafeZoneDoc {
  userId: string;
  name: string;
  latitude: number;
  longitude: number;
  radiusMeters: number;
  type: "home" | "work" | "school" | "custom";
  isActive: boolean;
  createdAt: FirebaseFirestore.Timestamp;
}

export interface DutyScheduleDoc {
  protectedPersonId: string;
  guardianId: string;
  dayOfWeek: number;
  startHour: number;
  endHour: number;
  timeZone: string;
  isActive: boolean;
}

export interface InviteDoc {
  code: string;
  createdBy: string;
  role: string;
  acceptedBy: string | null;
  status: "pending" | "accepted" | "expired";
  createdAt: FirebaseFirestore.Timestamp;
  expiresAt: FirebaseFirestore.Timestamp;
}

export interface DeviceTokenDoc {
  userId: string;
  token: string;
  platform: string;
  environment: string;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface TimelineEntryDoc {
  userId: string;
  timestamp: FirebaseFirestore.Timestamp;
  type: string;
  description: string;
  detail: string | null;
}

export interface EvidenceHoldDoc {
  protectedPersonId: string;
  createdBy: string;
  reason: string;
  timeWindowStart: FirebaseFirestore.Timestamp;
  timeWindowEnd: FirebaseFirestore.Timestamp;
  createdAt: FirebaseFirestore.Timestamp;
  expiresAt: FirebaseFirestore.Timestamp;
}

export interface IntegrityProofDoc {
  date: string;
  heartbeatMerkleRoot: string;
  locationMerkleRoot: string;
  recordCount: number;
  computedAt: FirebaseFirestore.Timestamp;
}

// API request/response types (matching iOS APIEndpoints.swift)

export interface HeartbeatRequest {
  userId: string;
  timestamp: string;
  source: string;
  batteryLevel?: number;
  batteryState?: string;
  latitude?: number;
  longitude?: number;
  accuracy?: number;
}

export interface LocationReportRequest {
  userId: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  altitude?: number;
  speed?: number;
  timestamp: string;
  isInSafeZone?: boolean;
  safeZoneName?: string;
}

export interface SOSTriggerRequest {
  protectedPersonId: string;
  triggerMethod: string;
  latitude?: number;
  longitude?: number;
  batteryLevel?: number;
}

export interface SOSResolveRequest {
  sosEventId: string;
  resolvedBy: string;
  resolution: string;
}

export interface CheckInRequest {
  userId: string;
  latitude?: number;
  longitude?: number;
  note?: string;
}

export interface VoiceCallRequest {
  guardianId: string;
  sosEventId: string;
  protectedPersonName: string;
  locationDescription?: string;
}

export interface DeviceTokenRequest {
  token: string;
  platform: string;
  environment: string;
}

export interface InviteCreateRequest {
  role: string;
}

export interface InviteAcceptRequest {
  inviteId: string;
}

export interface UpdateProfileRequest {
  displayName?: string;
  timeZone?: string;
  cityName?: string;
  countryCode?: string;
}

export interface SaveSafeZoneRequest {
  name: string;
  latitude: number;
  longitude: number;
  radius: number;
}

export interface UpdateDutyScheduleRequest {
  guardianId: string;
  slots: DutySlotInput[];
}

export interface DutySlotInput {
  startHour: number;
  endHour: number;
  dayOfWeek: number[];
  isConfirmed: boolean;
}

export interface EvidenceGenerateRequest {
  protectedPersonId: string;
  timeWindowStart: string;
  timeWindowEnd: string;
  format: "pdf" | "json" | "gpx";
  reason: string;
}
