import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  // Frontend contract fixture only. Native installer/baker checks run separately.
  await page.addInitScript(() => {
    window.requests = [];
    let id = 0;
    window.__TAURI_INTERNALS__ = {
      transformCallback: () => ++id,
      invoke: async (command, args) => {
        if (command === 'plugin:event|listen') return 1;
        if (command === 'bootstrap') return {
          bundleRoot: 'C:\\Smoke Tool', rememberedGame: '',
          candidates: [{path:'C:\\Games\\Steam\\steamapps\\common\\Call of Duty 2',source:'Steam library',steam:true,installed:false},
            {path:'C:\\Games\\Call of Duty 2',source:'Game folder',steam:false,installed:true}],
          suggestedOutput:'C:\\Maps\\smoke-output', bakerAvailable:!window.playerOnly,
        };
        if (command === 'pick_path') return args.kind === 'maps' ? ['C:\\Maps\\mp_example.d3dbsp'] : [];
        if (command === 'inspect_game') return {ready: !window.missingCoD2x, message: window.missingCoD2x ?
          'CoD2x is not installed in this folder. Install CoD2x first, then click Recheck.' :
          'CoD2x detected. Your current client will be backed up before smoke is installed.'};
        if (command === 'run_job') {
          window.requests.push(args.request);
          await new Promise(resolve => setTimeout(resolve, 150));
          if (window.failNext) { window.failNext = false; throw 'Unsupported DX9 renderer. No game files were changed.'; }
          return { message: args.request.action === 'trySmoke' ? 'Smoke launched.' : 'Checks passed.',
            outputs: args.request.action === 'bake' ? ['C:\\Maps\\smoke-output\\mp_example\\mapkit_smoke_mp_example.iwd'] : [] };
        }
        throw new Error('Unexpected command: ' + command);
      },
    };
  });
  await page.goto('/');
  await expect(page.getByRole('status')).toContainText('Ready.');
});

test('one click Try smoke auto-selects Steam and recovers from compatibility errors', async ({ page }, info) => {
  await expect(page.getByRole('heading', {name:'CoD2 Smoke',exact:true})).toBeVisible();
  await page.screenshot({path:info.outputPath('setup.png'),fullPage:true});
  const tryButton = page.getByRole('button', {name:'Try smoke',exact:true});
  await expect(page.getByRole('button', {name:'Check compatibility'})).not.toBeVisible();
  await expect(page.getByLabel('CoD2 game folder')).toHaveValue('C:\\Games\\Steam\\steamapps\\common\\Call of Duty 2');
  await tryButton.click();
  await expect(tryButton).toBeDisabled();
  await expect(page.getByRole('status')).toHaveText('Smoke launched.');
  expect(await page.evaluate(() => window.requests.at(-1))).toMatchObject({action:'trySmoke',map:'mp_toujane',gameDirectory:'C:\\Games\\Steam\\steamapps\\common\\Call of Duty 2'});
  await page.evaluate(() => {window.failNext=true;});
  await tryButton.click();
  await expect(page.getByRole('status')).toContainText('Unsupported DX9 renderer');
  await expect(tryButton).toBeEnabled();
  await expect(page.getByRole('button', {name:'Check compatibility'})).toBeVisible();
});

test('bake selection, output guidance, compact layout and restore cancellation', async ({ page }, info) => {
  await page.getByRole('button',{name:'Restore original files',exact:true}).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  expect(await page.evaluate(() => window.requests.length)).toBe(0);
  await page.getByText('Tools & details',{exact:true}).click();
  await page.getByRole('button',{name:'Map authoring',exact:true}).click();
  await expect(page.getByRole('button',{name:'Bake occupancy',exact:true})).toBeDisabled();
  await page.getByRole('button',{name:'Select maps…'}).click();
  await page.getByRole('button',{name:'Bake occupancy',exact:true}).click();
  await expect(page.getByText('Ready to install', {exact:true})).toBeVisible();
  expect(await page.evaluate(() => window.requests.at(-1))).toMatchObject({action:'bake',inputs:['C:\\Maps\\mp_example.d3dbsp'],output:'C:\\Maps\\smoke-output'});
  await page.screenshot({path:info.outputPath('bake.png'),fullPage:true});
  await page.setViewportSize({width:760,height:560});
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({path:info.outputPath('compact.png'),fullPage:true});
});

test('player package keeps Try available and hides authoring', async ({ page }, info) => {
  await page.addInitScript(() => { window.playerOnly = true; });
  await page.reload();
  await expect(page.getByRole('button',{name:'Try smoke',exact:true})).toBeEnabled();
  await page.getByText('Tools & details',{exact:true}).click();
  await expect(page.getByRole('button',{name:'Map authoring',exact:true})).toHaveCount(0);
  await page.getByRole('button',{name:'Check compatibility',exact:true}).click();
  await expect(page.getByRole('status')).toContainText('Checks passed.');
  await page.getByText('Tools & details',{exact:true}).click();
  await page.screenshot({path:info.outputPath('player.png'),fullPage:true});
});

test('missing CoD2x blocks installing and launching until rechecked', async ({ page }, info) => {
  await page.addInitScript(() => { window.missingCoD2x = true; });
  await page.reload();
  await expect(page.getByTestId('cod2x-status')).toContainText('Install CoD2x first');
  await expect(page.getByRole('button', {name:'Try smoke',exact:true})).toBeDisabled();
  await expect(page.getByRole('button', {name:'Restore original files',exact:true})).toBeEnabled();
  await page.getByText('Tools & details', {exact:true}).click();
  await expect(page.getByRole('button', {name:'Launch installed',exact:true})).toBeDisabled();
  expect(await page.evaluate(() => window.requests.length)).toBe(0);
  await page.screenshot({path:info.outputPath('missing-cod2x.png'),fullPage:true});
  await page.evaluate(() => { window.missingCoD2x = false; });
  await page.getByRole('button', {name:'Recheck',exact:true}).click();
  await expect(page.getByTestId('cod2x-status')).toContainText('CoD2x detected');
  await expect(page.getByRole('button', {name:'Try smoke',exact:true})).toBeEnabled();
  await expect(page.getByRole('button', {name:'Launch installed',exact:true})).toBeEnabled();
  expect(await page.evaluate(() => window.requests.length)).toBe(0);
});
