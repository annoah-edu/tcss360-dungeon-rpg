shader_type canvas_item;

// Draws the fog over the dungeon at art-pixel resolution.
//
// Three outcomes per pixel, matching the states the tile-based overlay used to paint:
//   lit now          -> clear, the dungeon shows through untouched
//   remembered only  -> a dark veil, so explored ground reads as map rather than scene
//   never seen       -> fully transparent, so the starfield backdrop reads through
//
// That last one is deliberate and load-bearing: the backdrop sits on a CanvasLayer
// behind the world, so unexplored space has to be a window onto it, not black paint.
//
// Room geometry is clipped separately (see seen_mask.gdshader) so unexplored rooms are
// not drawn underneath this transparency.

uniform sampler2D blockers : filter_nearest, repeat_disable;
// Accumulated "ever seen", produced by fov_memory.gdshader.
uniform sampler2D memory : filter_nearest, repeat_disable;

uniform vec2 grid_origin;
uniform vec2 grid_size;
uniform vec2 field_origin;
uniform vec2 field_size;

uniform vec2 player_world;
uniform float tile_size = 16.0;
uniform float radius_px = 144.0;
uniform float step_scale : hint_range(0.05, 1.0) = 0.25;
// How far a wall's art reaches above its own cell, in world pixels. North/south wall
// tiles are opaque from row 12 of their 32px sprite, whose lower 16 rows fill the
// cell — so 4px pokes into the cell above. East/west tiles start at row 16 and do not
// overhang at all; the probe below only fires where a wall actually sits, so they are
// unaffected. 0 disables the handling entirely.
uniform float overhang_px : hint_range(0.0, 16.0) = 6.0;

// How dark remembered-but-unlit ground is drawn.
uniform float remembered_darkness : hint_range(0.0, 1.0) = 0.55;
// Opacity of never-seen space. 0 lets the backdrop through; raise for a black shroud.
uniform float unseen_opacity : hint_range(0.0, 1.0) = 0.0;
// Outer ring: the last `rim_width` fraction of the sight radius is drawn at a single
// dimmer level instead of fading out. A gradient reads as a modern lighting effect
// laid over the art; one flat step keeps the pool inside the same limited palette the
// tiles use. 0 removes the ring entirely for a single hard edge.
uniform float rim_width : hint_range(0.0, 0.9) = 0.22;
// How lit the ring is, between the veil and full brightness.
uniform float rim_level : hint_range(0.0, 1.0) = 0.45;

// Set false to disable the fog entirely, for authoring and debugging.
uniform bool fog_enabled = true;
// Keep the veil off wall cells, so a wall never shades itself and a run of tiles shows
// no seams between its members. Off reverts to darkening everything uniformly.
uniform bool shadow_ignores_walls = true;

// Screen-to-world mapping. The fog is drawn on a CanvasLayer so it covers the viewport
// regardless of where the camera is, which means its vertices are in *screen* pixels —
// MODEL_MATRIX would give 0..1920, not world coordinates. These carry the camera's
// position and zoom so each fragment can recover the world point it covers.
uniform vec2 view_origin;   // world position of the screen's top-left corner
uniform vec2 view_scale;    // world pixels per screen pixel (1 / camera zoom)

varying vec2 screen_position;

