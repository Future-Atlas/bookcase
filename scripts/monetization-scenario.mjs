import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Approved *future* plan list prices, tax-inclusive JPY.
// No paid checkout is enabled by this offline model.
export const PRICES_GROSS_YEN = Object.freeze({
  plusMonthly: 300,
  plusAnnual: 3000,
  premiumMonthly: 550,
  premiumAnnual: 5000,
});

const PLAN_PERIOD_MONTHS = Object.freeze({
  plusMonthly: 1,
  plusAnnual: 12,
  premiumMonthly: 1,
  premiumAnnual: 12,
});

const PLAN_KEYS = Object.keys(PRICES_GROSS_YEN);
const SHARE_KEYS = [...PLAN_KEYS, 'activeTrialShare'];

function numberField(obj, field, { integer = false, max = Infinity } = {}) {
  const value = obj[field];
  if (typeof value !== 'number' || !Number.isFinite(value) ||
      value < 0 || value > max || (integer && !Number.isSafeInteger(value))) {
    throw new TypeError(field + ' must be a finite non-negative ' +
      (integer ? 'safe integer' : 'number') + (Number.isFinite(max) ? ' <= ' + max : ''));
  }
  return value;
}

function round(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function estimateMonthlyRevenue(config) {
  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    throw new TypeError('Provide a scenario JSON object');
  }
  const shares = config.subscriberShares;
  if (!shares || typeof shares !== 'object' || Array.isArray(shares)) {
    throw new TypeError('subscriberShares must be an object of monthly active user shares');
  }
  const mau = numberField(config, 'monthlyActiveUsers', { integer: true });
  const paidRates = Object.fromEntries(
    PLAN_KEYS.map((key) => [key, numberField(shares, key, { max: 1 })]),
  );
  const trialRate = numberField(config, 'activeTrialShare', { max: 1 });
  const paidRate = Object.values(paidRates).reduce((sum, value) => sum + value, 0);
  if (paidRate + trialRate > 1 + 1e-12) {
    throw new RangeError('Paid subscriber and trial shares cannot exceed 100% of MAU');
  }
  const freeRate = Math.max(0, 1 - paidRate - trialRate);

  const visits = numberField(config, 'homeVisitsPerFreeUserPerMonth');
  const slots = numberField(config, 'possibleAdSlotsPerHomeVisit');
  const readyRate = numberField(config, 'inventoryReadyRate', { max: 1 });
  const blockRate = numberField(config, 'adBlockRate', { max: 1 });
  const fillRate = numberField(config, 'fillRate', { max: 1 });
  const billableRate = numberField(config, 'billableRate', { max: 1 });
  const ecpm = numberField(config, 'publisherNetEcpmYen');

  const taxRate = numberField(config, 'consumptionTaxRate', { max: 1 });
  const feeRate = numberField(config, 'processorFeeRate', { max: 1 });
  const fixedFee = numberField(config, 'processorFixedYenPerPayment');
  const refundRate = numberField(config, 'refundRate', { max: 1 });
  const fixedCosts = numberField(config, 'fixedMonthlyCostsYen');
  const variableCostsPerMau = numberField(config, 'variableMonthlyCostsPerMauYen');

  // Annual subscriptions are allocated evenly for monthly contribution analysis.
  // This does not represent the actual month of annual cash collection or refunds.
  const subscriptionGrossPerMau = PLAN_KEYS.reduce(
    (sum, key) => sum + paidRates[key] * PRICES_GROSS_YEN[key] / PLAN_PERIOD_MONTHS[key],
    0,
  );
  const monthlyPaymentCountPerMau = PLAN_KEYS.reduce(
    (sum, key) => sum + paidRates[key] / PLAN_PERIOD_MONTHS[key],
    0,
  );
  const subscriptionsExTaxPerMau = subscriptionGrossPerMau / (1 + taxRate);
  const feePerMau = subscriptionGrossPerMau * feeRate +
    monthlyPaymentCountPerMau * fixedFee;
  const refundsPerMau = subscriptionsExTaxPerMau * refundRate;
  const subscriptionNetPerMau = subscriptionsExTaxPerMau - refundsPerMau - feePerMau;

  // Payout impressions are explicitly modeled; MAU is NOT ad reach.
  const adOpportunitiesPerMau = freeRate * visits * slots * readyRate;
  const billableImpressionsPerMau = adOpportunitiesPerMau *
    (1 - blockRate) * fillRate * billableRate;
  const advertisingRevenuePerMau = billableImpressionsPerMau / 1000 * ecpm;

  const unitContributionYen = subscriptionNetPerMau +
    advertisingRevenuePerMau - variableCostsPerMau;
  const monthlyOperatingCosts = fixedCosts + mau * variableCostsPerMau;
  const monthlyNetResult = mau *
    (subscriptionNetPerMau + advertisingRevenuePerMau) - monthlyOperatingCosts;

  // The threshold assumes subscriber mix and visit rates remain unchanged
  // as MAU grows. It is not a growth or revenue forecast.
  const breakEvenMau = fixedCosts === 0
    ? 0
    : unitContributionYen > 0
      ? Math.ceil(fixedCosts / unitContributionYen)
      : null;

  return {
    label: config.scenarioName ?? 'Unnamed hypothetical scenario',
    warning: 'Scenario only: not measured traffic, realized ad payout, or an accounting forecast.',
    monthlyActiveUsers: mau,
    audienceShares: {
      free: round(freeRate),
      trial: round(trialRate),
      paid: round(paidRate),
    },
    monthlyPlanGrossYen: round(subscriptionGrossPerMau * mau),
    monthlyPlanExTaxYen: round(subscriptionsExTaxPerMau * mau),
    estimatedPaymentProcessingYen: round(feePerMau * mau),
    estimatedRefundExTaxYen: round(refundsPerMau * mau),
    subscriptionNetYen: round(subscriptionNetPerMau * mau),
    adOpportunities: round(adOpportunitiesPerMau * mau),
    billableAdImpressions: round(billableImpressionsPerMau * mau),
    estimatedAdPublisherPayoutYen: round(advertisingRevenuePerMau * mau),
    monthlyOperatingCostsYen: round(monthlyOperatingCosts),
    estimatedMonthlyProfitYen: round(monthlyNetResult),
    unitContributionYenPerMau: round(unitContributionYen),
    breakEvenMau,
  };
}

async function main() {
  if (process.argv.length !== 3 || process.argv[2] === '--help') {
    process.stdout.write('Usage: node scripts/monetization-scenario.mjs <scenario.json>\n');
    process.exitCode = process.argv[2] === '--help' ? 0 : 2;
    return;
  }
  const raw = await readFile(resolve(process.argv[2]), 'utf8');
  const result = estimateMonthlyRevenue(JSON.parse(raw));
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    process.stderr.write('Scenario error: ' + error.message + '\n');
    process.exitCode = 1;
  });
}
