export interface SrCandidate {
  candidate_key: string;
  existing_sr_id?: string | null;
  disposition: string;
  title: string;
  brief_description: string;
  actor: string;
  preconditions: string[];
  minimum_guarantee: string[];
  success_guarantee: string[];
  trigger_event: string;
  main_success_scenarios: string[];
  extension_scenarios: string[];
  constraints: string[];
  specification: string[];
  upgrade: string[];
  reliability: string[];
  performance: string[];
  security: string[];
  resilience: string[];
  serviceability: string[];
  testability: string[];
  locatability: string[];
  large_contiguous_memory: string;
  supported_products: string[];
  media_requirements: string[];
  traceability?: Record<string, unknown>;
  confidence: string;
  open_questions: string[];
  review_reasons: string[];
}

export interface SrResultPayload {
  summary?: Record<string, unknown>;
  traceability?: unknown[];
  sr_candidates: SrCandidate[];
  review_items?: unknown[];
  uncovered_sources?: unknown[];
  open_questions?: string[];
}

const toStringValue = (value: unknown, fallback = "TBD"): string => {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number" || typeof value === "boolean")
    return String(value);
  return fallback;
};

const toStringArray = (value: unknown): string[] => {
  if (Array.isArray(value)) {
    return value
      .map((item) => toStringValue(item, ""))
      .filter((item): item is string => Boolean(item));
  }
  const single = toStringValue(value, "");
  return single ? [single] : [];
};

const normalizeCandidate = (
  value: unknown,
  index: number
): SrCandidate | null => {
  if (!value || typeof value !== "object") return null;
  const item = value as Record<string, unknown>;
  const title = toStringValue(item.title, "");
  if (!title) return null;

  return {
    candidate_key: toStringValue(
      item.candidate_key,
      `SRCAND-${String(index + 1).padStart(3, "0")}`
    ),
    existing_sr_id:
      typeof item.existing_sr_id === "string" ? item.existing_sr_id : null,
    disposition: toStringValue(item.disposition, "REVIEW"),
    title,
    brief_description: toStringValue(
      item.brief_description ?? item.requirement
    ),
    actor: toStringValue(item.actor, "本系统"),
    preconditions: toStringArray(item.preconditions),
    minimum_guarantee: toStringArray(item.minimum_guarantee),
    success_guarantee: toStringArray(item.success_guarantee),
    trigger_event: toStringValue(item.trigger_event),
    main_success_scenarios: toStringArray(
      item.main_success_scenarios ?? item.normal_scenarios
    ),
    extension_scenarios: toStringArray(
      item.extension_scenarios ?? item.exception_scenarios
    ),
    constraints: toStringArray(item.constraints),
    specification: toStringArray(item.specification),
    upgrade: toStringArray(item.upgrade),
    reliability: toStringArray(item.reliability),
    performance: toStringArray(item.performance),
    security: toStringArray(item.security),
    resilience: toStringArray(item.resilience),
    serviceability: toStringArray(item.serviceability),
    testability: toStringArray(item.testability),
    locatability: toStringArray(item.locatability),
    large_contiguous_memory: toStringValue(item.large_contiguous_memory),
    supported_products: toStringArray(item.supported_products),
    media_requirements: toStringArray(item.media_requirements),
    traceability:
      item.traceability && typeof item.traceability === "object"
        ? (item.traceability as Record<string, unknown>)
        : undefined,
    confidence: toStringValue(item.confidence, "LOW"),
    open_questions: toStringArray(item.open_questions),
    review_reasons: toStringArray(item.review_reasons),
  };
};

export const parseSrResult = (text: string): SrResultPayload | null => {
  if (!text || !text.toLowerCase().includes("<sr_output>")) return null;
  const match = text.match(/<sr_output>\s*([\s\S]*?)\s*<\/sr_output>/i);
  if (!match) return null;

  const jsonText = match[1]
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "")
    .trim();

  try {
    const raw = JSON.parse(jsonText) as Record<string, unknown>;
    if (!Array.isArray(raw.sr_candidates)) return null;
    const candidates = raw.sr_candidates
      .map(normalizeCandidate)
      .filter((item): item is SrCandidate => item !== null);
    return {
      summary:
        raw.summary && typeof raw.summary === "object"
          ? (raw.summary as Record<string, unknown>)
          : undefined,
      traceability: Array.isArray(raw.traceability) ? raw.traceability : [],
      sr_candidates: candidates,
      review_items: Array.isArray(raw.review_items) ? raw.review_items : [],
      uncovered_sources: Array.isArray(raw.uncovered_sources)
        ? raw.uncovered_sources
        : [],
      open_questions: toStringArray(raw.open_questions),
    };
  } catch {
    return null;
  }
};

const SR_OUTPUT_BLOCK_RE = /<sr_output\b[^>]*>[\s\S]*?(?:<\/sr_output>|$)/gi;

/** Keep structured payloads out of the visible reasoning transcript. */
export const summarizeSrOutputInReasoning = (text: string): string =>
  text.replace(
    SR_OUTPUT_BLOCK_RE,
    "\n\n结构化 SR 结果已生成，请查看下方表格。\n\n"
  );
