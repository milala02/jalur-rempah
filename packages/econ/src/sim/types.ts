import { WorldEconomyConfig } from '@jalur-rempah/shared';

export type BotStrategyName =
  | 'naive'
  | 'margin_hunter'
  | 'hoarder'
  | 'random'
  | 'adversarial';

export interface SimulationOptions {
  readonly ticks: number;
  readonly bots: number;
  readonly seed: number;
  readonly config?: WorldEconomyConfig;
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
  readonly finalPlayerCoins: string;
  readonly finalPortTreasury: string;
  readonly cumulativeUpkeepSink: string;
  readonly finalAccountedMoney: string;
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
  readonly maxStrategyWealthSharePct: number;
  readonly dominantStrategy: BotStrategyName;
  readonly overallPctTicksAtBounds: number;
  readonly moneyConservation: MoneyConservationReport;
  readonly portTreasuries: Readonly<Record<string, string>>;
  readonly commodityMetrics: readonly CommodityMetrics[];
  readonly strategyMetrics: readonly StrategyMetrics[];
  readonly routeMargins: readonly RouteMarginMetrics[];
  readonly adversarial: AdversarialMetrics;
}
