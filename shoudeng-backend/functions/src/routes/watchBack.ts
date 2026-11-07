import { Router, Request, Response } from "express";
import { authMiddleware } from "../middleware/auth";
import {
  requestWatchBack, offerWatchBack, respondWatchBack, stopWatchBack, watchBackOverview, WatchBackError,
} from "../services/watchBack";

/**
 * Watch back (see services/watchBack.ts).
 *   GET  /v1/watch-back             { guardians: [{id,name,state}], people: [...] }
 *   POST /v1/watch-back/request     { guardianId }        person being cared for asks
 *   POST /v1/watch-back/offer       { personId }          guardian lets them (active at once)
 *   POST /v1/watch-back/respond     { personId, accept }  guardian answers a request
 *   POST /v1/watch-back/stop        { otherId }           either side
 */
const router = Router();
router.use(authMiddleware);

async function run(res: Response, what: string, work: () => Promise<unknown>) {
  try {
    const state = await work();
    res.json(typeof state === "string" ? { state } : { success: true });
  } catch (e) {
    if (e instanceof WatchBackError) {
      res.status(e.status).json({ error: e.message });
      return;
    }
    console.error(`[WatchBack] ${what} failed:`, e);
    res.status(500).json({ error: `Failed to ${what}` });
  }
}

router.get("/", async (req: Request, res: Response) => {
  try { res.json(await watchBackOverview(req.uid!)); } catch (e) {
    console.error("[WatchBack] overview failed:", e);
    res.status(500).json({ error: "Failed to load" });
  }
});
router.post("/request", (req, res) => run(res, "request", () => requestWatchBack(req.uid!, req.body?.guardianId)));
router.post("/offer", (req, res) => run(res, "offer", () => offerWatchBack(req.uid!, req.body?.personId)));
router.post("/respond", (req, res) => run(res, "respond", () => respondWatchBack(req.uid!, req.body?.personId, req.body?.accept)));
router.post("/stop", (req, res) => run(res, "stop", () => stopWatchBack(req.uid!, req.body?.otherId)));

export default router;
