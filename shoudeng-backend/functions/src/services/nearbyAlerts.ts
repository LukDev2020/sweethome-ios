/**
 * Nearby alerts: disasters, traffic and crime around a point, from public sources.
 *
 * Every category says what is known here, so the app can tell three cases apart:
 *   - "found": the source covers this place and has something → show it
 *   - "clear": the source covers this place and has nothing → "nothing reported"
 *   - "noData": no public source for this place (or it failed) → "no public
 *     information here, take care"
 *
 * Sources (no personal data is sent, only a rounded point):
 *   disaster: USGS earthquakes (world), GDACS (world: cyclones, floods, volcanoes,
 *             wildfires, droughts, earthquakes), US National Weather Service alerts
 *   traffic:  TomTom incidents, only when TOMTOM_API_KEY is set
 *   crime:    police.uk (England, Wales, Northern Ireland) and the open data of
 *             New York, Chicago, San Francisco and Toronto — a summary of what was
 *             reported within ~1.6 km, never single reports
 */

export type Category = "disaster" | "traffic" | "crime";
export type Status = "found" | "clear" | "noData";

export interface NearbyAlert {
  id: string;
  category: Category;
  /** earthquake, cyclone, flood, volcano, wildfire, drought, tsunami, weather,
   *  accident, closure, roadworks, jam, hazard, crimeSummary */
  kind: string;
  /** 1 minor, 2 moderate, 3 serious */
  severity: number;
  distanceKm: number;
  occurredAt?: string;
  /** Source text (its own language), e.g. "12 km S of Changning, China" */
  place?: string;
  magnitude?: number;
  source: string;
  url?: string;
  /** crimeSummary: reports in the window, top categories (source wording) */
  total?: number;
  top?: { label: string; count: number }[];
  /** crimeSummary: newest report in the data (open data runs weeks behind) */
  dataUntil?: string;
  radiusKm?: number;
}

export interface CategoryCoverage {
  status: Status;
  sources: string[];
}

export interface NearbyResult {
  radiusKm: number;
  updatedAt: string;
  coverage: Record<Category, CategoryCoverage>;
  alerts: NearbyAlert[];
}

export const RADII = [10, 30, 50, 100];
/** Crime is about the streets around you, not the whole region */
export const CRIME_RADIUS_KM = 1.6;
const TIMEOUT_MS = 6000;
/** police.uk and the city portals can take a while */
const CRIME_TIMEOUT_MS = 12000;
const UA = "Beaconify family safety app (https://omni-webb.web.app/beaconify)";

type Fetch = (url: string, init?: { headers?: Record<string, string> }) => Promise<{ ok: boolean; status: number; json(): Promise<any> }>;

// MARK: - Geometry

export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)));
}

const round1 = (n: number) => Math.round(n * 10) / 10;

// MARK: - Where crime open data exists

interface Box { s: number; n: number; w: number; e: number }
const inBox = (lat: number, lng: number, b: Box) => lat >= b.s && lat <= b.n && lng >= b.w && lng <= b.e;

export const CRIME_AREAS: { id: string; source: string; box: Box }[] = [
  { id: "uk", source: "police.uk", box: { s: 49.8, n: 55.85, w: -8.2, e: 1.8 } },
  { id: "nyc", source: "NYC Open Data (NYPD)", box: { s: 40.49, n: 40.92, w: -74.27, e: -73.68 } },
  { id: "chicago", source: "Chicago Data Portal", box: { s: 41.64, n: 42.03, w: -87.95, e: -87.52 } },
  { id: "sf", source: "DataSF (SFPD)", box: { s: 37.70, n: 37.84, w: -122.52, e: -122.35 } },
  { id: "toronto", source: "Toronto Police open data", box: { s: 43.58, n: 43.86, w: -79.64, e: -79.11 } },
];

export function crimeAreaAt(lat: number, lng: number) {
  return CRIME_AREAS.find((a) => inBox(lat, lng, a.box));
}

/** Contiguous US, Alaska, Hawaii, Puerto Rico (NWS alerts) */
export function isUS(lat: number, lng: number): boolean {
  return inBox(lat, lng, { s: 24.4, n: 49.5, w: -125, e: -66.9 })
    || inBox(lat, lng, { s: 51, n: 71.5, w: -170, e: -129.9 })
    || inBox(lat, lng, { s: 18.8, n: 22.4, w: -160.4, e: -154.7 })
    || inBox(lat, lng, { s: 17.8, n: 18.6, w: -67.3, e: -65.2 });
}

