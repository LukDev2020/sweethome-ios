import { Router, Request, Response } from "express";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { publicApiBaseUrl } from "../services/twilio";
import {
  createIncidentReport, sealIncidentReport, listIncidentReports, verifyIncidentReport, IncidentReportError,
} from "../services/incidentReport";

/**
 * Incident reports for police (services/incidentReport.ts, docs/police-incident-report.md).
 *   POST /v1/incident-reports            { personId, windowStart, windowEnd, purpose, caseNumber?, sections? }
 *        → { reportId, verifyCode, dataSha256, verifyUrl, canonical }   canonical = data.json, byte for byte
 *   POST /v1/incident-reports/:id/seal   { files: { "report.pdf": sha256, ... } }   once, creator only
 *   GET  /v1/incident-reports?personId=  reports about me / the ones I made about them
 *   GET  /v1/incident-reports/verify?code=&sha256=   public (police), per-IP rate limit
 */
const router = Router();

function fail(res: Response, what: string, e: unknown) {
  if (e instanceof IncidentReportError) {
    res.status(e.status).json({ error: e.message });
    return;
  }
  console.error(`[IncidentReport] ${what} failed:`, e);
  res.status(500).json({ error: `Failed to ${what}` });
}

const verifyUrl = (code: string) => `${publicApiBaseUrl()}/v1/incident-reports/verify?code=${code}`;

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

// Public first: no auth on this one
router.get("/verify", createRateLimiter(RATE_LIMITS.publicShare, (req) => `ip:${req.ip}`), async (req: Request, res: Response) => {
  try {
    const result = await verifyIncidentReport(req.query.code, req.query.sha256, `ip:${req.ip}`);
    if (req.accepts(["json", "html"]) !== "html") {
      res.status(result.valid ? 200 : 404).json(result);
      return;
    }
    res.set("Content-Type", "text/html; charset=utf-8");
    res.set("Cache-Control", "no-store");
    res.set("X-Robots-Tag", "noindex");
    const body = !result.valid
      ? `<h1 class="bad">No report with this code</h1><p>Check the code printed on the report.</p>`
      : `<h1 class="ok">Genuine Lantern Care report ${esc(result.reportId)}</h1>
<p>Created ${esc(result.createdAt)} · covers ${esc(result.windowStart)} – ${esc(result.windowEnd)}${result.caseNumber ? ` · case ${esc(result.caseNumber)}` : ""}</p>
${"fileMatches" in result ? (result.fileMatches ? `<p class="ok">✔ The file you checked is <b>${esc(result.file)}</b>, unchanged.</p>` : `<p class="bad">✘ That SHA-256 matches no file of this report — the file was changed or belongs elsewhere.</p>`) : ""}
<table><tr><th>File</th><th>SHA-256</th></tr>${Object.entries(result.files).map(([f, h]) => `<tr><td>${esc(f)}</td><td><code>${esc(h)}</code></td></tr>`).join("")}</table>
<p><small>Compute a file's SHA-256 with <code>shasum -a 256 FILE</code> (macOS/Linux) or <code>certutil -hashfile FILE SHA256</code> (Windows) and compare.${result.sealed ? "" : " The PDF and map files were not registered yet; data.json can be checked."}</small></p>`;
    res.send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Verify report — Lantern Care</title>
<style>body{font:16px -apple-system,system-ui,sans-serif;margin:24px;color:#12203a;max-width:820px}h1{font-size:21px}.ok{color:#1f7a4d}.bad{color:#c4453c}table{border-collapse:collapse;font-size:13px}td,th{border:1px solid #dde;padding:6px 8px;text-align:left}code{word-break:break-all}small{color:#667}</style></head>
<body>${body}</body></html>`);
  } catch (e) {
    fail(res, "verify", e);
  }
});

router.post("/", authMiddleware, createRateLimiter(RATE_LIMITS.incidentReport), async (req: Request, res: Response) => {
  try {
    const r = await createIncidentReport(req.uid!, req.body ?? {});
    res.status(201).json({ ...r, verifyUrl: verifyUrl(r.verifyCode) });
  } catch (e) {
    fail(res, "create the report", e);
  }
});

router.post("/:id/seal", authMiddleware, async (req: Request, res: Response) => {
  try {
    await sealIncidentReport(req.uid!, req.params.id, req.body?.files);
    res.json({ success: true });
  } catch (e) {
    fail(res, "seal the report", e);
  }
});

router.get("/", authMiddleware, async (req: Request, res: Response) => {
  const personId = typeof req.query.personId === "string" && req.query.personId ? req.query.personId : req.uid!;
  try {
    res.json({ reports: await listIncidentReports(req.uid!, personId) });
  } catch (e) {
    fail(res, "list reports", e);
  }
});

export default router;
