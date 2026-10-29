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

2. THE OCCUPANCY FILE (only with sv_pure 1)
   Pure servers only let clients read IWD files the server also has. Copy
   prosmoke_stock.iwd into the mod folder you run (your zPAM or ProMod folder):
     <server>\<your mod>\prosmoke_stock.iwd
   Clients need the same file in the same mod folder; with sv_allowDownload 1
   the server sends it (435 KB). It covers all 15 stock maps. A server with no
   mod folder puts it in main renamed with an iw_ prefix, on both sides.
   With sv_pure 0 this step is unnecessary.

Changing the line while the server runs is fine. Carve changes apply to the next
shot; width, height, bloom and duration changes apply after current clouds fade.
