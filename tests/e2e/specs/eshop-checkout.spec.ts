import { test, expect } from '@playwright/test';

test('eShop full checkout flow', async ({ page }) => {
  // ── Step 1: Login as Alice ────────────────────────────────────────────────
  await page.goto(
    '/identity/account/login' +
      '?ReturnUrl=%2Fidentity%2Fconnect%2Fauthorize%2Fcallback' +
      '%3Fclient_id%3Dmvc%26redirect_uri%3Dhttps%253A%252F%252F' +
      (process.env.BASE_URL ?? 'dev.jan26-group6-eshoponcontainers.abrdns.com')
        .replace(/^https?:\/\//, '') +
      '%252Fsignin-oidc%26response_type%3Dcode%2520id_token' +
      '%26scope%3Dopenid%2520profile%2520orders%2520basket%2520webshoppingagg%2520webhooks' +
      '%26response_mode%3Dform_post%26nonce%3Dtest123%26state%3Dtest456',
  );

  await page.fill('#Input_Email', 'alice');
  await page.fill('#Input_Password', 'Pass123$');
  await page.click('button[type="submit"]');

  // If redirect hit an error page, drive the authorize endpoint directly
  const currentUrl = page.url();
  if (currentUrl.includes('error') || currentUrl.includes('502') || currentUrl.includes('signin-oidc')) {
    // Already handled by OIDC callback – just navigate to catalog
  } else if (!currentUrl.includes('/catalog') && !currentUrl.includes('webmvc')) {
    await page.goto('/catalog');
  }

  await page.waitForSelector('.esh-identity-name', { timeout: 30_000 });
  await expect(page.locator('.esh-identity-name')).toContainText('AliceSmith@email.com');

  // ── Step 2: Verify catalog ────────────────────────────────────────────────
  await page.waitForSelector('.esh-catalog-item', { timeout: 30_000 });
  const items = page.locator('.esh-catalog-item');
  await expect(items).toHaveCount(12);

  for (let i = 0; i < 12; i++) {
    const img = items.nth(i).locator('img');
    await expect(img).toHaveAttribute('src', /.+/);
  }

  // ── Step 3: Add first 3 items to cart ────────────────────────────────────
  for (let i = 0; i < 3; i++) {
    const item = items.nth(i);
    await item.hover();
    await item.locator('.esh-catalog-button').click();
    // Small wait to let the cart badge update between clicks
    await page.waitForTimeout(500);
  }

  const cartBadge = page.locator('.esh-basket-badge, .esh-catalog-items-count');
  await expect(cartBadge).toHaveText('3', { timeout: 15_000 });

  // ── Step 4: Open basket and verify ───────────────────────────────────────
  await page.locator('.esh-basket-section').click();
  await page.waitForSelector('.esh-basket-items', { timeout: 15_000 });

  const basketRows = page.locator('.esh-basket-items .esh-basket-row, .esh-basket-items tr.esh-basket-row');
  await expect(basketRows).toHaveCount(3);

  const total = page.locator('.esh-basket-total');
  await expect(total).toContainText('$40.00', { timeout: 10_000 });

  // ── Step 5: Proceed to checkout ──────────────────────────────────────────
  await page.locator('a.esh-basket-checkout, button.esh-basket-checkout').click();
  await page.waitForSelector('form', { timeout: 30_000 });

  // ── Step 6: Update card expiration date ──────────────────────────────────
  const expiryField = page.locator('[name="card_expiration"], #card_expiration');
  await expiryField.clear();
  await expiryField.type('12/28');

  // ── Step 7: Place order ───────────────────────────────────────────────────
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('button')).find(
      (b) => b.textContent?.trim() === 'Place Order',
    ) as HTMLButtonElement | undefined;
    if (!btn) throw new Error('Place Order button not found');
    btn.click();
  });

  await page.waitForURL('**/orders', { timeout: 60_000 });

  // ── Step 8: Poll for paid status (up to 2 minutes) ───────────────────────
  const deadline = Date.now() + 120_000;
  let orderPaid = false;

  while (Date.now() < deadline) {
    const statuses = await page.locator('.esh-orders-status, td.esh-orders-items-status').allTextContents();
    if (statuses.some((s) => s.toLowerCase().includes('paid'))) {
      orderPaid = true;
      break;
    }
    await page.waitForTimeout(15_000);
    await page.reload();
  }

  expect(orderPaid, 'Expected at least one order with status "paid"').toBe(true);
});
