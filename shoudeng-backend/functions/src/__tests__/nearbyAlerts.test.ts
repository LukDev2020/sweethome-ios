import {
  nearbyAlerts, crimeAreaAt, isUS, earthquakeSeverity, distanceKm, rank, clearGdacsCache, NearbyAlert,
} from "../services/nearbyAlerts";
import { shouldTouch, THROTTLE_MS } from "../services/presence";

type Route = (url: string) => any;
function fakeFetch(route: Route) {
  const calls: string[] = [];
  const fn = async (url: string) => {
    calls.push(url);
    const body = route(url);
    if (body instanceof Error) throw body;
    if (typeof body === "number") return { ok: false, status: body, json: async () => ({}) };
    return { ok: true, status: 200, json: async () => body };
  };
  return { fn, calls };
}

const quake = (id: string, mag: number, lng: number, lat: number) => ({
  id, geometry: { coordinates: [lng, lat, 10] },
  properties: { mag, place: `near ${id}`, time: Date.now() - 3600_000, url: `https://usgs/${id}` },
});

beforeEach(() => clearGdacsCache());

describe("where public data exists", () => {
  it("knows the crime areas and the US", () => {
    expect(crimeAreaAt(51.51, -0.13)?.id).toBe("uk");
    expect(crimeAreaAt(40.71, -74.0)?.id).toBe("nyc");
    expect(crimeAreaAt(43.65, -79.38)?.id).toBe("toronto");
    expect(crimeAreaAt(30.66, 104.06)).toBeUndefined();   // Chengdu
    expect(crimeAreaAt(-37.81, 144.96)).toBeUndefined();  // Melbourne
    expect(isUS(40.71, -74.0)).toBe(true);
    expect(isUS(30.66, 104.06)).toBe(false);
  });

  it("measures distance and earthquake severity", () => {
    expect(distanceKm(0, 0, 0, 1)).toBeCloseTo(111.2, 0);
    expect(earthquakeSeverity(3)).toBe(1);
    expect(earthquakeSeverity(4.6)).toBe(2);
    expect(earthquakeSeverity(6.1)).toBe(3);
  });
});

