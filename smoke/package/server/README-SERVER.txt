ProSmoke - server setup

1. THE POLICY LINE (required)
   Add to your server config, or copy prosmoke_server.cfg into your mod folder
   and exec it:
     sets sv_prosmoke_policy "v1"
   It must be "sets" (serverinfo), not "set", on a regular CoD2x server.
   This one line turns smoke on for every ProSmoke client. Fields after v1 tune
   width, height, bloom time, duration and per-weapon carve sizes; every client
   gets identical values. See prosmoke_server.cfg for the full list and ranges.
   A mistyped field makes the whole line invalid and everyone sees normal smoke.

2. THE OCCUPANCY FILE (mounted map data, and sv_pure compatibility)
   The client must mount the archive even when sv_pure is 0. The player package
   includes main\iw_prosmoke_stock.iwd for normal launches, plus the matching
   prosmoke\prosmoke_stock.iwd for launches with fs_game prosmoke.
   Pure servers only let clients read IWD files the server also has. Copy
   prosmoke_stock.iwd into the mod folder you run (your zPAM or ProMod folder):
     <server>\<your mod>\prosmoke_stock.iwd
   Clients need the same file in the same mod folder; with sv_allowDownload 1
   the server sends it (435 KB). It covers all 15 stock maps. A server with no
   mod folder puts it in main renamed with an iw_ prefix, on both sides.
   With sv_pure 0 no matching server archive is needed, but the client archive
   must still be in a mounted folder. Fully restart after adding an IWD.

3. THE COMPETITIVE MAP GRIDS
   prosmoke_competitive_full.iwd contains 12 additional full-collision map grids,
   including mp_toujane_fix. Install this same file into the active server mod
   directory and make it available to clients through your file distribution.
   For a FastDL mirror, keep the same relative directory and filename as the
   game server expects. Clients need the byte-identical IWD mounted in the
   corresponding active mod directory; normal mod downloads can provide it.
   Keep prosmoke_stock.iwd too: the two archives cover different map names.
   This competitive IWD is about 354 KB and contains data only. The separate
   eight-map cropped candidate bundle is not included in these server files.
   A live server needs a filesystem reload before it can mount a newly added
   archive. Adding it to the download mirror alone does not activate smoke.

Changing the line while the server runs is fine. Carve changes apply to the next
shot; width, height, bloom and duration changes apply after current clouds fade.
