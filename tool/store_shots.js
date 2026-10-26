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
  // Google Play allows 8 screenshots per device type, the App Store 10.
  { dir: 'phone', w: 360, h: 720, dsf: 3, max: 8 },
  { dir: 'tablet-7in', w: 600, h: 960, dsf: 2, max: 8 },
  { dir: 'tablet-10in', w: 800, h: 1280, dsf: 2, max: 8 },
  { dir: 'iphone-6.3in', w: 402, h: 874, dsf: 3, max: 10 },
  { dir: 'ipad-13in', w: 1032, h: 1376, dsf: 2, max: 10 },
];

const read = (p) => PNG.sync.read(fs.readFileSync(p));
const px = (png, x, y) => { const i = (png.width * y + x) << 2; return [png.data[i], png.data[i + 1], png.data[i + 2]]; };
const near = (c, t, tol) => Math.abs(c[0] - t[0]) <= tol && Math.abs(c[1] - t[1]) <= tol && Math.abs(c[2] - t[2]) <= tol;

// App Store Connect rejects screenshots with an alpha channel.
function saveRgb(src, dest) {
  const png = read(src);
  fs.writeFileSync(dest, PNG.sync.write(png, { colorType: 2, inputHasAlpha: true }));
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

// Preset scenes come from lib/debug/screenshot_scenarios.dart (?shot=...).
// drag: [traySlot, row, col] — row/col of the piece's center cell.
const SCENES = [
  { file: '01-home', shot: '' },
  { file: '02-classic', shot: 'classic' },
  { file: '03-combo', shot: 'combo', drag: [1, 10.5, 4], after: 380 },
  { file: '04-hammer', shot: 'hammer', hammer: true },
  { file: '05-survival', shot: 'survival' },
  { file: '06-game-over', shot: 'gameover', drag: [0, 6, 6], after: 900 },
  // Best seeded just under the scene's score so the drag beats it mid-run.
  { file: '07-new-best', shot: 'combo', best: 990, drag: [1, 10.5, 4], after: 1300 },
  { file: '08-bomb-countdown', shot: 'urgent' },
  { file: '09-how-to-play', shot: 'howto' },
  { file: '10-combo-x3', shot: 'combo3', drag: [0, 10, 7], after: 380 },
];

async function shoot(browser, { dir, w: W, h: H, dsf, max }) {
  const out = path.join(STORE, dir);
  fs.mkdirSync(out, { recursive: true });
  for (const f of fs.readdirSync(out)) if (f.endsWith('.png')) fs.unlinkSync(path.join(out, f));
  const tmp = path.join(os.tmpdir(), `bp_${dir}.png`);
  const context = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: dsf });
  await context.addInitScript(() => {
    const best = location.search.match(/best=(\d+)/);
    localStorage.setItem('flutter.best_score_classic', best ? best[1] : '2860');
    localStorage.setItem('flutter.best_score_survival', '1450');
  });
  const page = await context.newPage();
  const load = async (shot, best) => {
    const q = [shot && `shot=${shot}`, best && `best=${best}`].filter(Boolean).join('&');
    await page.goto(`http://localhost:8877/${q ? `?${q}` : ''}`, { waitUntil: 'load' });
    await page.waitForSelector('flutter-view', { timeout: 30000 });
    // Covers engine boot, the scenario's route push and its transition.
    await page.waitForTimeout(3500);
  };

  // Board/tray/button positions, measured once on the classic scene (its
  // top row is empty, which boardBounds needs).
  await load('classic');
  await page.screenshot({ path: tmp });
  const png = read(tmp);
  const b = boardBounds(png, dsf);
  const hy = hammerY(png, dsf, b.bottom);
  const trayY = H - 12 - Math.min(2.75 * b.cell, W / 3) / 2;
  const slotX = [W / 6, W / 2, (5 * W) / 6];

  for (const s of SCENES.slice(0, max)) {
    await load(s.shot, s.best);
    if (s.hammer) {
      await page.mouse.click(W / 2, hy);
      await page.waitForTimeout(600);
    }
    if (s.drag) {
      const [slot, r, c] = s.drag;
      const [x1, y1, x2, y2] = [slotX[slot], trayY, b.left + (c + 0.5) * b.cell, b.top + (r + 0.5) * b.cell];
      await page.mouse.move(x1, y1);
      await page.mouse.down();
      for (let k = 1; k <= 12; k++) await page.mouse.move(x1 + (x2 - x1) * k / 12, y1 + (y2 - y1) * k / 12);
      await page.mouse.up();
      await page.waitForTimeout(s.after);
    }
    await page.screenshot({ path: tmp });
    saveRgb(tmp, path.join(out, `${s.file}.png`));
  }

  await context.close();
  fs.unlinkSync(tmp);
  console.log(dir, 'done');
}

(async () => {
  const only = process.argv.slice(2);
  const browser = await chromium.launch();
  for (const d of DEVICES) if (!only.length || only.includes(d.dir)) await shoot(browser, d);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
