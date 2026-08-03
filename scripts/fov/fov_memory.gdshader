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

// Is this world point inside an authored pillar region? Green channel; see fov_fog.
bool is_pillar(vec2 p) {
    vec2 px = p - grid_origin * tile_size;
    vec2 field_px = grid_size * tile_size;
    if (px.x < 0.0 || px.y < 0.0 || px.x >= field_px.x || px.y >= field_px.y) {
        return false;
    }
    return texture(blockers, (floor(px) + vec2(0.5)) / field_px).g > 0.5;
}

// Does the whole-numbered field pixel `pix` occlude? Integer-addressed twin of occludes(),
// for the grid march below.
bool occludes_pixel(ivec2 pix) {
    vec2 px = vec2(pix) - grid_origin * tile_size;
    vec2 field_px = grid_size * tile_size;
    if (px.x < 0.0 || px.y < 0.0 || px.x >= field_px.x || px.y >= field_px.y) {
        return false;
    }
    return texture(blockers, (px + vec2(0.5)) / field_px).r > 0.5;
}

// Raw line of sight to a world point, ignoring the tall-wall overhang.
//
// Pixel-exact DDA (Amanatides–Woo), matching fov_fog.gdshader. A fixed stride steps over
// occluders thinner than the step, which let *remembered* ground leak through thin walls
// even after the live visibility march was fixed. Walking every pixel the ray enters
// makes occlusion independent of thickness.
float raw_visibility(vec2 world) {
    vec2 delta = world - player_world;
    float dist = length(delta);
    if (dist > radius_px) {
        return 0.0;
    }

    ivec2 cur = ivec2(floor(player_world));
    ivec2 goal = ivec2(floor(world));
    if (cur == goal) {
        return 1.0;
    }

    ivec2 stp = ivec2(0);
    vec2 t_max = vec2(1e30);
    vec2 t_delta = vec2(1e30);
    if (delta.x > 0.0) {
        stp.x = 1;
        t_max.x = (float(cur.x) + 1.0 - player_world.x) / delta.x;
        t_delta.x = 1.0 / delta.x;
    } else if (delta.x < 0.0) {
        stp.x = -1;
        t_max.x = (player_world.x - float(cur.x)) / -delta.x;
        t_delta.x = -1.0 / delta.x;
    }
    if (delta.y > 0.0) {
        stp.y = 1;
        t_max.y = (float(cur.y) + 1.0 - player_world.y) / delta.y;
        t_delta.y = 1.0 / delta.y;
    } else if (delta.y < 0.0) {
        stp.y = -1;
        t_max.y = (player_world.y - float(cur.y)) / -delta.y;
        t_delta.y = -1.0 / delta.y;
    }

    int max_steps = int(radius_px) * 2 + 2;
    for (int i = 0; i < max_steps; i++) {
        if (t_max.x < t_max.y) {
            cur.x += stp.x;
            t_max.x += t_delta.x;
        } else {
            cur.y += stp.y;
            t_max.y += t_delta.y;
        }
        // The destination pixel is lit by its own surface, so it is never tested.
        if (cur == goal) {
            break;
        }
        if (occludes_pixel(cur)) {
            return 0.0;
        }
    }
    return 1.0;
}

// Visibility of a pillar's face: line of sight to the centre of the floor just south of
// its base. See fov_fog.gdshader; the memory pass must use the same rule (including the
// shared foot) or remembered ground would disagree with what was lit.
float pillar_face_visibility(vec2 world) {
    vec2 p = world;
    for (int i = 0; i < 64; i++) {
        p.y += 1.0;
        if (!is_pillar(p)) {
            break;
        }
    }
    float base_y = p.y - 1.0;
    float left_x = world.x;
    for (int i = 0; i < 64; i++) {
        if (!is_pillar(vec2(left_x - 1.0, base_y))) {
            break;
        }
        left_x -= 1.0;
    }
    float right_x = world.x;
    for (int i = 0; i < 64; i++) {
        if (!is_pillar(vec2(right_x + 1.0, base_y))) {
            break;
        }
        right_x += 1.0;
    }
    vec2 foot = vec2(floor((left_x + right_x) * 0.5) + 0.5, p.y);
    return raw_visibility(foot);
}

// Mirrors fov_fog.gdshader exactly, or remembered ground would not line up with what
// was lit. See there for why the overhang is a short downward probe rather than
// inheriting the light of the wall below.
float visibility_at(vec2 world) {
    if (is_pillar(world)) {
        return pillar_face_visibility(world);
    }
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
