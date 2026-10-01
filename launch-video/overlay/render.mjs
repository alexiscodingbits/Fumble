// Renders overlay.html to transparent ProRes 4444 clips for DaVinci Resolve, plus an MP4 preview
// of each over the video frame.
//
//   node render.mjs                 all four options, 30fps, 1920x1080
//   node render.mjs a c --fps 24    just A and C, at 24fps
//   node render.mjs --scale 2       3840x2160, for a 4K timeline
//   node render.mjs --serve         live preview at http://localhost:4173
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import url from 'node:url';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(name);
  return i === -1 ? fallback : argv[i + 1];
};
const fps = Number(flag('--fps', 30));
const scale = Number(flag('--scale', 1));
const versions = argv.filter((a, i) => /^[a-d]$/.test(a) && !argv[i - 1]?.startsWith('--'));
const DURATION = 12;

// A tiny static server, so the page can load the system SF Mono (Chrome won't read a font
// straight off disk from a file:// page).
const server = http.createServer((req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = p === '/__sfmono.ttf' ? '/System/Library/Fonts/SFNSMono.ttf' : path.join(here, p === '/' ? 'overlay.html' : p);
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    const type = { '.html': 'text/html', '.png': 'image/png', '.ttf': 'font/ttf' }[path.extname(file)] ?? 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': type }); res.end(data);
  });
});
await new Promise(r => server.listen(4173, r));

if (argv.includes('--serve')) {
  console.log('Preview: http://localhost:4173/overlay.html  (Ctrl-C to stop)');
} else {
  const out = path.join(here, 'renders');
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ channel: 'chrome' });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: scale });

  for (const v of versions.length ? versions : ['a', 'b', 'c', 'd']) {
    await page.goto(`http://localhost:4173/overlay.html?v=${v}&render=1`);
    await page.evaluate(() => document.fonts.ready);
    const frames = fs.mkdtempSync(path.join(os.tmpdir(), `fumble-overlay-${v}-`));
    const count = Math.round(DURATION * fps);
    for (let i = 0; i < count; i++) {
      await page.evaluate(t => window.renderAt(t), i / fps);
      await page.screenshot({ path: path.join(frames, `${String(i).padStart(4, '0')}.png`), omitBackground: true });
    }

    const mov = path.join(out, `fumble-overlay-${v}.mov`);
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(fps), '-i', path.join(frames, '%04d.png'),
      '-c:v', 'prores_ks', '-profile:v', '4444', '-pix_fmt', 'yuva444p10le', '-vendor', 'apl0', mov]);

    const w = 1920 * scale, h = 1080 * scale;
    const mp4 = path.join(out, `preview-${v}.mp4`);
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-loop', '1', '-framerate', String(fps), '-i', path.join(here, 'preview-bg.png'), '-i', mov,
      '-filter_complex', `[0]scale=${w}:${h}[bg];[bg][1]overlay=shortest=1`, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', mp4]);

    fs.rmSync(frames, { recursive: true, force: true });
    console.log(`${v}: ${path.relative(here, mov)}  +  ${path.relative(here, mp4)}`);
  }
  await browser.close();
  server.close();
}
