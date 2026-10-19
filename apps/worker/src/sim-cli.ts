import fs from 'node:fs';
import { runEconomySimulation, SimulationResult } from '@jalur-rempah/econ';

interface CliArgs {
  ticks: number;
  bots: number;
  seeds: number[];
  outFile?: string;
}

function parseArgs(argv: readonly string[]): CliArgs {
  let ticks = 10000;
  let bots = 50;
  const seeds: number[] = [];
  let outFile: string | undefined;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = argv[i + 1];
    if (arg === '--ticks' && next) {
      ticks = Number.parseInt(next, 10);
      i++;
    } else if (arg === '--bots' && next) {
      bots = Number.parseInt(next, 10);
      i++;
    } else if (arg === '--seed' && next) {
      for (const part of next.split(',')) {
        const parsed = Number.parseInt(part.trim(), 10);
        if (!Number.isNaN(parsed)) seeds.push(parsed);
      }
      i++;
    } else if (arg === '--out' && next) {
      outFile = next;
      i++;
    }
  }

  if (seeds.length === 0) {
    seeds.push(1);
  }

  return {
    ticks,
    bots,
    seeds,
    ...(outFile !== undefined ? { outFile } : {}),
  };
}

function main(): void {
  const args = parseArgs(process.argv.slice(2));
  const runs: SimulationResult[] = [];
  let hasFailure = false;

  for (const seed of args.seeds) {
    const result = runEconomySimulation({
      ticks: args.ticks,
      bots: args.bots,
      seed,
    });

    // Verifikasi determinisme untuk run <= 20.000 tick
    if (args.ticks <= 20000) {
      const verifyDeterminism = runEconomySimulation({
        ticks: args.ticks,
        bots: args.bots,
        seed,
      });

      if (result.stateHash !== verifyDeterminism.stateHash) {
        console.error(
          `[SIM-ERROR] Pelanggaran determinisme pada seed ${seed}: ${result.stateHash} !== ${verifyDeterminism.stateHash}`,
        );
        hasFailure = true;
      }
    }

    if (!result.gates.passed) {
      console.error(
        `[SIM-GATE-FAILED] Seed ${seed} gagal pada gerbang: ${result.gates.failedGates.join('; ')}`,
      );
      hasFailure = true;
    }

    runs.push(result);
  }

  const outputPayload = args.seeds.length === 1 ? runs[0] : { runs };
  const jsonString = JSON.stringify(outputPayload, null, 2);
  console.log(jsonString);

  if (args.outFile) {
    fs.writeFileSync(args.outFile, jsonString, 'utf-8');
  }

  if (hasFailure) {
    console.error(
      '[SIM-ERROR] Satu atau lebih gerbang invarian/kualitas simulasi gagal.',
    );
    process.exit(1);
  }
}

main();
