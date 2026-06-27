import { chromium } from "playwright";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const htmlPath = join(here, "mockups.html");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({
  viewport: { width: 1560, height: 1120 },
  deviceScaleFactor: 1,
});

await page.goto(`file://${htmlPath}`, { waitUntil: "networkidle" });
await page.screenshot({
  path: join(here, "all-mockups.png"),
  fullPage: true,
});

const sections = await page.locator("section[data-shot]").elementHandles();
for (const section of sections) {
  const shot = await section.getAttribute("data-shot");
  if (!shot) continue;
  await section.screenshot({
    path: join(here, `${shot}.png`),
  });
}

await browser.close();
