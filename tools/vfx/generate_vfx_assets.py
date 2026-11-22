"""Generate crisp procedural RGBA VFX & truck-art badge textures under game/assets/vfx/."""

import os
import struct
import zlib
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "game/assets/vfx"


def write_png_rgba(path: Path, rgba: np.ndarray) -> None:
    """Write uint8 (H, W, 4) RGBA array to disk as standard compressed PNG."""
    h, w, c = rgba.shape
    assert c == 4
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    os.makedirs(path.parent, exist_ok=True)
    path.write_bytes(png)


def to_u8(arr: np.ndarray) -> np.ndarray:
    return np.clip(arr * 255.0, 0.0, 255.0).astype(np.uint8)


def make_junoon_aura_ring(size: int = 512) -> np.ndarray:
    y, x = np.mgrid[0:size, 0:size]
    nx = (x - size * 0.5) / (size * 0.5)
    ny = (y - size * 0.5) / (size * 0.5)
    r = np.sqrt(nx * nx + ny * ny)
    theta = np.arctan2(ny, nx)

    outer_ring = np.exp(-((r - 0.84) / 0.055) ** 2)
    mid_ring = np.exp(-((r - 0.68) / 0.032) ** 2)
    inner_glow = np.exp(-((r - 0.48) / 0.16) ** 2) * 0.45

    petals = 0.5 + 0.5 * np.cos(theta * 12.0)
    petal_band = np.exp(-((r - (0.76 + 0.045 * np.cos(theta * 12.0))) / 0.025) ** 2)
    spokes = (0.5 + 0.5 * np.cos(theta * 24.0)) ** 4 * np.exp(-((r - 0.58) / 0.12) ** 2) * 0.55

    alpha = np.clip(outer_ring * 0.95 + mid_ring * 0.8 + petal_band * 0.9 + spokes + inner_glow, 0.0, 1.0)
    alpha *= np.clip(1.0 - np.maximum(0.0, r - 0.93) / 0.07, 0.0, 1.0)

    gold = np.array([1.0, 0.78, 0.18])
    saffron = np.array([1.0, 0.48, 0.08])
    emerald = np.array([0.16, 0.88, 0.56])

    rgb = (
        outer_ring[..., None] * gold
        + mid_ring[..., None] * saffron
        + petal_band[..., None] * (petals[..., None] * gold + (1.0 - petals[..., None]) * emerald)
        + spokes[..., None] * gold
        + inner_glow[..., None] * saffron
    )
    rgb = np.clip(rgb, 0.0, 1.0)
    return to_u8(np.dstack([rgb, alpha]))


def make_junoon_flame_particle(size: int = 128) -> np.ndarray:
    y, x = np.mgrid[0:size, 0:size]
    nx = (x - size * 0.5) / (size * 0.5)
    ny = (y - size * 0.58) / (size * 0.5)
    wobble = 0.14 * np.sin(ny * 5.0)
    dist = np.sqrt(((nx + wobble) * 1.45) ** 2 + (ny * 0.9) ** 2)
    core = np.exp(-((dist) / 0.34) ** 2)
    halo = np.exp(-((dist) / 0.65) ** 2) * 0.65
    alpha = np.clip(core + halo, 0.0, 1.0) * np.clip(1.0 - dist / 0.95, 0.0, 1.0)
    rgb = np.clip(
        core[..., None] * np.array([1.0, 0.96, 0.72]) + halo[..., None] * np.array([1.0, 0.56, 0.10]),
        0.0,
        1.0,
    )
    return to_u8(np.dstack([rgb, alpha]))


def make_hit_spark_burst(size: int = 256) -> np.ndarray:
    y, x = np.mgrid[0:size, 0:size]
    nx = (x - size * 0.5) / (size * 0.5)
    ny = (y - size * 0.5) / (size * 0.5)
    r = np.sqrt(nx * nx + ny * ny)
    theta = np.arctan2(ny, nx)
    rays = np.maximum(0.0, np.cos(theta * 6.0)) ** 6
    rays2 = np.maximum(0.0, np.cos(theta * 12.0 + 0.25)) ** 10 * 0.7
    spike = (rays + rays2) * np.exp(-r * 2.8)
    core = np.exp(-(r / 0.22) ** 2)
    alpha = np.clip(core + spike, 0.0, 1.0)
    rgb = np.clip(core[..., None] * np.array([1.0, 0.98, 0.85]) + spike[..., None] * np.array([1.0, 0.72, 0.18]), 0.0, 1.0)
    return to_u8(np.dstack([rgb, alpha]))


