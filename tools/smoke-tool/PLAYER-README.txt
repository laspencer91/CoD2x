CoD2 Smoke - player preview

1. Install CoD2x into your Call of Duty 2 version 1.3 game folder first.
2. Extract the entire ZIP, open CoD2SmokeTool.exe and select that game folder.
3. Wait for "CoD2x detected", close other CoD clients/servers and click Try smoke.
4. Join a team, throw a smoke grenade, and shoot through it to try carving.

CoD2x is required: https://github.com/callofduty2x/CoD2x
If it is missing or incomplete, Try smoke and Launch installed stay disabled.
Install/reinstall CoD2x in the selected game folder, then click Recheck.

Existing CoD2 1.3 installations with CoD2x are supported, including Steam. The tool checks
compatibility, backs up replaced client files, installs smoke, and opens Toujane
locally. No separate game copy, Git repo, Python or map bake is required.
Microsoft Edge WebView2 Runtime is required to open the tool.

Restore original files returns the client backed up before smoke. Repeated installs
keep that backup. If CoD2x replaces the loader later, Try smoke backs up that newer
client for restoration and retains earlier backups. Keep the ZIP contents together
until you have restored.
Setup/restoration retain maps, player configs and unrelated files.

Tools & details contains validation and the activity log. It opens on errors.
Copy log copies the visible log; nothing is uploaded. This is a player preview;
multiplayer, demos, particle ordering and GPU compatibility still need acceptance
testing. It has not been approved for competition.

All 15 stock MP smoke occupancy grids and the default smoke look are included.
No game executable, renderer, BSP, textures or models are supplied. There are no
custom-map bakes, map baker, Python, tests or implementation source. Keep the
supporting files beside the EXE; they handle setup, validation and restoration.

Volumetric Smoke System by Logan - contact at logan@loganspencer.dev
Copyright (c) 2026 Logan Spencer. Retain the supplied license/attribution notices.