// MARK: - Helpers

async function getJSON(fetchFn: Fetch, url: string, headers: Record<string, string> = {}, timeoutMs = TIMEOUT_MS): Promise<any> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error(`timeout ${url.split("?")[0]}`)), timeoutMs); });
  try {
    const res = await Promise.race([fetchFn(url, { headers: { "User-Agent": UA, Accept: "application/json", ...headers } }), timeout]);
    if (!res.ok) throw new Error(`${url.split("?")[0]} → ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

export function topCounts(labels: string[], n = 3): { label: string; count: number }[] {
  const m = new Map<string, number>();
  for (const l of labels) if (l) m.set(l, (m.get(l) ?? 0) + 1);
  return [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, n).map(([label, count]) => ({ label, count }));
}

const isoDaysAgo = (days: number) => new Date(Date.now() - days * 86400000).toISOString();

// MARK: - Disasters

export function earthquakeSeverity(mag: number): number {
  return mag >= 5.5 ? 3 : mag >= 4 ? 2 : 1;
}

export async function fetchEarthquakes(fetchFn: Fetch, lat: number, lng: number, radiusKm: number): Promise<NearbyAlert[]> {
  const url = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson"
    + `&latitude=${lat}&longitude=${lng}&maxradiuskm=${radiusKm}`
    + `&starttime=${isoDaysAgo(7).slice(0, 10)}&minmagnitude=2.5&orderby=time&limit=20`;
  const data = await getJSON(fetchFn, url);
  return (data.features ?? []).map((f: any) => {
    const [lng2, lat2] = f.geometry.coordinates;
    const mag = Number(f.properties.mag);
    return {
      id: `usgs-${f.id}`,
      category: "disaster",
      kind: "earthquake",
      severity: earthquakeSeverity(mag),
      distanceKm: round1(distanceKm(lat, lng, lat2, lng2)),
      occurredAt: new Date(f.properties.time).toISOString(),
      place: f.properties.place,
      magnitude: Math.round(mag * 10) / 10,
      source: "USGS",
      url: f.properties.url,
    } as NearbyAlert;
  });
}

const GDACS_KIND: Record<string, string> = { EQ: "earthquake", TC: "cyclone", FL: "flood", VO: "volcano", WF: "wildfire", DR: "drought", TS: "tsunami" };
/** A cyclone or eruption far away still matters: look further for those */
const GDACS_REACH_KM: Record<string, number> = { TC: 400, VO: 150, TS: 300 };

/** GDACS's list is the same for everyone: one download per 30 minutes per instance */
let gdacsCache: { at: number; data: any } | undefined;
const GDACS_CACHE_MS = 30 * 60 * 1000;
export function clearGdacsCache(): void { gdacsCache = undefined; }

export async function fetchGdacs(fetchFn: Fetch, lat: number, lng: number, radiusKm: number): Promise<NearbyAlert[]> {
  let data = gdacsCache && Date.now() - gdacsCache.at < GDACS_CACHE_MS ? gdacsCache.data : undefined;
  if (!data) {
    const url = "https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH"
      + `?fromDate=${isoDaysAgo(14).slice(0, 10)}&toDate=${new Date().toISOString().slice(0, 10)}&alertlevel=Green;Orange;Red`;
    data = await getJSON(fetchFn, url, {}, 10000);
    gdacsCache = { at: Date.now(), data };
  }
  const out: NearbyAlert[] = [];
  for (const f of data.features ?? []) {
    const p = f.properties ?? {};
    // USGS already lists earthquakes, with more detail
    if (p.eventtype === "EQ" || p.iscurrent === "false") continue;
    const kind = GDACS_KIND[p.eventtype];
    if (!kind || f.geometry?.type !== "Point") continue;
    const [lng2, lat2] = f.geometry.coordinates;
    const d = distanceKm(lat, lng, lat2, lng2);
    if (d > Math.max(radiusKm, GDACS_REACH_KM[p.eventtype] ?? 0)) continue;
    out.push({
      id: `gdacs-${p.eventtype}-${p.eventid}`,
      category: "disaster",
      kind,
      severity: p.alertlevel === "Red" ? 3 : p.alertlevel === "Orange" ? 2 : 1,
      distanceKm: round1(d),
      occurredAt: p.fromdate ? new Date(p.fromdate + "Z").toISOString() : undefined,
      place: p.name || p.description,
      source: "GDACS",
      url: p.url?.report,
    });
  }
  return out;
}

export async function fetchWeatherAlertsUS(fetchFn: Fetch, lat: number, lng: number): Promise<NearbyAlert[]> {
  const data = await getJSON(fetchFn, `https://api.weather.gov/alerts/active?point=${lat.toFixed(4)},${lng.toFixed(4)}`, { Accept: "application/geo+json" });
  return (data.features ?? []).map((f: any) => {
    const p = f.properties ?? {};
    const sev = p.severity === "Extreme" || p.severity === "Severe" ? 3 : p.severity === "Moderate" ? 2 : 1;
    return {
      id: `nws-${p.id ?? f.id}`,
      category: "disaster",
      kind: "weather",
      severity: sev,
      distanceKm: 0,
      occurredAt: p.sent ? new Date(p.sent).toISOString() : undefined,
      place: p.event,
      source: "US National Weather Service",
    } as NearbyAlert;
  });
}

// MARK: - Traffic (TomTom; needs a key)

const TOMTOM_KIND: Record<number, string> = { 1: "accident", 7: "closure", 8: "closure", 9: "roadworks", 6: "jam", 3: "hazard", 2: "hazard", 4: "hazard", 5: "hazard", 10: "hazard", 11: "hazard", 14: "hazard" };

export async function fetchTraffic(fetchFn: Fetch, key: string, lat: number, lng: number, radiusKm: number): Promise<NearbyAlert[]> {
  // TomTom limits the box to 10,000 km²: at most ~50 km either side
  const r = Math.min(radiusKm, 50);
  const dLat = r / 111;
  const dLng = r / (111 * Math.max(0.2, Math.cos((lat * Math.PI) / 180)));
  const bbox = [lng - dLng, lat - dLat, lng + dLng, lat + dLat].map((n) => n.toFixed(4)).join(",");
  const fields = encodeURIComponent("{incidents{type,geometry{type,coordinates},properties{id,iconCategory,magnitudeOfDelay,startTime,from,to,roadNumbers}}}");
  const url = `https://api.tomtom.com/traffic/services/5/incidentDetails?bbox=${bbox}&fields=${fields}&language=en-GB&categoryFilter=1,6,7,8,9&timeValidityFilter=present&key=${encodeURIComponent(key)}`;
  const data = await getJSON(fetchFn, url);
  const out: NearbyAlert[] = [];
  for (const inc of data.incidents ?? []) {
    const p = inc.properties ?? {};
    const coords = inc.geometry?.type === "Point" ? [inc.geometry.coordinates] : inc.geometry?.coordinates ?? [];
    if (!coords.length) continue;
    const [lng2, lat2] = coords[0];
    const d = distanceKm(lat, lng, lat2, lng2);
    if (d > radiusKm) continue;
    const kind = TOMTOM_KIND[p.iconCategory] ?? "hazard";
    // Accidents and closures matter; a small jam is minor
    const severity = kind === "accident" || kind === "closure" ? Math.max(2, Math.min(3, p.magnitudeOfDelay ?? 2)) : Math.max(1, Math.min(2, p.magnitudeOfDelay ?? 1));
    const road = (p.roadNumbers ?? [])[0];
    out.push({
      id: `tomtom-${p.id}`,
      category: "traffic",
      kind,
      severity,
      distanceKm: round1(d),
      occurredAt: p.startTime,
      place: [road, p.from && p.to ? `${p.from} → ${p.to}` : p.from].filter(Boolean).join(" · "),
      source: "TomTom",
    });
  }
  return out;
}

// MARK: - Crime summaries

function crimeSummary(area: string, source: string, groups: { label: string; count: number }[], newest: string | undefined, url?: string): NearbyAlert | null {
  const total = groups.reduce((n, g) => n + g.count, 0);
  if (total === 0) return null;
  return {
    id: `crime-${area}`,
    category: "crime",
    kind: "crimeSummary",
    severity: 1,
    distanceKm: 0,
    total,
    top: [...groups].filter((g) => g.label).sort((a, b) => b.count - a.count).slice(0, 3),
    dataUntil: newest,
    radiusKm: CRIME_RADIUS_KM,
    source,
    url,
  };
}

/** Socrata (NYC, Chicago, SF): counts per category and the newest date, done by the portal */
async function socrata(fetchFn: Fetch, base: string, labelField: string, dateField: string, pointField: string,
  lat: number, lng: number, m: number, since: string) {
  const where = encodeURIComponent(`within_circle(${pointField},${lat},${lng},${m}) AND ${dateField} > '${since}'`);
  const [groups, newest] = await Promise.all([
    getJSON(fetchFn, `${base}?$select=${labelField},count(*) as n&$where=${where}&$group=${labelField}&$order=n DESC&$limit=50`, {}, CRIME_TIMEOUT_MS),
    getJSON(fetchFn, `${base}?$select=max(${dateField}) as newest&$where=${where}`, {}, CRIME_TIMEOUT_MS),
  ]);
  return {
    groups: (groups as any[]).map((g) => ({ label: String(g[labelField] ?? ""), count: Number(g.n) || 0 })),
    newest: (newest as any[])[0]?.newest as string | undefined,
  };
}

/** Reports within CRIME_RADIUS_KM over the last 90 days (open data lags weeks) */
export async function fetchCrime(fetchFn: Fetch, lat: number, lng: number): Promise<NearbyAlert | null | undefined> {
  const area = crimeAreaAt(lat, lng);
  if (!area) return undefined; // no public data here
  const m = Math.round(CRIME_RADIUS_KM * 1000);
  const since = isoDaysAgo(90).slice(0, 19);
  switch (area.id) {
    case "uk": {
      // Latest published month, one mile around the point
      const rows: any[] = await getJSON(fetchFn, `https://data.police.uk/api/crimes-street/all-crime?lat=${lat.toFixed(4)}&lng=${lng.toFixed(4)}`, {}, CRIME_TIMEOUT_MS);
      const pretty = (c: string) => c.replace(/-/g, " ").replace(/^./, (x) => x.toUpperCase());
      const month = rows.map((r) => r.month).filter(Boolean).sort().pop();
      return crimeSummary("uk", area.source, topCounts(rows.map((r) => pretty(r.category)), 50), month ? `${month}-01` : undefined, "https://www.police.uk");
    }
    case "nyc": {
      const r = await socrata(fetchFn, "https://data.cityofnewyork.us/resource/5uac-w243.json", "ofns_desc", "cmplnt_fr_dt", "lat_lon", lat, lng, m, since);
      return crimeSummary("nyc", area.source, r.groups, r.newest, "https://data.cityofnewyork.us");
    }
    case "chicago": {
      const r = await socrata(fetchFn, "https://data.cityofchicago.org/resource/ijzp-q8t2.json", "primary_type", "date", "location", lat, lng, m, since);
      return crimeSummary("chicago", area.source, r.groups, r.newest, "https://data.cityofchicago.org");
    }
    case "sf": {
      const r = await socrata(fetchFn, "https://data.sf.gov/resource/wg3w-h783.json", "incident_category", "incident_datetime", "point", lat, lng, m, since);
      return crimeSummary("sf", area.source, r.groups, r.newest, "https://data.sf.gov");
    }
    case "toronto": {
      const stats = encodeURIComponent(JSON.stringify([
        { statisticType: "count", onStatisticField: "OBJECTID", outStatisticFieldName: "n" },
        { statisticType: "max", onStatisticField: "OCC_DATE", outStatisticFieldName: "newest" },
      ]));
      const data = await getJSON(fetchFn, "https://services.arcgis.com/S9th0jAJ7bqgIRjw/arcgis/rest/services/Major_Crime_Indicators_Open_Data/FeatureServer/0/query"
        + `?where=${encodeURIComponent(`OCC_DATE > TIMESTAMP '${since.replace("T", " ")}'`)}`
        + `&geometry=${lng},${lat}&geometryType=esriGeometryPoint&inSR=4326&distance=${m}&units=esriSRUnit_Meter`
        + `&outStatistics=${stats}&groupByFieldsForStatistics=CSI_CATEGORY&f=json`, {}, CRIME_TIMEOUT_MS);
      const rows: any[] = (data.features ?? []).map((f: any) => f.attributes);
      const newestMs = Math.max(0, ...rows.map((r) => Number(r.newest) || 0));
      return crimeSummary("toronto", area.source, rows.map((r) => ({ label: String(r.CSI_CATEGORY ?? ""), count: Number(r.n) || 0 })),
        newestMs ? new Date(newestMs).toISOString() : undefined, "https://data.torontopolice.on.ca");
    }
  }
  return undefined;
}

// MARK: - Everything together

/** Most serious first, then nearest, then newest */
export function rank(a: NearbyAlert, b: NearbyAlert): number {
  if (b.severity !== a.severity) return b.severity - a.severity;
  if (a.distanceKm !== b.distanceKm) return a.distanceKm - b.distanceKm;
  return (b.occurredAt ?? "").localeCompare(a.occurredAt ?? "");
}

export async function nearbyAlerts(
  lat: number, lng: number, radiusKm: number,
  opts: { fetchFn?: Fetch; tomtomKey?: string; limit?: number } = {},
): Promise<NearbyResult> {
  const fetchFn: Fetch = opts.fetchFn ?? (globalThis.fetch as unknown as Fetch);
  const limit = opts.limit ?? 5;
  const settle = <T>(p: Promise<T>) => p.then((v) => ({ ok: true as const, v }), (e) => {
    console.warn("[Nearby]", String(e?.message ?? e));
    return { ok: false as const };
  });

  const us = isUS(lat, lng);
  const [quakes, gdacs, weather, traffic, crime] = await Promise.all([
    settle(fetchEarthquakes(fetchFn, lat, lng, radiusKm)),
    settle(fetchGdacs(fetchFn, lat, lng, radiusKm)),
    us ? settle(fetchWeatherAlertsUS(fetchFn, lat, lng)) : Promise.resolve(null),
    opts.tomtomKey ? settle(fetchTraffic(fetchFn, opts.tomtomKey, lat, lng, radiusKm)) : Promise.resolve(null),
    settle(fetchCrime(fetchFn, lat, lng)),
  ]);

  const disaster: NearbyAlert[] = [];
  const disasterSources: string[] = [];
  if (quakes.ok) { disaster.push(...quakes.v); disasterSources.push("USGS"); }
  if (gdacs.ok) { disaster.push(...gdacs.v); disasterSources.push("GDACS"); }
  if (weather?.ok) { disaster.push(...weather.v); disasterSources.push("US National Weather Service"); }

  const trafficItems = traffic?.ok ? traffic.v : [];
  const crimeArea = crimeAreaAt(lat, lng);
  const crimeItem = crime.ok && crime.v ? crime.v : null;

  const coverage: Record<Category, CategoryCoverage> = {
    disaster: {
      status: disasterSources.length === 0 ? "noData" : disaster.length > 0 ? "found" : "clear",
      sources: disasterSources,
    },
    traffic: {
      status: !traffic?.ok ? "noData" : trafficItems.length > 0 ? "found" : "clear",
      sources: traffic?.ok ? ["TomTom"] : [],
    },
    crime: {
      // A covered city that returned nothing is "clear"; outside them, or on error, "noData"
      status: !crimeArea || !crime.ok ? "noData" : crimeItem ? "found" : "clear",
      sources: crimeArea && crime.ok ? [crimeArea.source] : [],
    },
  };

  // Each category keeps a place in the short list: the most serious of each first
  const all = [...disaster.sort(rank), ...trafficItems.sort(rank)];
  if (crimeItem) all.push(crimeItem);
  const firstOfEach = (["disaster", "traffic", "crime"] as Category[])
    .map((c) => all.find((a) => a.category === c))
    .filter((a): a is NearbyAlert => !!a);
  const rest = all.filter((a) => !firstOfEach.includes(a)).sort(rank);
  const alerts = [...firstOfEach.sort(rank), ...rest].slice(0, limit);

  return { radiusKm, updatedAt: new Date().toISOString(), coverage, alerts };
}
