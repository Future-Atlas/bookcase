const { test } = require('node:test');
const assert = require('node:assert/strict');

const modulePromise = import('../../scripts/monetization-scenario.mjs');
function input() {
  return {
    scenarioName: 'Unit test, not live data',
    monthlyActiveUsers: 100,
    subscriberShares: { plusMonthly: 0, plusAnnual: 0, premiumMonthly: 0, premiumAnnual: 0 },
    activeTrialShare: 0,
    homeVisitsPerFreeUserPerMonth: 0,
    possibleAdSlotsPerHomeVisit: 0,
    inventoryReadyRate: 1,
    adBlockRate: 0,
    fillRate: 1,
    billableRate: 1,
    publisherNetEcpmYen: 0,
    consumptionTaxRate: 0,
    processorFeeRate: 0,
    processorFixedYenPerPayment: 0,
    refundRate: 0,
    fixedMonthlyCostsYen: 0,
    variableMonthlyCostsPerMauYen: 0,
  };
}

test('approved future tax-inclusive Plus / Premium list prices remain unchanged', async () => {
  const { PRICES_GROSS_YEN } = await modulePromise;
  assert.deepEqual({ ...PRICES_GROSS_YEN }, {
    plusMonthly: 300, plusAnnual: 3000, premiumMonthly: 550, premiumAnnual: 5000,
  });
});

test('monthly subscriptions are recognized once with no fees at zero tax', async () => {
  const { estimateMonthlyRevenue } = await modulePromise;
  const data = input();
  data.subscriberShares.plusMonthly = 0.1;
  const result = estimateMonthlyRevenue(data);
  assert.equal(result.monthlyPlanGrossYen, 3000);
  assert.equal(result.subscriptionNetYen, 3000);
  assert.equal(result.estimatedMonthlyProfitYen, 3000);
  assert.equal(result.audienceShares.free, 0.9);
});

test('annual plans are monthly allocated and annual transaction fixed fees are prorated', async () => {
  const { estimateMonthlyRevenue } = await modulePromise;
  const data = input();
  data.monthlyActiveUsers = 120;
  data.subscriberShares.plusAnnual = 0.1;
  data.processorFixedYenPerPayment = 12;
  const result = estimateMonthlyRevenue(data);
  assert.equal(result.monthlyPlanGrossYen, 3000);
  assert.equal(result.estimatedPaymentProcessingYen, 12);
  assert.equal(result.subscriptionNetYen, 2988);
});

test('free users produce publisher payout only from modeled billable impressions', async () => {
  const { estimateMonthlyRevenue } = await modulePromise;
  const data = input();
  data.homeVisitsPerFreeUserPerMonth = 10;
  data.possibleAdSlotsPerHomeVisit = 2;
  data.inventoryReadyRate = 0.5;
  data.publisherNetEcpmYen = 1000;
  const result = estimateMonthlyRevenue(data);
  assert.equal(result.adOpportunities, 1000);
  assert.equal(result.billableAdImpressions, 1000);
  assert.equal(result.estimatedAdPublisherPayoutYen, 1000);
});

test('paid members and active-trial members are excluded from ad inventory', async () => {
  const { estimateMonthlyRevenue } = await modulePromise;
  const data = input();
  data.subscriberShares.premiumMonthly = 0.3;
  data.activeTrialShare = 0.2;
  data.homeVisitsPerFreeUserPerMonth = 1;
  data.possibleAdSlotsPerHomeVisit = 1;
  const result = estimateMonthlyRevenue(data);
  assert.equal(result.adOpportunities, 50);
  assert.equal(result.audienceShares.free, 0.5);
});

test('fixed costs and unit contribution determine an explicit break-even MAU', async () => {
  const { estimateMonthlyRevenue } = await modulePromise;
  const data = input();
  data.subscriberShares.plusMonthly = 0.1; // 30 JPY recognized gross per MAU
  data.variableMonthlyCostsPerMauYen = 5;
  data.fixedMonthlyCostsYen = 1000;
  const result = estimateMonthlyRevenue(data);
  assert.equal(result.unitContributionYenPerMau, 25);
  assert.equal(result.breakEvenMau, 40);
  assert.equal(result.estimatedMonthlyProfitYen, 1500);
});

test('zero contribution with fixed costs makes break-even impossible under assumptions', async () => {
  const { estimateMonthlyRevenue } = await modulePromise;
  const data = input();
  data.fixedMonthlyCostsYen = 100;
  assert.equal(estimateMonthlyRevenue(data).breakEvenMau, null);
});

test('invalid shares, negative costs and non-finite inputs fail closed', async () => {
  const { estimateMonthlyRevenue } = await modulePromise;
  const cases = [
    (o) => { o.subscriberShares.plusMonthly = 0.7; o.subscriberShares.plusAnnual = 0.6; },
    (o) => { o.activeTrialShare = 1.1; },
    (o) => { o.monthlyActiveUsers = -1; },
    (o) => { o.monthlyActiveUsers = 3.5; },
    (o) => { o.fillRate = NaN; },
    (o) => { o.fixedMonthlyCostsYen = -1; },
  ];
  for (const edit of cases) {
    const data = input();
    edit(data);
    assert.throws(() => estimateMonthlyRevenue(data));
  }
});
