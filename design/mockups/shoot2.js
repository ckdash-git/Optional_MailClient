const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1840, height: 920 } });
  for (const k of ['R1','R2','R3']) { await p.goto('file://' + process.cwd() + `/round2-${k}.html`); await p.waitForTimeout(300); await p.screenshot({ path: `round2-${k}.png` }); }
  await b.close();
})();
