shader_type canvas_item;

// Horizontal lines drifting across a black field, fading in and out like stars in a
// star map.
//
// Every line is brightest at its centre and falls symmetrically to nothing at both
// ends, so it never terminates on a hard edge. Lines are one pixel tall in this
// buffer's space; because the buffer is rendered at 1/zoom resolution and upscaled
// with nearest-neighbour filtering, one pixel here lands as exactly one pixel of
// foreground art (see starfield.gd).

// How many lines are alive across the field.
uniform int line_count : hint_range(1, 64) = 22;
// Drift speed in buffer pixels per second, before per-line variation.
uniform float drift_speed = 3.0;
// Seconds for one fade in/out cycle, before per-line variation. A period, so larger
// is slower.
uniform float twinkle_period = 14.0;
// Line length as a fraction of field width, randomised per line between these.
uniform float min_length : hint_range(0.02, 1.0) = 0.15;
uniform float max_length : hint_range(0.02, 1.0) = 0.40;
// Peak brightness at a line's centre.
uniform float brightness : hint_range(0.0, 1.0) = 0.55;
// Number of discrete brightness steps a line's gradient is snapped to. Low values
// read as chunky pixel art; raising it toward 32 approaches a smooth ramp.
uniform int shade_steps : hint_range(2, 32) = 5;
// Lines are derived from the haze colour rather than set independently, so they read
// as a brighter version of the same muddy purple instead of a separate hue sitting on
// top of it. See `line_tint` below for the derivation.
uniform vec3 line_color : source_color = vec3(0.78, 0.62, 0.95);
// How far the lines shift toward `line_color` from the haze hue. 0 makes them a plain
// bright version of the haze; 1 uses `line_color` outright. Part-way keeps the family
// resemblance while letting the lines lift clear of the murk.
uniform float line_tint : hint_range(0.0, 1.0) = 0.55;

// --- Noise field ---------------------------------------------------------------
// A dim, cluttered grey haze behind the lines, so the void reads as a faded memory
// rather than empty black. Two octaves at different scales give it structure —
// broad patches with finer grain inside — instead of uniform static.

// Overall strength of the haze. Kept low; this is a texture, not a subject.
uniform float noise_strength : hint_range(0.0, 1.0) = 0.10;
// Base colour the haze tends toward: a muddy deep purple, desaturated enough to still
// read as grey-ish at the low strengths this is drawn at.
uniform vec3 noise_color : source_color = vec3(0.42, 0.33, 0.55);
// Size of the coarse patches, in buffer pixels. Larger means broader blotches.
uniform float noise_scale : hint_range(1.0, 64.0) = 9.0;
// How much the finer second octave contributes, relative to the coarse one.
uniform float noise_detail : hint_range(0.0, 1.0) = 0.45;
// Discrete grey levels. Matches the lines' banding so the whole field reads as one
// palette rather than smooth gradient against chunky lines.
uniform int noise_steps : hint_range(2, 16) = 4;
// Seconds for the haze to drift through one cycle. Slow enough that almost nothing
// changes frame to frame — fast noise reads as TV static and fights the calm of the
// lines — but not so slow the field looks frozen. Measured at this value roughly 3%
// of pixels shift per second and 9% over three, which breathes without churning.
uniform float noise_drift = 16.0;
// Raises the noise floor so the darkest patches are not fully black.
uniform float noise_floor : hint_range(0.0, 1.0) = 0.18;

// Size of the low-resolution buffer, in pixels.
uniform vec2 buffer_size = vec2(384.0, 216.0);
uniform float time_scale = 1.0;

// Cheap deterministic hash, so every line's row, speed, length and phase are stable
// from frame to frame without needing a texture of random values.
float hash(float n) {
    return fract(sin(n * 127.1) * 43758.5453123);
}

