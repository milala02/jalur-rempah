import { describe, it, expect } from 'vitest';
import { runEconomySimulation } from '../src/index.js';

describe('M1 — packages/econ: Simulator Determinisme, Bot Adversarial, & Invarian', () => {
  it('1. Determinisme penuh: seed yang sama menghasilkan stateHash dan metrik yang 100% identik di 2 kali jalan', () => {
    const run1 = runEconomySimulation({
      ticks: 500,
      bots: 20,
      seed: 42,
    });
    const run2 = runEconomySimulation({
      ticks: 500,
      bots: 20,
      seed: 42,
    });

    expect(run1.stateHash).toBe(run2.stateHash);
    expect(run1.invariantViolations).toBe(0);
    expect(run2.invariantViolations).toBe(0);
    expect(run1.moneyConservation.valid).toBe(true);
    expect(run1.adversarial.profitableExploitsFound).toBe(0);
    expect(run1.adversarial.cycleAttempts).toBeGreaterThan(0);
  });

  it('2. Seed berbeda menghasilkan simulasi berbeda tetapi tetap 0 pelanggaran invarian dan 0 eksploit adversarial', () => {
    const runA = runEconomySimulation({
      ticks: 1000,
      bots: 15,
      seed: 101,
    });
    const runB = runEconomySimulation({
      ticks: 1000,
      bots: 15,
      seed: 202,
    });

    expect(runA.stateHash).not.toBe(runB.stateHash);
    expect(runA.invariantViolations).toBe(0);
    expect(runB.invariantViolations).toBe(0);
    expect(runA.adversarial.profitableExploitsFound).toBe(0);
    expect(runB.adversarial.profitableExploitsFound).toBe(0);
  });
});
