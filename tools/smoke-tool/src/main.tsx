import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import './style.css';

type Candidate = { path: string; source: string; steam: boolean; installed: boolean };
type Bootstrap = { bundleRoot: string; candidates: Candidate[]; suggestedOutput: string; rememberedGame: string; bakerAvailable: boolean };
type Action = 'check' | 'install' | 'verify' | 'uninstall' | 'quickTest' | 'trySmoke' | 'bake' | 'validateBundle' | 'openOutput';
type Result = { message: string; outputs: string[] };
const titles: Record<Action, string> = { check: 'Checking compatibility', install: 'Installing smoke', verify: 'Verifying installation', uninstall: 'Restoring original files', quickTest: 'Preparing quick test', trySmoke: 'Preparing smoke', bake: 'Baking occupancy', validateBundle: 'Validating bundle', openOutput: 'Opening output' };
const stockMaps = ['toujane','burgundy','brecourt','breakout','carentan','dawnville','decoy','downtown','farmhouse','harbor','leningrad','matmata','railyard','rhine','trainstation'];
const desktop = '__TAURI_INTERNALS__' in window;

function App() {
  const [tab, setTab] = useState<'setup' | 'bake'>('setup');
  const [data, setData] = useState<Bootstrap>();
  const [game, setGame] = useState('');
  const [map, setMap] = useState('mp_toujane');
  const [inputs, setInputs] = useState<string[]>([]);
  const [output, setOutput] = useState('');
  const [outputs, setOutputs] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [ready, setReady] = useState(false);
  const [status, setStatus] = useState('Finding your installation...');
  const [tone, setTone] = useState('idle');
  const [logs, setLogs] = useState<string[]>([]);
  const [restore, setRestore] = useState(false);
  const logEnd = useRef<HTMLDivElement>(null);
  const log = (line: string) => setLogs(old => [...old.slice(-799), line]);

  async function refresh(initial = false) {
    const found = await invoke<Bootstrap>('bootstrap');
    setData(found);
    if (initial) {
      setGame(found.candidates.find(c => c.path === found.rememberedGame)?.path || found.candidates[0]?.path || '');
      setOutput(found.suggestedOutput);
    }
  }
  useEffect(() => {
    if (!desktop) {
      setStatus('Browser preview. Run the desktop EXE to use installation and baking.');
      return;
    }
    let disposed = false;
    let unlisten: (() => void) | undefined;
    (async () => {
      try {
        const stop = await listen<{ line: string }>('job-log', event => { if (!disposed) log(event.payload.line); });
        if (disposed) { stop(); return; }
        unlisten = stop;
        await refresh(true);
        if (!disposed) { setReady(true); setStatus('Ready. Select your game and click Try smoke.'); }
      } catch (error) { if (!disposed) { setStatus(String(error)); setTone('bad'); } }
    })();
    return () => { disposed = true; unlisten?.(); };
  }, []);
  useEffect(() => { logEnd.current?.scrollIntoView({ block: 'nearest' }); }, [logs]);

  async function pick(kind: 'game' | 'maps' | 'output') {
    try {
      const paths = await invoke<string[]>('pick_path', { kind });
      if (!paths.length) return;
      if (kind === 'game') setGame(paths[0].replace(/[\\/][^\\/]+$/, ''));
      else if (kind === 'maps') { setInputs(paths); setOutputs([]); }
      else { setOutput(paths[0]); setOutputs([]); }
    } catch (error) { setStatus(String(error)); setTone('bad'); }
  }
  async function job(action: Action) {
    if (busy) return;
    setBusy(true); setStatus(titles[action] + '...'); setTone('run');
    if (action === 'bake') setOutputs([]);
    log('\n— ' + titles[action] + ' —');
    try {
      const result = await invoke<Result>('run_job', { request: { action, gameDirectory: game.trim(), map: map.trim(), inputs, output: output.trim() } });
      setStatus(result.message); setTone('ok');
      if (action === 'bake') setOutputs(result.outputs);
      try { await refresh(); } catch (error) { log('Could not refresh installation detection: ' + String(error)); }
    } catch (error) { setStatus(String(error)); setTone('bad'); log(String(error)); }
    finally { setBusy(false); }
  }
  const disabled = busy || !ready;
  const gameDisabled = disabled || !game.trim();
  return <div className="shell">
    <header><div className="brand-mark" aria-hidden="true">2</div><div><div className="eyebrow">CALL OF DUTY 2 · VOLUMETRIC SMOKE</div><h1>Smoke Tool</h1></div><span className="version">LOCAL TEST · 0.1</span></header>
    <nav aria-label="Tool sections"><button aria-current={tab === 'setup' ? 'page' : undefined} onClick={() => setTab('setup')}>01 <span>Try smoke</span></button><button aria-current={tab === 'bake' ? 'page' : undefined} onClick={() => setTab('bake')}>02 <span>Authoring</span></button></nav>
    <main>
      {tab === 'setup' ? <>
        <section className="panel accent"><div className="section-heading"><div><h2>Try volumetric smoke</h2><p>Use your existing CoD2 installation. Steam installations are supported.</p></div><span className="tag">LOCAL GAME</span></div>
          <label htmlFor="game">CoD2 game folder</label><div className="field-row"><input id="game" value={game} disabled={disabled} onChange={e => setGame(e.target.value)} placeholder="Choose the folder containing CoD2MP_s.exe"/><button disabled={disabled} onClick={() => void pick('game')}>Browse…</button></div>
          {!!data?.candidates.length && <div className="detected">{data.candidates.map(c => <button className="candidate" disabled={disabled} key={c.path} onClick={() => setGame(c.path)}><span>{c.source}{c.installed ? ' · smoke installed' : ''}</span><span title={c.path}>{c.path}</span></button>)}</div>}
          <p className="notice">Checks compatibility, backs up your existing client files, and opens {map === 'mp_toujane' ? 'Toujane' : map} with smoke enabled. No separate game copy or map bake is needed.</p>
          <div className="actions"><button className="primary try-button" disabled={gameDisabled || !map.trim()} onClick={() => void job('trySmoke')}>▶ Try smoke</button><button disabled={gameDisabled} onClick={() => setRestore(true)}>Restore original files…</button></div>
          <p className="notice">Join a team and throw a smoke grenade. Shoot through it to carve holes. Close CoD clients and servers before starting.</p>
        </section>
        <details className="panel options"><summary>Advanced options</summary>
          <div className="test-row"><div><label htmlFor="map">Test map</label><input id="map" list="stock-maps" value={map} disabled={disabled} onChange={e => setMap(e.target.value)} spellCheck={false}/><datalist id="stock-maps">{stockMaps.map(name => <option key={name} value={'mp_' + name}/>)}</datalist></div><button disabled={gameDisabled || !map.trim()} onClick={() => void job('quickTest')}>Launch installed</button></div>
          <div className="actions"><button disabled={gameDisabled} onClick={() => void job('check')}>Check compatibility</button><button disabled={gameDisabled} onClick={() => void job('verify')}>Verify installed</button><button disabled={gameDisabled} onClick={() => void job('install')}>Install without launching</button></div>
        </details>
      </> : <>
        <section className="panel"><div className="section-heading"><div><h2>Bake map occupancy</h2><p>Generate smoke collision data from compiled CoD2 maps.</p></div><span className="tag">50 CM GRID</span></div>
          <label>Compiled maps (.d3dbsp)</label><div className="map-list">{inputs.length ? inputs.map(path => <div title={path} key={path}>{path}</div>) : <span>No maps selected. Radiant .map sources must be compiled first.</span>}</div><div className="actions"><button disabled={disabled} onClick={() => void pick('maps')}>Select maps…</button>{!!inputs.length && <button className="quiet" disabled={disabled} onClick={() => { setInputs([]); setOutputs([]); }}>Clear selection</button>}</div>
          <label htmlFor="output">Bake output folder</label><div className="field-row"><input id="output" value={output} disabled={disabled} onChange={e => { setOutput(e.target.value); setOutputs([]); }}/><button disabled={disabled} onClick={() => void pick('output')}>Browse…</button></div>
          <p className="notice">Includes world brushes and terrain. Small static props are ignored. Full collision bounds are used; oversized maps report an error rather than silently reducing coverage.</p>
          <div className="actions"><button className="primary" disabled={disabled || !data?.bakerAvailable || !inputs.length || !output.trim()} onClick={() => void job('bake')}>Bake {inputs.length > 1 ? `${inputs.length} maps` : 'occupancy'}</button><button disabled={disabled || !output.trim()} onClick={() => void job('openOutput')}>Open output folder</button></div>
          {data && !data.bakerAvailable && <p className="warning">Bundled Python is missing. Use the complete portable ZIP to bake without installing Python.</p>}
          {!!outputs.length && <div className="results"><strong>Ready to install</strong>{outputs.map(path => <code key={path}>{path}</code>)}<p>Copy these IWDs into &lt;CoD2&gt;\mapkit_smoke_test\ for this launcher, or your active server mod. Distribute with the matching map; re-bake when its BSP changes.</p></div>}
        </section>
      </>}
      <div className="status" data-tone={tone} role="status"><span className={busy ? 'status-dot working' : 'status-dot'}/><span>{status}</span></div>
      <details className="log-panel" open={busy || tone === 'bad' || tab === 'bake'}><summary>Details & activity</summary><div className="log-heading"><h2>Activity</h2><div><button disabled={disabled} onClick={() => void job('validateBundle')}>Validate bundle</button><button disabled={!logs.length} onClick={() => { void navigator.clipboard.writeText(logs.join('\n')).catch(error => { setStatus('Could not copy log: ' + String(error)); setTone('bad'); }); }}>Copy log</button></div></div><div className="log" role="log" aria-label="Activity log"><pre>{logs.length ? logs.join('\n') : 'Operations and validation results appear here.'}</pre><div ref={logEnd}/></div></details>
    </main>
    <footer><span>Volumetric Smoke System by Logan</span><span title={data?.bundleRoot}>Portable tool · private test build</span></footer>
    {restore && <div className="modal-backdrop"><section className="modal" role="dialog" aria-modal="true" aria-labelledby="restore-title"><h2 id="restore-title">Restore original files?</h2><p>This removes the installed smoke runtime from:</p><code>{game}</code><p>Your previous client files are restored. Backups, maps and unrelated files are kept.</p><div className="actions"><button autoFocus onClick={() => setRestore(false)}>Cancel</button><button className="primary" onClick={() => { setRestore(false); void job('uninstall'); }}>Restore original files</button></div></section></div>}
  </div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
