shader_type canvas_item;

// Scatters a sprite's pixels upward and outward as it fades, so something leaving the
// player's sight dissolves into a drifting apparition rather than blinking out.
//
// The sprite is treated as a grid of blocks (`block_size`, in texture pixels). Each
// block drifts along its own pseudo-random path and fades on its own schedule, which
// is what reads as "coming apart" rather than "sliding away as one piece". Sampling is
// nearest-neighbour and offsets are snapped to whole pixels, so the scatter stays
// chunky and in keeping with the pixel art rather than smearing.

// 0 = intact, 1 = fully dispersed. Driven from GDScript over the fade duration.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Size of a scattering block in texture pixels. 1 disperses individual pixels; larger
// values break the sprite into coarser flakes.
uniform float block_size : hint_range(1.0, 16.0) = 2.0;
// How far blocks travel by the end, in texture pixels.
uniform float drift_distance = 14.0;
// Upward bias, so the sprite rises like smoke instead of scattering evenly.
uniform float rise = 0.75;
// Sideways spread relative to the rise.
uniform float spread = 0.55;
// Tint blocks take on as they disperse — a ghostly cast, applied as they fade.
uniform vec3 ghost_color : source_color = vec3(0.72, 0.62, 0.95);
// How strongly the ghost tint is applied at full dispersal.
uniform float ghost_tint : hint_range(0.0, 1.0) = 0.7;
// Texture size in pixels, so block maths can work in texel space.
uniform vec2 sprite_size = vec2(16.0, 16.0);

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    if (progress <= 0.0) {
        // Untouched while intact, so an enemy in view renders exactly as authored.
        COLOR = texture(TEXTURE, UV);
    } else {
        vec2 px = UV * sprite_size;
        // Which block this fragment belongs to.
        vec2 block = floor(px / block_size);
        float r1 = hash2(block);
        float r2 = hash2(block + vec2(37.7, 11.3));
        float r3 = hash2(block + vec2(91.2, 53.9));

        // Blocks leave at staggered times, so the sprite frays apart instead of
        // dissolving all at once. Each block's own progress is remapped from the
        // global one against its head start.
        float delay = r3 * 0.45;
        float local = clamp((progress - delay) / max(1.0 - delay, 0.001), 0.0, 1.0);
        // Ease out, so blocks leap away then coast rather than moving linearly.
        float travel = 1.0 - pow(1.0 - local, 2.0);

        // Rise, with a sideways wander that differs per block.
        vec2 dir = vec2((r1 - 0.5) * 2.0 * spread, -rise);
        vec2 offset = dir * travel * drift_distance;
        // Snap to whole pixels: a fractional offset with nearest sampling makes blocks
        // jitter between texels rather than moving cleanly.
        offset = floor(offset + 0.5);

        vec2 src_px = px - offset;
        vec2 src_uv = src_px / sprite_size;

        // A block that has drifted past the sprite's bounds has nothing to sample.
        if (src_uv.x < 0.0 || src_uv.x > 1.0 || src_uv.y < 0.0 || src_uv.y > 1.0) {
            COLOR = vec4(0.0);
        } else {
            vec4 tex = texture(TEXTURE, src_uv);
            // Per-block fade, offset so blocks wink out at different moments. The
            // extra global term guarantees everything reaches zero alpha exactly at
            // progress 1.0, so no faint remnant is left hanging when the dissolve
            // completes.
            float fade = clamp(1.0 - local * (0.75 + r2 * 0.5), 0.0, 1.0);
            fade *= 1.0 - progress;
            vec3 rgb = mix(tex.rgb, ghost_color, ghost_tint * local);
            COLOR = vec4(rgb, tex.a * fade);
        }
    }
}
