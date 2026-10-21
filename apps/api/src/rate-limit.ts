export interface RateLimitRule {
  readonly windowMs: number;
  readonly maxRequests: number;
}

export const V1_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000; // 15 menit
export const V1_RATE_LIMIT_MAX_REQUESTS = 100; // Maksimal 100 request per 15 menit per IP Address
export const V1_RATE_LIMIT_MESSAGE =
  'Terlalu banyak permintaan. Silakan coba lagi nanti.';

export const RATE_LIMIT_GROUPS = {
  v1Ip: {
    windowMs: V1_RATE_LIMIT_WINDOW_MS,
    maxRequests: V1_RATE_LIMIT_MAX_REQUESTS,
  },
  general: { windowMs: 60_000, maxRequests: 60 },
  auth: { windowMs: 60_000, maxRequests: 10 },
  putRules: { windowMs: 60_000, maxRequests: 10 },
  simulate: { windowMs: 5_000, maxRequests: 1 },
} as const;

export interface ExpressRateLimitConfig {
  readonly windowMs: number;
  readonly max: number;
  readonly limit: number;
  readonly standardHeaders: boolean;
  readonly legacyHeaders: boolean;
  readonly message: {
    readonly message: string;
    readonly error: {
      readonly code: string;
      readonly message: string;
      readonly details: readonly unknown[];
    };
  };
}

/**
 * Konfigurasi standar express-rate-limit untuk seluruh endpoint `/v1/*` (Fase 9 Langkah 1).
 * Maksimal 100 request per 15 menit per IP Address -> HTTP 429 "Terlalu banyak permintaan. Silakan coba lagi nanti."
 */
export function createV1RateLimitConfig(
  maxRequests: number = V1_RATE_LIMIT_MAX_REQUESTS,
  windowMs: number = V1_RATE_LIMIT_WINDOW_MS,
): ExpressRateLimitConfig {
  return {
    windowMs,
    max: maxRequests,
    limit: maxRequests,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      message: V1_RATE_LIMIT_MESSAGE,
      error: {
        code: 'RATE_LIMITED',
        message: V1_RATE_LIMIT_MESSAGE,
        details: [],
      },
    },
  };
}

interface BucketEntry {
  count: number;
  resetAtMs: number;
}

export class InMemoryRateLimiter {
  private readonly buckets = new Map<string, BucketEntry>();

  check(
    group: string,
    key: string,
    rule: RateLimitRule,
    nowMs: number = Date.now(),
  ): { allowed: boolean; retryAfterSec: number; remaining: number } {
    const compositeKey = `${group}:${key}`;
    const existing = this.buckets.get(compositeKey);

    if (!existing || nowMs >= existing.resetAtMs) {
      this.buckets.set(compositeKey, {
        count: 1,
        resetAtMs: nowMs + rule.windowMs,
      });
      return {
        allowed: true,
        retryAfterSec: 0,
        remaining: Math.max(0, rule.maxRequests - 1),
      };
    }

    if (existing.count >= rule.maxRequests) {
      const retryAfterSec = Math.max(
        1,
        Math.ceil((existing.resetAtMs - nowMs) / 1000),
      );
      return { allowed: false, retryAfterSec, remaining: 0 };
    }

    existing.count += 1;
    return {
      allowed: true,
      retryAfterSec: 0,
      remaining: Math.max(0, rule.maxRequests - existing.count),
    };
  }

  reset(): void {
    this.buckets.clear();
  }
}

/**
 * Antrean & semaphore konkurensi untuk simulasi sandbox (/v1/ships/:id/rules/simulate):
 * Maksimal 2 simulasi aktif paralel dan antrean maksimal 10; selebihnya ditolak 503 BUSY (docs/08).
 */
export class SandboxConcurrencyQueue {
  private activeCount = 0;
  private readonly waitQueue: Array<() => void> = [];

  constructor(
    private readonly maxConcurrent: number = 2,
    private readonly maxQueue: number = 10,
  ) {}

  async run<T>(task: () => Promise<T> | T): Promise<T> {
    if (this.activeCount >= this.maxConcurrent) {
      if (this.waitQueue.length >= this.maxQueue) {
        const busyErr = new Error(
          'Antrean simulasi sandbox penuh. Silakan coba beberapa saat lagi.',
        ) as Error & { code?: string };
        busyErr.code = 'BUSY';
        throw busyErr;
      }
      await new Promise<void>((resolve) => {
        this.waitQueue.push(resolve);
      });
    }

    this.activeCount += 1;
    try {
      return await task();
    } finally {
      this.activeCount -= 1;
      const next = this.waitQueue.shift();
      if (next) {
        next();
      }
    }
  }
}
