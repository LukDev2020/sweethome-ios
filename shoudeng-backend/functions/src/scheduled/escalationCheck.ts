import * as functions from "firebase-functions";
import { advanceDueEscalations } from "../services/escalation";

/**
 * Durability backstop for SOS escalation: every minute, run any escalation step
 * that is due but was not run inline (instance crash, timeout, cold start).
 */
export const advanceEscalations = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    const ran = await advanceDueEscalations(new Date());
    if (ran > 0) console.log(`[Escalation] scheduler advanced ${ran} step(s)`);
  });