describe("nearbyAlerts", () => {
  it("Chengdu: disasters found, no traffic key and no crime data → noData for both", async () => {
    const { fn, calls } = fakeFetch((url) => {
      if (url.includes("usgs")) return { features: [quake("a", 4.6, 104.9, 28.5), quake("b", 2.8, 104.1, 30.7)] };
      if (url.includes("gdacs")) return { features: [] };
      throw new Error(`unexpected ${url}`);
    });
    const res = await nearbyAlerts(30.66, 104.06, 100, { fetchFn: fn });
    expect(res.coverage.disaster.status).toBe("found");
    expect(res.coverage.traffic.status).toBe("noData");
    expect(res.coverage.crime.status).toBe("noData");
    expect(res.alerts.map((a) => a.id)).toEqual(["usgs-a", "usgs-b"]); // more serious first
    expect(res.alerts[0].magnitude).toBe(4.6);
    expect(calls.some((u) => u.includes("weather.gov"))).toBe(false); // not the US
    expect(calls.some((u) => u.includes("tomtom"))).toBe(false);      // no key
  });

  it("nothing reported where the sources cover → clear, not noData", async () => {
    const { fn } = fakeFetch((url) => {
      if (url.includes("usgs")) return { features: [] };
      if (url.includes("gdacs")) return { features: [] };
      if (url.includes("police.uk")) return [];
      throw new Error(url);
    });
    const res = await nearbyAlerts(51.51, -0.13, 30, { fetchFn: fn });
    expect(res.coverage.disaster.status).toBe("clear");
    expect(res.coverage.crime.status).toBe("clear");
    expect(res.alerts).toEqual([]);
  });

  it("a failing source is noData, never an error for the whole answer", async () => {
    const { fn } = fakeFetch(() => new Error("down"));
    const res = await nearbyAlerts(51.51, -0.13, 30, { fetchFn: fn });
    expect(res.coverage.disaster.status).toBe("noData");
    expect(res.coverage.crime.status).toBe("noData");
  });

  it("GDACS: far floods are left out, a cyclone within 400 km stays; earthquakes come from USGS", async () => {
    const ev = (type: string, id: number, lng: number, lat: number, level = "Orange") => ({
      geometry: { type: "Point", coordinates: [lng, lat] },
      properties: { eventtype: type, eventid: id, alertlevel: level, iscurrent: "true", name: `${type} ${id}`, fromdate: "2026-11-20T00:00:00", url: { report: "r" } },
    });
    const { fn } = fakeFetch((url) => {
      if (url.includes("usgs")) return { features: [] };
      if (url.includes("gdacs")) return { features: [
        ev("FL", 1, 106.5, 30.66),   // ~235 km: beyond 30 km
        ev("TC", 2, 106.5, 30.66),   // same place, but a cyclone reaches 400 km
        ev("EQ", 3, 104.06, 30.66),  // USGS covers earthquakes
      ] };
      throw new Error(url);
    });
    const res = await nearbyAlerts(30.66, 104.06, 30, { fetchFn: fn });
    expect(res.alerts.map((a) => a.kind)).toEqual(["cyclone"]);
    expect(res.alerts[0].severity).toBe(2);
  });

  it("New York: crime is a summary counted by the portal; each category keeps a place in the short list", async () => {
    const { fn } = fakeFetch((url) => {
      if (url.includes("usgs")) return { features: [quake("q1", 4.1, -74.1, 40.7), quake("q2", 4.2, -74.1, 40.7), quake("q3", 4.3, -74.1, 40.7), quake("q4", 4.4, -74.1, 40.7), quake("q5", 4.5, -74.1, 40.7)] };
      if (url.includes("gdacs")) return { features: [] };
      if (url.includes("weather.gov")) return { features: [] };
      if (url.includes("cityofnewyork") && url.includes("count")) return [{ ofns_desc: "PETIT LARCENY", n: "30" }, { ofns_desc: "ROBBERY", n: "5" }, { ofns_desc: "ASSAULT 3", n: "12" }, { ofns_desc: "OTHER", n: "1" }];
      if (url.includes("cityofnewyork") && url.includes("max(")) return [{ newest: "2026-09-30T00:00:00.000" }];
      throw new Error(url);
    });
    const res = await nearbyAlerts(40.71, -74.0, 30, { fetchFn: fn, limit: 5 });
    const crime = res.alerts.find((a) => a.category === "crime")!;
    expect(crime).toBeDefined(); // 5 earthquakes did not push it out
    expect(crime.total).toBe(48);
    expect(crime.top).toEqual([{ label: "PETIT LARCENY", count: 30 }, { label: "ASSAULT 3", count: 12 }, { label: "ROBBERY", count: 5 }]);
    expect(crime.dataUntil).toBe("2026-09-30T00:00:00.000");
    expect(res.alerts).toHaveLength(5);
  });

  it("traffic only with a key; accidents rank above jams", async () => {
    const { fn, calls } = fakeFetch((url) => {
      if (url.includes("usgs") || url.includes("gdacs")) return { features: [] };
      if (url.includes("tomtom")) return { incidents: [
        { geometry: { type: "LineString", coordinates: [[104.07, 30.67], [104.08, 30.68]] }, properties: { id: "j", iconCategory: 6, magnitudeOfDelay: 1, from: "A", to: "B" } },
        { geometry: { type: "Point", coordinates: [104.1, 30.7] }, properties: { id: "x", iconCategory: 1, magnitudeOfDelay: 3, roadNumbers: ["G5"] } },
      ] };
      throw new Error(url);
    });
    const res = await nearbyAlerts(30.66, 104.06, 100, { fetchFn: fn, tomtomKey: "k" });
    expect(res.coverage.traffic.status).toBe("found");
    expect(res.alerts.filter((a) => a.category === "traffic").map((a) => a.kind)).toEqual(["accident", "jam"]);
    // The box is capped at TomTom's 10,000 km² (≈ ±50 km)
    const bbox = decodeURIComponent(calls.find((u) => u.includes("tomtom"))!.split("bbox=")[1].split("&")[0]).split(",").map(Number);
    expect(bbox[3] - bbox[1]).toBeLessThanOrEqual(0.91);
  });

  it("ranks by severity, then distance, then time", () => {
    const a = (id: string, severity: number, distanceKm: number): NearbyAlert => ({ id, category: "disaster", kind: "earthquake", severity, distanceKm, source: "t" });
    expect([a("far", 2, 50), a("near", 2, 5), a("big", 3, 90)].sort(rank).map((x) => x.id)).toEqual(["big", "near", "far"]);
  });
});

describe("who's online", () => {
  it("writes a user at most once per throttle window", () => {
    const t = 1_000_000;
    expect(shouldTouch("u-presence", t)).toBe(true);
    expect(shouldTouch("u-presence", t + 1000)).toBe(false);
    expect(shouldTouch("u-presence", t + THROTTLE_MS + 1)).toBe(true);
  });
});
