shader_type canvas_item;

// Accumulates "ever seen" at art-pixel resolution.
//
// Each fragment marches a ray back to the player through the blocker grid to decide
// whether it is lit right now, then writes max(previous, lit). The result only ever
// grows, which is exactly the remembered set — but per pixel rather than per tile, so
// a doorway's shadow edge is remembered where it actually fell.
//
// Rendered into a ping-pong pair of SubViewports: this pass reads the other target's
// texture as `previous` and writes its own, then the two swap. That costs one frame of
// latency, which is invisible at the ~6 updates/sec the player generates.

// Walls, one pixel per tile, red 1 = blocks sight.
uniform sampler2D blockers : filter_nearest, repeat_disable;
// Last frame's accumulated memory, same dimensions as this target.
uniform sampler2D previous : filter_nearest, repeat_disable;
// False on the first pass of a new dungeon, so stale memory is not carried in.
uniform bool use_previous = true;

// World tile of the blocker texture's (0,0), and its size in tiles.
uniform vec2 grid_origin;
uniform vec2 grid_size;
// World pixel of this target's (0,0), and its size in world pixels.
uniform vec2 field_origin;
uniform vec2 field_size;

uniform vec2 player_world;
uniform float tile_size = 16.0;
uniform float radius_px = 144.0;
// March step as a fraction of a tile. Smaller is more accurate at corners; measured
// free up to at least 8x finer, so this is tuned for artifacts rather than speed.
uniform float step_scale : hint_range(0.05, 1.0) = 0.25;
// World pixels a wall's art reaches above its own cell. Must match the fog shader.
uniform float overhang_px : hint_range(0.0, 16.0) = 6.0;

// Does `p` land on solid masonry? The blocker texture holds the wall art's silhouette
// at art-pixel resolution, since the tiles do not fill their cells. See
// fov_fog.gdshader for the measurements behind that.
bool occludes(vec2 p) {
    vec2 px = p - grid_origin * tile_size;
    vec2 field_px = grid_size * tile_size;
    // Outside the grid is open floor: the field is padded so real walls never sit on
    // the boundary.
    if (px.x < 0.0 || px.y < 0.0 || px.x >= field_px.x || px.y >= field_px.y) {
        return false;
    }
    return texture(blockers, (floor(px) + vec2(0.5)) / field_px).r > 0.5;
}

bool is_blocker(vec2 tile) {
    vec2 centre = (tile + vec2(0.5)) * tile_size;
    return occludes(centre);
}

// Raw line of sight to a world point, ignoring the tall-wall overhang.
float raw_visibility(vec2 world) {
    vec2 delta = world - player_world;
    float dist = length(delta);
    float lit = 0.0;
    if (dist <= radius_px) {
        lit = 1.0;
        vec2 dir = delta / max(dist, 0.0001);
        float step_len = tile_size * step_scale;
        int steps = int(dist / step_len);
        for (int i = 1; i < steps; i++) {
            vec2 p = player_world + dir * (float(i) * step_len);
            // Stop short of the destination so a pixel on masonry is lit by its own
            // surface rather than shadowed by it.
            if (distance(p, world) < step_len) {
                break;
            }
            if (occludes(p)) {
                lit = 0.0;
                break;
            }
        }
    }
    return lit;
}

// Mirrors fov_fog.gdshader exactly, or remembered ground would not line up with what
// was lit. See there for why the overhang is a short downward probe rather than
// inheriting the light of the wall below.
float visibility_at(vec2 world) {
    float lit = raw_visibility(world);
    if (overhang_px > 0.0 && lit < 1.0) {
        vec2 below = world + vec2(0.0, overhang_px);
        vec2 below_tile = floor(below / tile_size);
        if (is_blocker(below_tile) && !is_blocker(floor(world / tile_size))) {
            vec2 top_of_wall = vec2(world.x, below_tile.y * tile_size + 1.0);
            lit = max(lit, raw_visibility(top_of_wall));
        }
    }
    return lit;
}

void fragment() {
    // Quantised to whole art pixels exactly as the fog shader does, or a remembered
    // pixel could disagree with the lit pixel that produced it and the two would drift
    // apart along shadow edges.
    vec2 world = floor(field_origin + UV * field_size) + vec2(0.5);
    float lit = visibility_at(world);
    float prev = use_previous ? texture(previous, UV).r : 0.0;
    float acc = max(prev, lit);
    COLOR = vec4(acc, acc, acc, 1.0);
}
