import { test, expect } from '@playwright/test';

test('eShop full checkout flow', async ({ page }) => {
  // ── Step 1: Login as Alice ────────────────────────────────────────────────
  // Catalog is public — click the LOGIN link to trigger the identity redirect
  await page.goto('/');
  await page.waitForSelector('text=LOGIN', { timeout: 15_000 });
  await page.click('text=LOGIN');
  await page.waitForURL(/\/identity\/account\/login/i, { timeout: 30_000 });

  await page.getByLabel('Username').fill('alice');
  await page.getByLabel('Password').fill('Pass123$');
  await page.getByRole('button', { name: 'Login' }).click();

  // After OIDC callback the MVC app sometimes returns 502 transiently.
  // Wait for any navigation to settle, then recover by going to /catalog.
  await page.waitForLoadState('load', { timeout: 15_000 }).catch(() => {});
  if (page.url().includes('502') || (await page.title()).includes('502')) {
    await page.goto('/catalog');
  }

  await expect(page.locator('.esh-identity-name')).toContainText('AliceSmith@email.com', { timeout: 20_000 });

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
