import { Router, Request, Response } from "express";
import { authMiddleware } from "../middleware/auth";
import {
  createCrew, joinCrew, leaveCrew, crewView, setShift, addCaution, respondToCrewSOS, crewAlerts, watchBack, CrewError,
} from "../services/crew";

/**
 * Rider crews (see services/crew.ts).
 *   GET  /v1/crew            my crew, members (location while on shift), caution spots
 *   POST /v1/crew            { name }       create (you become the owner)
 *   POST /v1/crew/join       { code }       join with the invite code
 *   POST /v1/crew/leave
 *   POST /v1/crew/shift      { onShift, plannedEnd?, watcherIds? }   watchers: crew mates + guardians
 *   POST /v1/crew/watch-back { memberId }   watch a crew mate who watches you
 *   POST /v1/crew/caution    { latitude, longitude, note? }   "bike tampered with here"
 *   GET  /v1/crew/alerts     open SOS events of crew mates
 *   POST /v1/crew/respond    { sosEventId, response: going | cant_help }
 */
const router = Router();
router.use(authMiddleware);

function fail(res: Response, error: unknown, what: string) {
  if (error instanceof CrewError) {
    res.status(error.status).json({ error: error.message });
    return;
  }
  console.error(`[Crew] ${what} failed:`, error);
  res.status(500).json({ error: `Failed to ${what}` });
}

router.get("/", async (req: Request, res: Response) => {
  try { res.json({ crew: await crewView(req.uid!) }); } catch (e) { fail(res, e, "load crew"); }
});

router.post("/", async (req: Request, res: Response) => {
  try {
    await createCrew(req.uid!, req.body?.name);
    res.status(201).json({ crew: await crewView(req.uid!) });
  } catch (e) { fail(res, e, "create crew"); }
});

router.post("/join", async (req: Request, res: Response) => {
  try {
    await joinCrew(req.uid!, req.body?.code);
    res.json({ crew: await crewView(req.uid!) });
  } catch (e) { fail(res, e, "join crew"); }
});

router.post("/leave", async (req: Request, res: Response) => {
  try { await leaveCrew(req.uid!); res.json({ success: true }); } catch (e) { fail(res, e, "leave crew"); }
});

router.post("/shift", async (req: Request, res: Response) => {
  if (typeof req.body?.onShift !== "boolean") {
    res.status(400).json({ error: "onShift (boolean) is required" });
    return;
  }
  try { await setShift(req.uid!, req.body.onShift, req.body.plannedEnd, new Date(), req.body.watcherIds); res.json({ success: true }); }
  catch (e) { fail(res, e, "update shift"); }
});

router.post("/watch-back", async (req: Request, res: Response) => {
  try { await watchBack(req.uid!, req.body?.memberId); res.json({ success: true }); }
  catch (e) { fail(res, e, "watch back"); }
});

router.post("/caution", async (req: Request, res: Response) => {
  try { res.status(201).json({ id: await addCaution(req.uid!, req.body ?? {}) }); }
  catch (e) { fail(res, e, "add caution"); }
});

router.get("/alerts", async (req: Request, res: Response) => {
  try { res.json({ alerts: await crewAlerts(req.uid!) }); } catch (e) { fail(res, e, "load crew alerts"); }
});

router.post("/respond", async (req: Request, res: Response) => {
  try { await respondToCrewSOS(req.uid!, req.body?.sosEventId, req.body?.response); res.json({ success: true }); }
  catch (e) { fail(res, e, "respond"); }
});

export default router;
