// Volumetric Smoke System by Logan - contact at logan@loganspencer.dev
// Copyright (c) 2026 Logan Spencer. Private preview.
#pragma once
#include <cmath>
#include <cstdlib>
#include <sstream>
#include <string>
#include <string_view>

namespace cod2_smoke {
inline constexpr char policy_dvar[] = "sv_prosmoke_policy";
inline constexpr char resolution_dvar[] = "prosmoke_resolution";
inline constexpr char default_policy[] = "v1";

#define COD2_SMOKE_POLICY_FIELDS(X) \
    X(density, .07f, .001f, 1.f) \
    X(width, 1.2f, .5f, 1.5f) \
    X(height, 1.f, .5f, 2.f) \
    X(bloom_rate, 512.f, 64.f, 32768.f) \
    X(bloom_time, 0.f, 0.f, 30.f) \
    X(thicken, .5f, .05f, 3.f) \
    X(duration, 48.f, 10.f, 90.f) \
    X(fade_time, 12.f, 1.f, 30.f) \
    X(fx_after_smoke, 0.f, 0.f, 2.f) \
    X(brightness, .80f, .1f, 2.f) \
    X(variation, .42f, 0.f, 3.f) \
    X(shadow_strength, .35f, 0.f, 1.f) \
    X(lightgrid_strength, .65f, 0.f, 1.f) \
    X(edge_softness, .22f, .05f, .8f) \
    X(height_gradient, .30f, 0.f, 1.f) \
    X(billow_size, 190.f, 20.f, 1000.f) \
    X(billow_strength, 1.65f, 0.f, 3.f) \
    X(billow_speed, 1.f, .1f, 4.f) \
    X(wisp_size, 90.f, 10.f, 500.f) \
    X(wisp_strength, 1.5f, 0.f, 3.f) \
    X(wisp_speed, 1.f, .1f, 4.f) \
    X(rise_speed, 1.f, .1f, 4.f) \
    X(tint_r, 1.05f, 0.f, 2.f) \
    X(tint_g, 1.01f, 0.f, 2.f) \
    X(tint_b, .94f, 0.f, 2.f) \
    X(tint_amount, .35f, 0.f, 1.f) \
    X(carve_scale, 1.f, .5f, 2.f) \
    X(carve_pistol, 3.f, 1.f, 20.f) \
    X(carve_smg, 3.5f, 1.f, 20.f) \
    X(carve_rifle, 4.5f, 1.f, 20.f) \
    X(carve_semi, 4.75f, 1.f, 20.f) \
    X(carve_sniper, 11.f, 1.f, 20.f) \
    X(carve_shotgun, 6.f, 1.f, 20.f)

// width scales the mature cloud; height scales its vertical radius relative to width.
// bloom_time is approximate seconds for a cloud to reach full size; 0 keeps bloom_rate
// (new cells per second). thicken is seconds for a reached cell to fill.
// carve_* values are visual hole radii in game units per weapon class, multiplied by
// carve_scale. Holes already carved keep their size; new shots use the current values.
struct Policy {
#define DECLARE_POLICY(name, value, lo, hi) float name = value;
    COD2_SMOKE_POLICY_FIELDS(DECLARE_POLICY)
#undef DECLARE_POLICY
};
struct PolicyField { const char* name; float Policy::*member; float minimum, maximum; };
inline constexpr PolicyField policy_fields[]{
#define DEFINE_POLICY_FIELD(name, value, lo, hi) {#name, &Policy::name, lo, hi},
    COD2_SMOKE_POLICY_FIELDS(DEFINE_POLICY_FIELD)
#undef DEFINE_POLICY_FIELD
};
#undef COD2_SMOKE_POLICY_FIELDS

inline bool parse_policy(std::string_view text, Policy& output) {
    if (text.empty() || text.size() > 1024) return false;
    std::istringstream stream{std::string(text)};
    std::string token;
    if (!(stream >> token) || token != default_policy) return false;
    Policy next;
    bool used[sizeof(policy_fields) / sizeof(policy_fields[0])]{};
    while (stream >> token) {
        const auto separator = token.find('=');
        if (separator == std::string::npos || separator + 1 == token.size()) return false;
        const auto name = token.substr(0, separator), number = token.substr(separator + 1);
        char* end = nullptr; const float value = std::strtof(number.c_str(), &end);
        if (end != number.c_str() + number.size() || !std::isfinite(value)) return false;
        bool found = false;
        for (unsigned i = 0; i < sizeof(used) / sizeof(used[0]); ++i) {
            const auto& field = policy_fields[i];
            if (name != field.name) continue;
            if (used[i] || value < field.minimum || value > field.maximum) return false;
            used[i] = true; found = true; next.*field.member = value; break;
        }
        if (!found) return false;
    }
    if (next.fade_time >= next.duration || std::floor(next.fx_after_smoke) != next.fx_after_smoke) return false;
    output = next;
    return true;
}

// Read the replicated configstring itself, rather than a client-writable dvar copy.
// The same parser serves systeminfo (branch servers register the dvar) and serverinfo
// (stock CoD2x servers publish it with `sets`), which the client checks in that order.
inline std::string policy_from_info(std::string_view info) {
    std::string result;
    bool found = false;
    if (!info.empty() && info.front() == '\\') info.remove_prefix(1);
    while (!info.empty()) {
        const auto split = info.find('\\');
        if (split == std::string_view::npos) return {};
        const auto key = info.substr(0, split); info.remove_prefix(split + 1);
        const auto next = info.find('\\');
        const auto value = info.substr(0, next);
        if (key == policy_dvar) {
            if (found || value.size() > 1024) return {};
            result = std::string(value); found = true;
        }
        if (next == std::string_view::npos) break;
        info.remove_prefix(next + 1);
    }
    return result;
}
}
