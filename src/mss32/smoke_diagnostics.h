#pragma once

// Opt-in, stock-preserving diagnostics for the CoD2 smoke renderer adapter.
void smoke_diagnostics_startup();
void smoke_diagnostics_renderer_loaded();
void smoke_diagnostics_register_settings();
void smoke_diagnostics_frame();
bool smoke_diagnostics_shutdown();
bool smoke_diagnostics_wants_bullets();
void smoke_diagnostics_bullet(int shooter, int weapon, const float* start, const float* end);