def make_jalwa_speedlines(w: int = 1280, h: int = 720) -> np.ndarray:
    y, x = np.mgrid[0:h, 0:w]
    nx = (x - w * 0.5) / (w * 0.5)
    ny = (y - h * 0.5) / (h * 0.5)
    r = np.sqrt(nx * nx + ny * ny)
    theta = np.arctan2(ny, nx)

    streaks = (
        np.maximum(0.0, np.sin(theta * 29.0 + 0.4)) ** 12
        + 0.8 * np.maximum(0.0, np.sin(theta * 47.0 + 1.7)) ** 14
        + 0.5 * np.maximum(0.0, np.cos(theta * 17.0)) ** 8
    )
    edge_mask = np.clip((r - 0.38) / 0.65, 0.0, 1.0) ** 1.4
    vignette = np.clip((r - 0.72) / 0.75, 0.0, 1.0) * 0.45
    alpha = np.clip(streaks * edge_mask * 0.85 + vignette, 0.0, 0.92)
    gold = np.array([1.0, 0.76, 0.20])
    saffron = np.array([0.95, 0.42, 0.08])
    mix = edge_mask[..., None]
    rgb = np.clip(gold * (1.0 - mix * 0.4) + saffron * (mix * 0.4), 0.0, 1.0)
    return to_u8(np.dstack([rgb, alpha]))


def make_truck_badge(primary: tuple[float, float, float], accent: tuple[float, float, float], w: int = 256, h: int = 64) -> np.ndarray:
    y, x = np.mgrid[0:h, 0:w]
    nx = (x - w * 0.5) / (w * 0.5)
    ny = (y - h * 0.5) / (h * 0.5)
    ax = np.abs(nx)
    ay = np.abs(ny)
    chamfer = np.maximum(ax * 0.92 + ay * 0.22, ay)
    inside = (ax < 0.97) & (ay < 0.92) & (chamfer < 0.98)
    border = inside & ((ax > 0.91) | (ay > 0.76) | (chamfer > 0.90))
    inner_trim = inside & ~border & ((ax > 0.86) | (ay > 0.64))

    scallop = np.sin(x * 0.28) * 0.5 + 0.5
    grad = np.clip(1.0 - ay * 0.65, 0.25, 1.0)
    bg = np.array([0.07, 0.14, 0.17])[None, None, :] * grad[..., None]
    p_col = np.array(primary)[None, None, :]
    a_col = np.array(accent)[None, None, :]

    rgb = np.where(border[..., None], p_col, bg)
    rgb = np.where(inner_trim[..., None], a_col * (0.65 + 0.35 * scallop[..., None]), rgb)
    alpha = np.where(inside, 0.95, 0.0)
    return to_u8(np.dstack([np.clip(rgb, 0.0, 1.0), alpha]))


def _smooth_fbm(nx: np.ndarray, ny: np.ndarray, rng: np.random.Generator, octaves: list[tuple[int, float]]) -> np.ndarray:
    """Evaluate smooth quintic-interpolated 2D value-noise fBm on normalized [-1, 1] coordinates."""
    u = np.clip((nx + 1.0) * 0.5, 0.0, 0.999999)
    v = np.clip((ny + 1.0) * 0.5, 0.0, 0.999999)
    total = np.zeros_like(u, dtype=np.float64)
    weight_sum = 0.0
    for grid_n, weight in octaves:
        grid = rng.random((grid_n + 1, grid_n + 1))
        gx = u * grid_n
        gy = v * grid_n
        ix = np.floor(gx).astype(np.int32)
        iy = np.floor(gy).astype(np.int32)
        fx = gx - ix
        fy = gy - iy
        # Quintic fade for C2 continuity without grid creases.
        sx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
        sy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
        v00 = grid[iy, ix]
        v10 = grid[iy, ix + 1]
        v01 = grid[iy + 1, ix]
        v11 = grid[iy + 1, ix + 1]
        row0 = v00 + sx * (v10 - v00)
        row1 = v01 + sx * (v11 - v01)
        total += (row0 + sy * (row1 - row0)) * weight
        weight_sum += weight
    return total / max(weight_sum, 1e-8)


