import * as functions from "firebase-functions";

// MARK: - Structured Logger
//
// JSON-formatted structured logging for Cloud Logging.
// Enables log-based alerting via Google Cloud Monitoring.

type LogLevel = "INFO" | "WARN" | "ERROR";

interface LogEntry {
  severity: LogLevel;
  message: string;
  service: string;
  [key: string]: unknown;
}

function log(level: LogLevel, service: string, message: string, extra?: Record<string, unknown>): void {
  const entry: LogEntry = {
    severity: level,
    message,
    service,
    timestamp: new Date().toISOString(),
    ...extra,
  };

  switch (level) {
    case "ERROR":
      functions.logger.error(entry);
      break;
    case "WARN":
      functions.logger.warn(entry);
      break;
    default:
      functions.logger.info(entry);
  }
}

export const logger = {
  info: (service: string, message: string, extra?: Record<string, unknown>) =>
    log("INFO", service, message, extra),

  warn: (service: string, message: string, extra?: Record<string, unknown>) =>
    log("WARN", service, message, extra),

  error: (service: string, message: string, extra?: Record<string, unknown>) =>
    log("ERROR", service, message, extra),

  // SOS-specific logging with full context
  sos: (action: string, sosEventId: string, extra?: Record<string, unknown>) =>
    log("INFO", "sos", action, { sosEventId, ...extra }),

  // Auth event logging
  auth: (action: string, userId?: string, extra?: Record<string, unknown>) =>
    log("INFO", "auth", action, { userId, ...extra }),

  // Payment event logging
  payment: (action: string, userId?: string, extra?: Record<string, unknown>) =>
    log("INFO", "payment", action, { userId, ...extra }),

  // Webhook event logging
  webhook: (source: string, action: string, extra?: Record<string, unknown>) =>
    log("INFO", "webhook", `${source}: ${action}`, extra),
};
