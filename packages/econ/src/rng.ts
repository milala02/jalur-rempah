export interface SeededRng {
  nextUint32(): number;
  nextFloat(): number;
  nextInt(minInclusive: number, maxInclusive: number): number;
}

function hashSeedToUint32(seed: number | string): number {
  if (typeof seed === 'number') {
    const intSeed = seed | 0;
    return intSeed === 0 ? 0x6d2b79f5 : intSeed >>> 0;
  }
  let h = 2166136261 >>> 0;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h === 0 ? 0x6d2b79f5 : h >>> 0;
}

export function createSeededRng(seed: number | string): SeededRng {
  let state = hashSeedToUint32(seed);

  const nextUint32 = (): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return (t ^ (t >>> 14)) >>> 0;
  };

  const nextFloat = (): number => {
    return nextUint32() / 4294967296;
  };

  const nextInt = (minInclusive: number, maxInclusive: number): number => {
    if (maxInclusive <= minInclusive) {
      return minInclusive;
    }
    const span = maxInclusive - minInclusive + 1;
    return minInclusive + (nextUint32() % span);
  };

  return {
    nextUint32,
    nextFloat,
    nextInt,
  };
}
