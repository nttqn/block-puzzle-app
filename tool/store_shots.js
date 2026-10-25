// Store screenshots for every device class, written to store/<device>/.
// Needs `flutter build web` served on :8877 (e.g. `npx http-server build/web
// -p 8877`) and playwright + pngjs resolvable (set NODE_PATH if installed
// elsewhere). Usage: node tool/store_shots.js [deviceName ...]
const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { PNG } = require('pngjs');

const STORE = path.join(__dirname, '..', 'store');
const DEVICES = [
  { dir: 'phone', w: 360, h: 720, dsf: 3 },
  { dir: 'tablet-7in', w: 600, h: 960, dsf: 2 },
  { dir: 'tablet-10in', w: 800, h: 1280, dsf: 2 },
  { dir: 'iphone-6.3in', w: 402, h: 874, dsf: 3 },
  { dir: 'ipad-13in', w: 1032, h: 1376, dsf: 2 },
];

const read = (p) => PNG.sync.read(fs.readFileSync(p));
const px = (png, x, y) => { const i = (png.width * y + x) << 2; return [png.data[i], png.data[i + 1], png.data[i + 2]]; };
const near = (c, t, tol) => Math.abs(c[0] - t[0]) <= tol && Math.abs(c[1] - t[1]) <= tol && Math.abs(c[2] - t[2]) <= tol;

// App Store Connect rejects screenshots with an alpha channel.
function saveRgb(src, dest) {
  const png = read(src);
  fs.writeFileSync(dest, PNG.sync.write(png, { colorType: 2, inputHasAlpha: true }));
}

// Home mode buttons: an x column with >= 2 long runs of the button fill.
function modeButtons(png, dsf) {
  const minRun = png.height * 0.03;
  for (let fx = 0.15; fx <= 0.5; fx += 0.01) {
    const x = Math.round(png.width * fx);
    const runs = [];
    let s = null;
    for (let y = Math.round(png.height * 0.3); y < png.height; y++) {
      if (near(px(png, x, y), [25, 28, 32], 6)) { if (s === null) s = y; }
      else if (s !== null) { if (y - s > minRun) runs.push([x / dsf, (s + y) / 2 / dsf]); s = null; }
    }
    if (runs.length >= 2) return runs;
  }
  throw new Error('mode buttons not found');
}

function boardBounds(png, dsf) {
  const cell = [35, 46, 61];
  const cx = Math.round(png.width / 2) + 3;
  let top = null, s = null;
  for (let y = 0; y < png.height && top === null; y++) {
    if (near(px(png, cx, y), cell, 4)) { if (s === null) s = y; if (y - s >= 10 * dsf) top = s; }
    else s = null;
  }
  const cy = top + 4 * dsf;
  let left = null, right = null;
  for (let x = 0; x < png.width; x++) if (near(px(png, x, cy), cell, 4)) { if (left === null) left = x; right = x; }
  // Square board; the power-up buttons below share the empty-cell color.
  return { top: top / dsf, left: left / dsf, bottom: (top + right - left) / dsf, cell: (right - left) / dsf / 12 };
}

function hammerY(png, dsf, boardBottom) {
  const x = Math.round(png.width / 2 + 17 * dsf);
  let s = null;
  for (let y = Math.round((boardBottom + 10) * dsf); y < png.height; y++) {
    if (near(px(png, x, y), [35, 46, 61], 6)) { if (s === null) s = y; }
    else if (s !== null) { if (y - s > 8 * dsf) return (s + y) / 2 / dsf; s = null; }
  }
  throw new Error('hammer button not found');
}

async function shoot(browser, { dir, w: W, h: H, dsf }) {
  const out = path.join(STORE, dir);
  fs.mkdirSync(out, { recursive: true });
  const tmp = path.join(os.tmpdir(), `bp_${dir}.png`);
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: dsf });
  const snap = async (name) => { await page.screenshot({ path: tmp }); saveRgb(tmp, path.join(out, name)); };
  const home = async () => {
    await page.goto('http://localhost:8877/', { waitUntil: 'load' });
    await page.waitForFunction(() => {
      const el = document.querySelector('flutter-view');
      return !!(el && el.shadowRoot && el.shadowRoot.querySelector('canvas'));
    }, { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(2500);
  };
  const drag = async (x1, y1, x2, y2) => {
    await page.mouse.move(x1, y1);
    await page.mouse.down();
    for (let k = 1; k <= 12; k++) await page.mouse.move(x1 + (x2 - x1) * k / 12, y1 + (y2 - y1) * k / 12);
    await page.mouse.up();
    await page.waitForTimeout(350);
  };
  const playMode = async (btn, targets) => {
    await page.mouse.click(btn[0], btn[1]);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: tmp });
    const png = read(tmp);
    const b = boardBounds(png, dsf);
    const hy = hammerY(png, dsf, b.bottom);
    const trayY = H - 12 - Math.min(2.75 * b.cell, W / 3) / 2;
    const slotX = [W / 6, W / 2, (5 * W) / 6];
    let i = 0;
    for (const [r, c] of targets) await drag(slotX[i++ % 3], trayY, b.left + (c + 0.5) * b.cell, b.top + (r + 0.5) * b.cell);
    await page.waitForTimeout(1300);
    return hy;
  };

  await home();
  await snap('01-home.png');
  const buttons = modeButtons(read(tmp), dsf);

  const hy = await playMode(buttons[0], [[10, 1], [10, 5], [10, 9], [8, 2], [8, 6], [8, 10], [11, 3], [11, 7], [6, 1], [6, 9], [9, 4], [9, 8], [7, 5], [5, 2], [5, 9]]);
  await snap('02-classic.png');
  await page.mouse.click(W / 2, hy);
  await page.waitForTimeout(600);
  await snap('03-hammer.png');

  await home();
  await playMode(buttons[1], [[10, 2], [10, 7], [8, 4], [8, 9], [11, 5], [6, 2], [9, 1], [7, 8]]);
  await snap('04-survival.png');

  await page.close();
  fs.unlinkSync(tmp);
  console.log(dir, 'done');
}

(async () => {
  const only = process.argv.slice(2);
  const browser = await chromium.launch();
  for (const d of DEVICES) if (!only.length || only.includes(d.dir)) await shoot(browser, d);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
