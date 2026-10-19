import { WorldEconomyConfig } from '@jalur-rempah/shared';

export type BotStrategyName =
  | 'adversarial'
  | 'naive'
  | 'margin_hunter'
  | 'hoarder'
  | 'random';

export interface SimulationOptions {
  readonly ticks: number;
  readonly bots: number;
  readonly seed: number;
  readonly config?: WorldEconomyConfig;
  readonly sampleCount?: number;
}

export interface CommodityMetrics {
  readonly commodityId: number;
  readonly code: string;
  readonly basePrice: number;
  readonly minBoundPrice: number;
  readonly maxBoundPrice: number;
  readonly meanPrice: number;
  readonly stdDevPrice: number;
  readonly volatilityPct: number;
  readonly minObservedPrice: number;
  readonly maxObservedPrice: number;
  readonly pctTicksAtLowerBound: number;
  readonly pctTicksAtUpperBound: number;
  readonly pctTicksAtBounds: number;
}

export interface StrategyMetrics {
  readonly strategy: BotStrategyName;
  readonly botCount: number;
  readonly totalWealth: string;
  readonly avgWealth: number;
  readonly wealthSharePct: number;
  readonly bankruptCount: number;
  readonly tradesCompleted: number;
  readonly avgMarginPerTx: number;
  readonly avgTicksToDoubleCoins: number | null;
}

export interface RouteMarginMetrics {
  readonly routeKey: string;
  readonly fromPort: string;
  readonly toPort: string;
  readonly ticks: number;
  readonly tripsCompleted: number;
  readonly avgNetProfitPerTrip: number;
  readonly avgNetProfitPerTick: number;
}

export interface AdversarialMetrics {
  readonly cycleAttempts: number;
  readonly roundingAttempts: number;
  readonly pumpDumpAttempts: number;
  readonly rescueFarmingAttempts: number;
  readonly totalExploitAttempts: number;
  readonly profitableExploitsFound: number;
  readonly bestCycleNetDeltaCoins: string;
  readonly worstCycleNetDeltaCoins: string;
}

export interface MoneyConservationReport {
  readonly valid: boolean;
  readonly totalInitialPlayerCoins: string;
  readonly totalInitialPortTreasury: string;
  readonly totalInitialMoney: string;
  readonly cumulativeSource: string;
  readonly cumulativePortIncomeSource: string;
  readonly cumulativeRescueSource: string;
  readonly finalPlayerCoins: string;
  readonly finalPortTreasury: string;
  readonly cumulativeUpkeepSink: string;
  readonly cumulativeShipUpkeepSink: string;
  readonly cumulativePortProducerPayoutSink: string;
  readonly lhsTotalAccounted: string;
  readonly rhsTotalExpected: string;
}

export interface PortTreasuryStats {
  readonly portCode: string;
  readonly initialTreasury: string;
  readonly finalTreasury: string;
  readonly minTreasury: string;
  readonly minTreasuryTick: number;
  readonly maxTreasury: string;
  readonly meanTreasury: number;
  readonly firstZeroTick: number | null;
}

export interface TimeSeriesSample {
  readonly tick: number;
  readonly totalPlayerCoins: string;
  readonly totalPortTreasury: string;
  readonly portTreasuries: Readonly<Record<string, string>>;
  readonly meanPriceByCommodity: Readonly<Record<string, number>>;
}

export interface PlayerCoinsStabilityReport {
  readonly q3MeanCoins: number;
  readonly q4MeanCoins: number;
  readonly relativeDriftPct: number;
  readonly maxAllowedDriftPct: number;
  readonly isStable: boolean;
}

export interface SkillGradientReport {
  readonly naiveAvgWealth: number;
  readonly bestSmartStrategy: BotStrategyName;
  readonly bestSmartAvgWealth: number;
  readonly skillGradientRatio: number;
}

export interface SimulationGateReport {
  readonly passed: boolean;
  readonly failedGates: readonly string[];
}

export interface SimulationResult {
  readonly seed: number;
  readonly ticks: number;
  readonly bots: number;
  readonly stateHash: string;
  readonly invariantViolations: number;
  readonly invariantViolationDetails: readonly string[];
  readonly giniWealth: number;
  readonly bankruptBotCount: number;
  readonly bankruptBotPct: number;
  readonly permanentlyDeadBotCount: number;
  readonly rescueGrantedTotal: number;
  readonly maxStrategyWealthSharePct: number;
  readonly dominantStrategy: BotStrategyName;
  readonly overallPctTicksAtBounds: number;
  readonly maxCommodityPctTicksAtBounds: number;
  readonly minPortTreasuryCoins: string;
  readonly minPortTreasuryPort: string;
  readonly minPortTreasuryTick: number;
  readonly skillGradient: SkillGradientReport;
  readonly playerCoinsStability: PlayerCoinsStabilityReport;
  readonly gates: SimulationGateReport;
  readonly moneyConservation: MoneyConservationReport;
  readonly portTreasuries: Readonly<Record<string, string>>;
  readonly portTreasuryStats: Readonly<Record<string, PortTreasuryStats>>;
  readonly commodityMetrics: readonly CommodityMetrics[];
  readonly strategyMetrics: readonly StrategyMetrics[];
  readonly routeMargins: readonly RouteMarginMetrics[];
  readonly adversarial: AdversarialMetrics;
  readonly timeSeriesSamples: readonly TimeSeriesSample[];
}
