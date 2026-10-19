export interface RateLimitRule {
  readonly windowMs: number;
  readonly maxRequests: number;
}

export const RATE_LIMIT_GROUPS = {
  general: { windowMs: 60_000, maxRequests: 60 },
  auth: { windowMs: 60_000, maxRequests: 10 },
  putRules: { windowMs: 60_000, maxRequests: 10 },
  simulate: { windowMs: 5_000, maxRequests: 1 },
} as const;

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
  ): { allowed: boolean; retryAfterSec: number } {
    const compositeKey = `${group}:${key}`;
    const existing = this.buckets.get(compositeKey);

    if (!existing || nowMs >= existing.resetAtMs) {
      this.buckets.set(compositeKey, {
        count: 1,
        resetAtMs: nowMs + rule.windowMs,
      });
      return { allowed: true, retryAfterSec: 0 };
    }

    if (existing.count >= rule.maxRequests) {
      const retryAfterSec = Math.max(
        1,
        Math.ceil((existing.resetAtMs - nowMs) / 1000),
      );
      return { allowed: false, retryAfterSec };
    }

    existing.count += 1;
    return { allowed: true, retryAfterSec: 0 };
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