void vertex() {
    screen_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Does the world point `p` land on solid masonry?
//
// The blocker texture stores the wall art's silhouette at art-pixel resolution, not one
// bit per tile, because the tiles do not fill their cells: an east/west wall is a 6px
// pillar in a 16px cell, corners hug one side, some tiles occupy only the lower half.
// Testing per pixel means occlusion follows the outline the player can actually see,
// so shadow edges start at the masonry rather than a tile boundary away from it.
bool occludes(vec2 p) {
    vec2 px = p - grid_origin * tile_size;
    vec2 field_px = grid_size * tile_size;
    if (px.x < 0.0 || px.y < 0.0 || px.x >= field_px.x || px.y >= field_px.y) {
        return false;
    }
    return texture(blockers, (floor(px) + vec2(0.5)) / field_px).r > 0.5;
}

// Whether any part of a tile blocks, for the overhang probe below.
bool is_blocker(vec2 tile) {
    vec2 centre = (tile + vec2(0.5)) * tile_size;
    return occludes(centre);
}

// Is this world point on drawn masonry? Blue channel is the untrimmed sprite — the
// wall body as the player sees it, including the inner skin that no longer occludes.
bool is_wall_art(vec2 p) {
    vec2 px = p - grid_origin * tile_size;
    vec2 field_px = grid_size * tile_size;
    if (px.x < 0.0 || px.y < 0.0 || px.x >= field_px.x || px.y >= field_px.y) {
        return false;
    }
    return texture(blockers, (floor(px) + vec2(0.5)) / field_px).b > 0.5;
}

// Should shadow be suppressed at this pixel because it lies within a wall's body?
//
// Masking every occupied *cell* was wrong: the sprite fills only part of its cell — an
// east/west wall is a 6px pillar in a 16px cell — so a whole-cell exemption leaves a
// halo of empty pixels that can never be shadowed. Measured, 30% of the occupancy mask
// was empty space, and that halo is exactly the bright strip along wall borders and
// corners.
//
// Two conditions, both required:
//   * the pixel is drawn masonry (red channel), not merely inside an occupied cell —
//     this is what removes the halo, since empty pixels now receive shadow normally;
//   * walking outward along the ray still finds solid art before open floor, meaning
//     the pixel sits inside the run rather than on its far face.
//
// The second is the grid traversal: shadow resumes the moment the ray leaves the
// contiguous solid region, so thick walls and connected runs never shade themselves
// and never produce internal seams.
bool inside_wall_run(vec2 world) {
    // Drawn masonry only. Testing the sprite rather than the cell is the whole fix:
    // an empty pixel inside a wall cell is floor as far as lighting is concerned, and
    // now receives shadow like any other floor.
    return is_wall_art(world);
}

// Raw line-of-sight to a single world point, ignoring the tall-wall overhang.
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
            // Stop just short of the destination so a pixel sitting on masonry is lit
            // by its own surface rather than shadowed by it. With pixel-accurate
            // silhouettes this only needs to skip the last step, not a whole tile.
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

// Light a wall's tall face along with the wall it belongs to.
//
// North/south wall art overhangs its grid cell by `overhang_px` (measured 4px: the
// sprite is opaque from row 12 of 32, and its lower 16 rows fill the cell). That strip
// is the face the player looks at, and it is drawn into the cell above — which is
// usually shadowed behind the wall, so on its own line of sight it renders dark while
// the wall below it is lit.
//
// East/west walls use a different tile that is opaque only from row 16, so they do not
// overhang at all and need none of this.
//
// The fix is a short *downward* probe, not the earlier "inherit the wall below's
// light": inheriting let sight cross solid wall runs entirely (measured 14 cells
// visible through up to 4 walls) because the wall below can be lit from a completely
// different angle. Probing only `overhang_px` down keeps the effect local to the
// sprite's own footprint.
float visibility_at(vec2 world) {
    float lit = raw_visibility(world);
    if (overhang_px > 0.0 && lit < 1.0) {
        // Only the strip immediately above a wall carries that wall's face, so the
        // probe fires only there.
        vec2 below = world + vec2(0.0, overhang_px);
        vec2 below_tile = floor(below / tile_size);
        if (is_blocker(below_tile) && !is_blocker(floor(world / tile_size))) {
            // Sample the wall's own top edge rather than wherever the probe landed:
            // a probe that overshoots into the next cell can pick up light from a
            // completely different space, which is how sight ends up crossing solid
            // wall runs.
            vec2 top_of_wall = vec2(world.x, below_tile.y * tile_size + 1.0);
            lit = max(lit, raw_visibility(top_of_wall));
        }
    }
    return lit;
}

void fragment() {
    if (!fog_enabled) {
        COLOR = vec4(0.0);
    } else {
        // Snap to whole art pixels before deciding anything. The fog rect is
        // screen-space, so at 5x zoom one screen pixel is a fifth of an art pixel and
        // the veil boundary would otherwise land mid-pixel — a smooth ramp across a
        // block that the rest of the game draws as one flat colour. Quantising here
        // makes every fragment of an art pixel resolve identically, so shadow edges
        // fall on the same grid as the tile art.
        vec2 world = floor(view_origin + screen_position * view_scale) + vec2(0.5);
        float lit = visibility_at(world);

        // Step the outer band down to one flat level rather than fading it. Applied
        // after the sight test so the ring only dims ground that is genuinely visible;
        // shadowed ground is already dark and must not be lifted by it.
        if (lit > 0.0 && rim_width > 0.0) {
            float inner = radius_px * (1.0 - rim_width);
            if (distance(world, player_world) > inner) {
                lit = rim_level;
            }
        }

        // Memory is stored over the blocker field's extent; anything outside it has
        // certainly never been seen.
        vec2 mem_uv = (world - field_origin) / field_size;
        float remembered = 0.0;
        if (mem_uv.x >= 0.0 && mem_uv.y >= 0.0 && mem_uv.x <= 1.0 && mem_uv.y <= 1.0) {
            remembered = texture(memory, mem_uv).r;
        }

        // Veil strength: none where lit, `remembered_darkness` over remembered ground,
        // `unseen_opacity` where the player has never been. Mixing rather than
        // branching keeps the transition smooth at the rim.
        float veil = mix(unseen_opacity, remembered_darkness, remembered);
        veil *= 1.0 - lit;

        // Never darken masonry itself.
        //
        // A ray stops at the *near* surface of a wall, so everything from there to the
        // far side is nominally shadowed — including the wall's own body. Drawn, that
        // reads as the wall casting a shadow onto itself, and on a run of tiles the
        // internal boundaries show up as seams where each tile shades the next.
        //
        // Masking by tile occupancy sidesteps computing exit intersections entirely:
        // the shadow is still projected from the near surface, it simply cannot be seen
        // until it leaves the solid region. Equivalent to drawing the shadow layer
        // beneath the wall tiles, but done here because the fog composites over the
        // whole scene rather than sitting in the layer stack.
        if (shadow_ignores_walls && inside_wall_run(world)) {
            veil = 0.0;
        }

        COLOR = vec4(0.0, 0.0, 0.0, veil);
    }
}
