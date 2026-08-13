shader_type canvas_item;

// Hides room geometry the player has never seen, so unexplored space shows the
// backdrop instead of the dungeon.
//
// The fog draws never-seen ground transparent, which is what lets the starfield read
// through it. On its own that would also expose every unexplored room, since the tiles
// are still rendered underneath. This shader clips those fragments away.
//
// The mask is the same per-pixel memory texture the fog composites against, so a wall
// is covered at exactly the pixels it occupies. That is what retires the old per-tile
// mask and its wall-overhang dilation: a 16x32 wall sprite straddling two grid rows no
// longer has to be special-cased, because nothing here is decided per tile.

uniform sampler2D memory : filter_nearest, repeat_disable;
// World pixel of the memory texture's (0,0), and its size in world pixels.
uniform vec2 field_origin;
uniform vec2 field_size;
// Below this, a pixel counts as never seen and is discarded.
uniform float reveal_threshold : hint_range(0.0, 1.0) = 0.35;
// Set false to draw everything, e.g. when fog is disabled.
uniform bool mask_enabled = true;

varying vec2 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    if (mask_enabled) {
        vec2 uv = (world_position - field_origin) / field_size;
        // Outside the tracked field is by definition unexplored.
        if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
            discard;
        }
        if (texture(memory, uv).r < reveal_threshold) {
            discard;
        }
    }
}