def make_dust_puff(size: int = 256) -> np.ndarray:
    """Generate a soft, wispy, billowing stone/asphalt dust cloud sprite with zero hard edges."""
    rng = np.random.default_rng(20261117)
    y, x = np.mgrid[0:size, 0:size]
    nx = (x - (size - 1) * 0.5) / (size * 0.5)
    ny = (y - (size - 1) * 0.5) / (size * 0.5)

    warp_x = _smooth_fbm(nx, ny, rng, [(3, 0.55), (6, 0.30), (12, 0.15)]) - 0.5
    warp_y = _smooth_fbm(nx, ny, rng, [(3, 0.55), (6, 0.30), (12, 0.15)]) - 0.5
    wx = np.clip(nx + warp_x * 0.55, -1.0, 1.0)
    wy = np.clip(ny + warp_y * 0.55, -1.0, 1.0)

    fbm_body = _smooth_fbm(wx, wy, rng, [(4, 0.42), (9, 0.28), (18, 0.17), (36, 0.09), (68, 0.04)])
    fbm_wisps = _smooth_fbm(
        np.clip(nx - warp_y * 0.38, -1.0, 1.0),
        np.clip(ny + warp_x * 0.38, -1.0, 1.0),
        rng,
        [(6, 0.42), (14, 0.30), (30, 0.18), (60, 0.10)],
    )
    # Billowing puff ridges: emphasize fluffy rounded cloud lobes inside the puff.
    billow = np.clip((fbm_body - 0.25) / 0.65, 0.0, 1.0)
    wisp_detail = np.clip((fbm_wisps - 0.28) / 0.62, 0.0, 1.0)

    # Asymmetric multi-lobe cloud silhouette + smooth radial & border falloff.
    lobes = np.exp(-((wx * wx + wy * wy) / 0.26))
    for cx, cy, sigma, amp in [
        (-0.22, -0.10, 0.16, 0.80),
        (0.24, -0.05, 0.15, 0.76),
        (-0.14, 0.20, 0.17, 0.74),
        (0.18, 0.17, 0.15, 0.70),
        (0.02, -0.26, 0.14, 0.66),
    ]:
        lobes = np.maximum(lobes, amp * np.exp(-(((wx - cx) ** 2 + (wy - cy) ** 2) / sigma)))

    r = np.sqrt(nx * nx + ny * ny)
    radial_t = np.clip(1.0 - np.clip((r - 0.12) / 0.82, 0.0, 1.0), 0.0, 1.0)
    radial_falloff = radial_t * radial_t * (3.0 - 2.0 * radial_t)

    box_r = np.maximum(np.abs(nx), np.abs(ny))
    border_t = np.clip(1.0 - np.clip((box_r - 0.70) / 0.28, 0.0, 1.0), 0.0, 1.0)
    border_falloff = border_t * border_t * (3.0 - 2.0 * border_t)

    cloud_shape = lobes * (0.38 + 0.82 * billow) + 0.34 * wisp_detail * radial_falloff
    alpha = np.clip((cloud_shape * radial_falloff * border_falloff - 0.04) / 0.85, 0.0, 1.0)
    alpha = (alpha ** 1.05) * 0.92

    # Warm limestone/asphalt dust shading with bright sunlit upper billows and deeper warm-grey creases.
    shade = np.clip(0.56 + 0.24 * (0.5 - ny * 0.5) + 0.28 * billow + 0.12 * (wisp_detail - 0.4), 0.50, 0.98)
    stone_tint = np.array([0.92, 0.88, 0.81])
    rgb = np.clip(shade[..., None] * stone_tint[None, None, :], 0.0, 1.0)
    return to_u8(np.dstack([rgb, alpha]))


def main() -> None:
    write_png_rgba(OUT_DIR / "junoon_aura_ring.png", make_junoon_aura_ring())
    write_png_rgba(OUT_DIR / "junoon_flame_particle.png", make_junoon_flame_particle())
    write_png_rgba(OUT_DIR / "hit_spark_burst.png", make_hit_spark_burst())
    write_png_rgba(OUT_DIR / "jalwa_speedlines.png", make_jalwa_speedlines())
    write_png_rgba(OUT_DIR / "dust_puff.png", make_dust_puff())
    write_png_rgba(OUT_DIR / "badge_junoon.png", make_truck_badge((0.98, 0.68, 0.18), (0.14, 0.82, 0.54)))
    write_png_rgba(OUT_DIR / "badge_jalwa.png", make_truck_badge((1.0, 0.84, 0.24), (0.92, 0.24, 0.22)))
    print("VFX_ASSETS_GENERATED:", sorted(p.name for p in OUT_DIR.glob("*.png")))


if __name__ == "__main__":
    main()
