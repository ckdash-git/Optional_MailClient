const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1360, height: 960 }, deviceScaleFactor: 1 });
  for (const k of 'ABC') { await p.goto('file://' + process.cwd() + `/direction-${k}.html`); await p.waitForTimeout(300); await p.screenshot({ path: `direction-${k}.png` }); }
  await b.close();
})();
