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
// Soft-shadow width for pillar bodies, in world pixels. The base's cast shadow crosses the
// pillar as a hard per-column edge; this many pixels of smoothstep are spread across that
// terminator for a penumbra. 0 restores the hard per-column edge.
uniform float pillar_penumbra : hint_range(0.0, 12.0) = 4.0;

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

// Is this world point inside an authored pillar region? Green channel. A pillar's tall
// body is drawn north of its base, so its own base occludes the player's line of sight to
// it from the south even though it is the face they look at — the fog shades these pixels
// directionally instead of by their own (blocked) sightline. See BlockerField.
bool is_pillar(vec2 p) {
    vec2 px = p - grid_origin * tile_size;
    vec2 field_px = grid_size * tile_size;
    if (px.x < 0.0 || px.y < 0.0 || px.x >= field_px.x || px.y >= field_px.y) {
        return false;
    }
    return texture(blockers, (floor(px) + vec2(0.5)) / field_px).g > 0.5;
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

// Does the whole-numbered field pixel `pix` occlude? Same red-channel test as occludes(),
// but addressed by integer pixel so the grid march below cannot drift off a pixel centre.
bool occludes_pixel(ivec2 pix) {
    vec2 px = vec2(pix) - grid_origin * tile_size;
    vec2 field_px = grid_size * tile_size;
    if (px.x < 0.0 || px.y < 0.0 || px.x >= field_px.x || px.y >= field_px.y) {
        return false;
    }
    return texture(blockers, (px + vec2(0.5)) / field_px).r > 0.5;
}

// Raw line-of-sight to a single world point, ignoring the tall-wall overhang.
//
// Marches the exact grid of art pixels the sightline crosses — a DDA (Amanatides–Woo) —
// rather than sampling at a fixed stride. A fixed stride steps *over* anything thinner
// than the step: a hand-authored occluder only a few pixels wide let sight tunnel
// straight through it. Visiting every pixel the ray enters makes occlusion independent of
// occluder thickness, so one solid pixel on the line is enough to stop it. Stepping one
// axis at a time also closes the diagonal corner leak a point march could slip through.
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

    // Parametrise the segment as player_world + t*delta, t in [0,1]. t_max is the t at
    // which the ray next crosses a pixel boundary on each axis; t_delta is the t spent
    // crossing one whole pixel. Advancing the smaller t_max walks pixel to pixel.
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

    // A diagonal crossing visits at most dx+dy pixels; 2*radius bounds that comfortably.
    int max_steps = int(radius_px) * 2 + 2;
    for (int i = 0; i < max_steps; i++) {
        if (t_max.x < t_max.y) {
            cur.x += stp.x;
            t_max.x += t_delta.x;
        } else {
            cur.y += stp.y;
            t_max.y += t_delta.y;
        }
        // Stop at the destination pixel: a fragment sitting on an occluder is lit by its
        // own surface, not shadowed by it — the old march skipped the final step for the
        // same reason, here it is exactly one pixel.
        if (cur == goal) {
            break;
        }
        if (occludes_pixel(cur)) {
            return 0.0;
        }
    }
    return 1.0;
}

// The floor pixel just south of the pillar's base, in THIS pixel's own column.
//
// A pillar's tall body is drawn north of its base, so a ray to the body itself is blocked
// by the base — it is behind the occluder even though it is the face the player sees.
// Marching straight south out of the green region lands on the floor at the base's near
// foot; that foot is directly visible from the front (south) and hidden behind the base
// from the rear (north), which is exactly how the face should light and darken.
//
// Per-column, not a single shared foot: each column of the body inherits the sightline to
// the foot directly beneath it, so the pillar shades as a gradient — columns whose foot
// clears the base light up, columns whose foot is behind it stay dark, and the boundary
// tracks the base's cast shadow. A shared foot instead lights the whole pillar as one flat
// unit, which loses that directional read. The hard per-column edge (and its shimmer as the
// boundary grazes columns) is softened downstream by pillar_shadow_ramp.
//
// The descend runs through the whole green region, which is authored to reach down past
// the base occluder (see the pillar polygons in the room scenes), so the foot lands on
// open floor south of the base rather than on the occluder itself.
vec2 pillar_foot(vec2 world) {
    vec2 p = world;
    for (int i = 0; i < 64; i++) {
        p.y += 1.0;
        if (!is_pillar(p)) {
            break;
        }
    }
    return vec2(world.x, p.y);
}

// Soft directional shading for a pillar body: a smooth ramp across the base's cast-shadow
// terminator instead of the hard per-column on/off.
//
// Along the foot row each column is either lit or shadowed by the base — raw_visibility of
// its own foot, a 0/1 step. The place that step flips is where the base's shadow crosses the
// pillar. Rather than take the raw value here, we measure how far this column sits from that
// boundary (scanning left and right along the foot row for the nearest flip) and smoothstep
// across `pillar_penumbra` pixels of it. That gives an analytic penumbra whose width is a
// fixed artistic parameter rather than something tied to the march resolution; a uniform
// region with no boundary in reach saturates to fully lit or fully dark. Feeding the smooth
// value into the memory pass as well (fov_memory mirrors this) means explored ground
// accumulates the ramp, not a stack of hard per-column edges.
float pillar_shadow_ramp(float cx, float foot_y) {
    bool here = raw_visibility(vec2(cx, foot_y)) > 0.5;
    if (pillar_penumbra <= 0.0) {
        return here ? 1.0 : 0.0;
    }
    float reach = pillar_penumbra + 3.0;
    float dist = reach;
    // Nearest column to the right whose foot flips visibility.
    for (int i = 1; i <= 16; i++) {
        float o = float(i);
        if (o > reach) { break; }
        if ((raw_visibility(vec2(cx + o, foot_y)) > 0.5) != here) { dist = o; break; }
    }
    // ...and to the left; keep whichever boundary is closer, and stop once we pass it.
    for (int i = 1; i <= 16; i++) {
        float o = float(i);
        if (o > reach || o >= dist) { break; }
        if ((raw_visibility(vec2(cx - o, foot_y)) > 0.5) != here) { dist = min(dist, o); break; }
    }
    float signed_dist = here ? dist : -dist;
    return smoothstep(-pillar_penumbra, pillar_penumbra, signed_dist);
}

// Step the outer band of the sight pool down to one flat level rather than fading it, and
// cut everything past the radius to full dark. `point` is the world pixel whose distance
// from the player drives the falloff — for a pillar this is its column's foot, not the
// body pixel being shaded, so the pillar's falloff matches the floor it stands on rather
// than glowing at its top past the pool's edge. raw_visibility has already zeroed anything
// past the radius, so lit==0 pixels are left untouched here.
float apply_rim(float lit, vec2 point) {
    if (lit > 0.0 && rim_width > 0.0) {
        float inner = radius_px * (1.0 - rim_width);
        if (distance(point, player_world) > inner) {
            return rim_level;
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
    // A pillar face inherits the visibility of its near foot, so it lights from the front
    // and darkens from behind rather than by its own base-blocked sightline. The per-column
    // boundary is softened into a penumbra (see pillar_shadow_ramp); the rim falloff is
    // measured from this column's foot.
    if (is_pillar(world)) {
        float fy = pillar_foot(world).y;
        return apply_rim(pillar_shadow_ramp(world.x, fy), vec2(world.x, fy));
    }
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
    // Ordinary ground and wall faces take the rim from their own pixel.
    return apply_rim(lit, world);
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
        // visibility_at folds in the outer-rim step-down, measured from the pillar foot
        // for pillars and from the pixel itself for everything else.
        float lit = visibility_at(world);

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