// 2D value hash for the noise field.
float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Value noise: hash the lattice corners and interpolate with a smoothstep curve, so
// patches blend into each other instead of showing hard cell edges.
float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(cell);
    float b = hash2(cell + vec2(1.0, 0.0));
    float c = hash2(cell + vec2(0.0, 1.0));
    float d = hash2(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 px = UV * buffer_size;
    float t = TIME * time_scale;
    float lit = 0.0;

    for (int i = 0; i < line_count; i++) {
        float fi = float(i);

        // Fixed row for this line, chosen by stratified sampling: the field is cut
        // into `line_count` horizontal slices and this line lands somewhere inside
        // its own slice. Picking rows by plain hash instead leaves large stretches
        // bare — measured three empty bands out of ten, with the whole top fifth of
        // the screen unused — because nothing stops several lines clumping together.
        // Jittering within the slice keeps the spacing irregular rather than a
        // mechanical ladder. Quantised to whole pixels so a line occupies one crisp
        // row rather than straddling two at partial alpha.
        float slice = buffer_size.y / float(line_count);
        float row = floor((fi + hash(fi + 1.7)) * slice);
        if (abs(px.y - row) > 0.5) {
            continue;
        }

        float len = mix(min_length, max_length, hash(fi + 4.2)) * buffer_size.x;
        // Per-line speed variation, so the field never slides as one rigid sheet.
        float speed = drift_speed * mix(0.45, 1.35, hash(fi + 9.3));
        // Wrap over a span wide enough that a line is fully offscreen before it
        // reappears on the left.
        float span = buffer_size.x + len;
        float head = mod(hash(fi + 6.1) * span + t * speed, span) - len;
        float along = (px.x - head) / len;
        if (along < 0.0 || along > 1.0) {
            continue;
        }

        // Two-sided gradient: 1 at the centre, 0 at both ends. Smoothstep softens the
        // falloff so the taper reads as a glow rather than a linear ramp.
        float gradient = smoothstep(0.0, 1.0, 1.0 - abs(along * 2.0 - 1.0));

        // Independent fade in and out, so lines blink at their own rhythm rather than
        // pulsing together.
        float period = twinkle_period * mix(0.6, 1.6, hash(fi + 12.7));
        float phase = hash(fi + 15.9) * 6.2831853;
        float twinkle = 0.5 + 0.5 * sin(t * 6.2831853 / period + phase);

        lit = max(lit, gradient * twinkle);
    }

    // Snap to a fixed set of brightness levels. Quantising here — after the gradient
    // and twinkle are combined — means the displayed value is always on the palette,
    // so a line reads as a run of flat-coloured pixel blocks and its fade steps
    // between shades instead of sliding smoothly through them.
    float steps = float(shade_steps);
    lit = floor(lit * steps + 0.5) / steps;

    // Grey haze behind everything. Two octaves: broad patches, with a finer grain
    // laid over them so the clutter has structure at more than one size. Both drift
    // very slowly and in different directions, which keeps the field from ever
    // settling into a pattern the eye can lock onto.
    float slow = t / max(noise_drift, 0.001);
    float coarse = value_noise(px / noise_scale + vec2(slow, slow * 0.6));
    float fine = value_noise(px / max(noise_scale * 0.35, 0.001) + vec2(-slow * 0.8, slow * 1.3));
    float haze = mix(coarse, fine, noise_detail);
    // Lift the floor so the darkest patches stay a faint grey rather than going black.
    haze = noise_floor + haze * (1.0 - noise_floor);
    // Band it like the lines, so the whole image shares one quantised palette.
    float nsteps = float(noise_steps);
    haze = floor(haze * nsteps + 0.5) / nsteps;

    vec3 background = noise_color * haze * noise_strength;

    // Lines are the haze colour lifted toward full brightness, then nudged partway to
    // `line_color`. Deriving them from `noise_color` rather than setting them outright
    // is what makes them read as "a brighter version of the background" — recolour the
    // haze and the lines follow it automatically instead of drifting out of key.
    vec3 lifted = normalize(max(noise_color, vec3(0.001)));
    vec3 line_rgb = mix(lifted, line_color, line_tint);

    // Lines sit on top of the haze; taking the max keeps a line at full strength
    // rather than letting the haze wash it out.
    COLOR = vec4(max(background, line_rgb * lit * brightness), 1.0);
}
