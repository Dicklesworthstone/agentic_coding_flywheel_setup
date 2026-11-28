"use client";

import { type RefObject, useEffect, useRef } from "react";
import * as THREE from "three";
import { Timer } from "three";

/**
 * ToolStorm: the /omarchy hero, a living orbital map of the tool system.
 * A small "acfs" hub, three concentric orbit rings and glowing tool-name
 * plates riding each ring, off-centered to the right of the hero copy. The
 * rings are the page's own tool-index tiers (cornerstone, flywheel,
 * third-party), so the hero and the index below it never disagree. No sun
 * and no bloom: a technical orrery that stays legible behind the copy.
 *
 * Plates fade while they pass behind hero text. The page passes the text
 * elements (copy column, nav items) as `avoid`, and the storm measures them,
 * so the text stays on clean navy at every width.
 *
 * Guards:
 * - DPR ≤ 1.5, one-step downgrade to 1 if the warm-up FPS probe sags
 * - RAF loop pauses while document.hidden or the hero is scrolled off-screen
 * - no WebGL available → renders nothing (the CSS gradient hero remains)
 * - lost GL context stops the loop; a restored context resumes it
 * - prefers-reduced-motion renders one still frame, with the same
 *   text fade as the animation
 * - full teardown via AbortController + explicit disposal, aria-hidden canvas
 */

export type StormTier = "cornerstone" | "flywheel" | "thirdParty";
/** Tool names per ring, in the order the page's tool index lists them. */
export type StormTools = Readonly<Record<StormTier, readonly string[]>>;

const BG = 0x0a0e1a;

interface Ring {
  color: string;
  radius: number;
  plateHeight: number;
  /** Orbital speed in radians per second; inner rings run faster. */
  speed: number;
  /** Starting angle, so the three rings' plates never line up radially. */
  phase: number;
  ringOpacity: number;
  plateOpacity: number;
  /** Plates that fit the ring without crowding; the index lists the rest. */
  maxPlates: number;
}

// Third-party CLIs ride the outer ring in dim slate so the flywheel's own
// tools carry the picture.
const RINGS: Record<StormTier, Ring> = {
  cornerstone: {
    color: "#9ece6a",
    radius: 4.1,
    plateHeight: 0.82,
    speed: 0.21,
    phase: 4,
    ringOpacity: 0.4,
    plateOpacity: 1,
    maxPlates: 10,
  },
  flywheel: {
    color: "#7dcfff",
    radius: 6.9,
    plateHeight: 0.68,
    speed: 0.13,
    phase: 8,
    ringOpacity: 0.3,
    plateOpacity: 0.9,
    maxPlates: 10,
  },
  thirdParty: {
    color: "#8b93b8",
    radius: 9.7,
    plateHeight: 0.54,
    speed: 0.085,
    phase: 9,
    ringOpacity: 0.22,
    plateOpacity: 0.72,
    maxPlates: 10,
  },
};
const RING_ORDER: readonly StormTier[] = ["cornerstone", "flywheel", "thirdParty"];

const STORM_OFFSET_X = 3.3; // world units right: reserves the text column
const CAMERA_Z = 13.0;
const CAMERA_Y = 2.3;
/** Breathing room around each measured text box, in CSS pixels. */
const TEXT_ZONE_PAD = 24;
/** Width of a text box's soft edge, in normalized device coordinates. */
const TEXT_ZONE_EDGE = 0.12;
/** Opacity factor for a plate fully behind text. */
const TEXT_ZONE_FLOOR = 0.08;

/** A screen-space box in normalized device coordinates (y up). */
interface TextZone {
  left: number;
  right: number;
  bottom: number;
  top: number;
}
/** Stand-in when the page passes nothing measurable: the hero's left quarter. */
const FALLBACK_TEXT_ZONE: TextZone = { left: -2, right: -0.5, bottom: -2, top: 2 };
const PLATE_FONT_SIZE = 52;
const FALLBACK_PLATE_FONT = `700 ${PLATE_FONT_SIZE}px "JetBrains Mono", ui-monospace, monospace`;

/** Approximate standard normal (Irwin–Hall, n=3). */
function randn(): number {
  return Math.random() + Math.random() + Math.random() - 1.5;
}

/**
 * Canvas font for the plates. next/font registers the site's JetBrains Mono
 * under a generated family name exposed as --font-jetbrains; the literal
 * "JetBrains Mono" only matches a copy installed on the visitor's machine.
 */
function plateFont(element: Element): string {
  const siteFamily = getComputedStyle(element).getPropertyValue("--font-jetbrains").trim();
  if (!siteFamily) return FALLBACK_PLATE_FONT;
  return `700 ${PLATE_FONT_SIZE}px ${siteFamily}, "JetBrains Mono", ui-monospace, monospace`;
}

/** Monospace tool-name plate: dark pill, tier-colored ring, glowing text. */
function makePlateTexture(
  name: string,
  color: string,
  font: string,
): { texture: THREE.CanvasTexture; aspect: number } {
  const pad = 30;
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas context unavailable");
  // An unparsable font string is ignored by the canvas, which would leave the
  // 10px default; setting the fallback first keeps the plates full size.
  const applyFont = () => {
    ctx.font = FALLBACK_PLATE_FONT;
    ctx.font = font;
  };
  applyFont();
  const metrics = ctx.measureText(name);
  canvas.width = Math.ceil(metrics.width + pad * 2);
  canvas.height = PLATE_FONT_SIZE + pad * 2;
  applyFont(); // resizing the canvas resets its context state
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = "rgba(10, 14, 26, 0.78)";
  ctx.beginPath();
  ctx.roundRect(4, 4, canvas.width - 8, canvas.height - 8, 14);
  ctx.fill();
  ctx.strokeStyle = `${color}99`;
  ctx.lineWidth = 2.5;
  ctx.stroke();
  // Glow pass, then a crisp core
  ctx.shadowColor = color;
  ctx.shadowBlur = 18;
  ctx.fillStyle = color;
  ctx.fillText(name, canvas.width / 2, canvas.height / 2 + 1);
  ctx.shadowBlur = 0;
  ctx.fillStyle = "#f2f7ff";
  ctx.fillText(name, canvas.width / 2, canvas.height / 2 + 1);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return { texture, aspect: canvas.width / canvas.height };
}

/** Small soft dot for the hub (deliberately modest: no sun). */
function makeHubTexture(): THREE.CanvasTexture {
  const size = 128;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas context unavailable");
  const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  g.addColorStop(0, "rgba(210, 255, 170, 0.85)");
  g.addColorStop(0.35, "rgba(158, 206, 106, 0.35)");
  g.addColorStop(1, "rgba(10, 14, 26, 0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

export default function ToolStorm({
  className,
  tools,
  avoid,
}: {
  className?: string;
  tools: StormTools;
  /** Hero text elements; plates fade while they pass behind any of them. Keep the array stable. */
  avoid?: readonly RefObject<HTMLElement | null>[];
}) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const isMobile = window.innerWidth < 768;

    // three throws synchronously when no WebGL context can be created
    // (webgl.disabled, some VDI/remote-desktop setups, software-only VMs).
    // The hero's CSS gradient is a perfectly good fallback, so bail quietly
    // instead of letting the error unmount the whole route.
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({
        antialias: true,
        alpha: true,
        // Mobile GPUs: let the browser pick the power-efficient GPU.
        powerPreference: isMobile ? "default" : "high-performance",
      });
    } catch {
      return;
    }

    let pixelRatio = Math.min(window.devicePixelRatio, 1.5);
    renderer.setPixelRatio(pixelRatio);
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.setClearColor(0x000000, 0);
    renderer.domElement.style.display = "block";
    container.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(BG, 0.02);

    const camera = new THREE.PerspectiveCamera(
      55,
      container.clientWidth / Math.max(container.clientHeight, 1),
      0.1,
      200,
    );
    camera.position.set(0, CAMERA_Y, CAMERA_Z);

    const disposables: Array<{ dispose: () => void }> = [];
    // One AbortController tears down every listener; it also lets async work
    // (font loading) that resolves after unmount see that it is too late.
    const controller = new AbortController();
    const { signal } = controller;

    const system = new THREE.Group();
    system.position.set(STORM_OFFSET_X, -0.3, 0);
    system.rotation.x = -0.92; // orrery tilt: rings read as ellipses
    system.rotation.z = 0.16;
    scene.add(system);

    // --- Sparse in-plane dust for depth (no glare) -----------------------------
    {
      const DUST = isMobile ? 500 : 1300;
      const positions = new Float32Array(DUST * 3);
      for (let i = 0; i < DUST; i++) {
        const r = 2 + Math.random() * 11;
        const a = Math.random() * Math.PI * 2;
        positions[i * 3] = Math.cos(a) * r + randn() * 0.3;
        positions[i * 3 + 1] = randn() * 0.25;
        positions[i * 3 + 2] = Math.sin(a) * r + randn() * 0.3;
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
      const mat = new THREE.PointsMaterial({
        color: 0x9ece6a,
        size: isMobile ? 0.045 : 0.055,
        sizeAttenuation: true,
        transparent: true,
        opacity: 0.35,
        depthWrite: false,
      });
      system.add(new THREE.Points(geo, mat));
      disposables.push(geo, mat);
    }

    // --- Hub: modest acfs marker -------------------------------------------------
    const hubTexture = makeHubTexture();
    const hubMaterial = new THREE.SpriteMaterial({
      map: hubTexture,
      transparent: true,
      depthWrite: false,
      opacity: 0.9,
    });
    const hub = new THREE.Sprite(hubMaterial);
    hub.scale.setScalar(1.6);
    system.add(hub);
    disposables.push(hubTexture, hubMaterial);

    // --- Rings: orbit line + plates ----------------------------------------------
    interface Plate {
      name: string;
      ring: Ring;
      sprite: THREE.Sprite;
      material: THREE.SpriteMaterial;
      angle: number;
      wobblePhase: number;
    }
    const plates: Plate[] = [];
    const font = plateFont(container);

    for (const tier of RING_ORDER) {
      const ring = RINGS[tier];
      const SEGMENTS = 160;
      const ringPositions = new Float32Array((SEGMENTS + 1) * 3);
      for (let i = 0; i <= SEGMENTS; i++) {
        const a = (i / SEGMENTS) * Math.PI * 2;
        ringPositions[i * 3] = Math.cos(a) * ring.radius;
        ringPositions[i * 3 + 1] = 0;
        ringPositions[i * 3 + 2] = Math.sin(a) * ring.radius;
      }
      const ringGeo = new THREE.BufferGeometry();
      ringGeo.setAttribute("position", new THREE.BufferAttribute(ringPositions, 3));
      const ringMat = new THREE.LineBasicMaterial({
        color: new THREE.Color(ring.color),
        transparent: true,
        opacity: ring.ringOpacity,
        depthWrite: false,
      });
      system.add(new THREE.Line(ringGeo, ringMat));
      disposables.push(ringGeo, ringMat);

      const names = tools[tier].slice(0, ring.maxPlates);
      names.forEach((name, index) => {
        const { texture, aspect } = makePlateTexture(name, ring.color, font);
        const material = new THREE.SpriteMaterial({
          map: texture,
          transparent: true,
          depthWrite: false,
          opacity: 0,
        });
        const sprite = new THREE.Sprite(material);
        sprite.scale.set(ring.plateHeight * aspect, ring.plateHeight, 1);
        plates.push({
          name,
          ring,
          sprite,
          material,
          angle: (index / names.length) * Math.PI * 2 + ring.phase,
          wobblePhase: Math.random() * Math.PI * 2,
        });
        system.add(sprite);
        disposables.push(texture, material);
      });
    }

    // --- Frame state -------------------------------------------------------------
    let raf = 0;
    let running = false;
    let angularVel = 0;
    let dragging = false;
    let lastPointerX = 0;
    const mouse = { x: 0, y: 0 };
    let scrollDive = 0;
    // THREE.Clock is deprecated (r176+, warns on construction); Timer is the
    // replacement. It needs one update() per frame before getDelta() is read.
    const timer = new Timer();
    const plateWorld = new THREE.Vector3();
    const plateScreen = new THREE.Vector3();

    // Each hero text element as a padded box in normalized device
    // coordinates, re-measured on layout changes rather than every frame.
    let textZones: TextZone[] = [FALLBACK_TEXT_ZONE];
    const measureTextZones = () => {
      const frame = container.getBoundingClientRect();
      if (frame.width === 0 || frame.height === 0) return;
      const measured: TextZone[] = [];
      for (const ref of avoid ?? []) {
        const box = ref.current?.getBoundingClientRect();
        if (!box || box.width === 0 || box.height === 0) continue;
        measured.push({
          left: ((box.left - TEXT_ZONE_PAD - frame.left) / frame.width) * 2 - 1,
          right: ((box.right + TEXT_ZONE_PAD - frame.left) / frame.width) * 2 - 1,
          top: 1 - ((box.top - TEXT_ZONE_PAD - frame.top) / frame.height) * 2,
          bottom: 1 - ((box.bottom + TEXT_ZONE_PAD - frame.top) / frame.height) * 2,
        });
      }
      textZones = measured.length > 0 ? measured : [FALLBACK_TEXT_ZONE];
    };
    measureTextZones();

    /** 0 clear of every text box, 1 well inside one, eased across the soft edge. */
    const behindText = (x: number, y: number) => {
      let deepest = 0;
      for (const zone of textZones) {
        // How far inside this box the point sits (negative outside)
        const inside = Math.min(x - zone.left, zone.right - x, y - zone.bottom, zone.top - y);
        deepest = Math.max(
          deepest,
          THREE.MathUtils.smoothstep(inside, -TEXT_ZONE_EDGE / 2, TEXT_ZONE_EDGE / 2),
        );
      }
      return deepest;
    };

    // Adaptive quality: if the average FPS sags early, drop internal resolution
    let warmupFrames = 0;
    let warmupTime = 0;
    let qualityDegraded = false;

    /**
     * Orbit the plates, then fade each one out while it is behind hero text
     * and dim it toward the far side of its ring. `settle` applies the target
     * opacity at once (the still frame) instead of easing toward it.
     */
    const updatePlates = (dt: number, t: number, settle: boolean) => {
      system.updateMatrixWorld();
      camera.updateMatrixWorld();
      const hubDistance = camera.position.distanceTo(system.position);
      for (const plate of plates) {
        plate.angle += plate.ring.speed * dt;
        plate.sprite.position.set(
          Math.cos(plate.angle) * plate.ring.radius,
          Math.sin(t * 0.9 + plate.wobblePhase) * 0.08,
          Math.sin(plate.angle) * plate.ring.radius,
        );
        plateWorld.copy(plate.sprite.position).applyMatrix4(system.matrixWorld);
        plateScreen.copy(plateWorld).project(camera);
        // The soft edge lets plates glide out from behind the text instead of popping.
        const hidden = plateScreen.z < 1 ? behindText(plateScreen.x, plateScreen.y) : 0;
        const textFade = 1 - (1 - TEXT_ZONE_FLOOR) * hidden;
        // -1 on the near side of the ring, +1 on the far side. Projected NDC
        // depth cannot carry this: at 10–20 units from a 0.1–200 frustum it
        // sits near 0.98 for every plate.
        const depth = THREE.MathUtils.clamp(
          (plateWorld.distanceTo(camera.position) - hubDistance) / plate.ring.radius,
          -1,
          1,
        );
        const depthDim = 0.7 - 0.3 * depth;
        const target = textFade * depthDim * plate.ring.plateOpacity;
        plate.material.opacity = settle
          ? target
          : plate.material.opacity + (target - plate.material.opacity) * Math.min(dt * 6, 1);
      }
    };

    const applyFrame = (dt: number) => {
      const t = timer.getElapsed();

      // Slow system precession + drag-flick inertia
      system.rotation.y += (0.05 + angularVel) * dt;
      angularVel *= Math.exp(-1.6 * dt);

      // Hub breathing: subtle, definitely not a sun
      hub.scale.setScalar(1.55 + Math.sin(t * 1.1) * 0.08);

      // Camera: parallax toward the pointer + scroll-driven dive
      const damp = 1 - Math.exp(-3 * dt);
      camera.position.x += (mouse.x * 0.8 - camera.position.x) * damp;
      camera.position.y += (CAMERA_Y - mouse.y * 0.6 - camera.position.y) * damp;
      camera.position.z += (CAMERA_Z - scrollDive * 1.4 - camera.position.z) * damp;
      camera.lookAt(STORM_OFFSET_X * 0.5, 0, 0);

      updatePlates(dt, t, false);
      renderer.render(scene, camera);
    };

    // Reduced motion: one composed frame from the resting camera position.
    const renderStill = () => {
      camera.position.set(0, CAMERA_Y, CAMERA_Z);
      camera.lookAt(STORM_OFFSET_X * 0.5, 0, 0);
      updatePlates(0, 0, true);
      renderer.render(scene, camera);
    };

    const loop = () => {
      raf = requestAnimationFrame(loop);
      timer.update();
      const dt = Math.min(timer.getDelta(), 0.05);
      applyFrame(dt);

      // Warm-up FPS probe → degrade resolution once if this GPU struggles
      if (!qualityDegraded && warmupFrames < 120) {
        warmupFrames += 1;
        warmupTime += dt;
        if (warmupFrames === 120 && warmupFrames / warmupTime < 40) {
          qualityDegraded = true;
          pixelRatio = 1;
          renderer.setPixelRatio(pixelRatio);
          renderer.setSize(container.clientWidth, container.clientHeight);
        }
      }
    };

    const start = () => {
      if (running || prefersReducedMotion) return;
      running = true;
      timer.update(); // swallow the pause gap so the first frame's delta is small
      loop();
    };
    const stop = () => {
      running = false;
      cancelAnimationFrame(raf);
    };

    // The plates are baked onto <canvas>. With font-display: swap the webfont
    // is usually not ready on first paint, so every plate would be rasterised
    // in the fallback face. Re-bake once the real font is available.
    if (typeof document.fonts?.load === "function") {
      document.fonts
        .load(font)
        .then(() => {
          if (signal.aborted) return;
          for (const plate of plates) {
            const { texture, aspect } = makePlateTexture(plate.name, plate.ring.color, font);
            plate.material.map?.dispose();
            plate.material.map = texture;
            plate.material.needsUpdate = true;
            plate.sprite.scale.set(plate.ring.plateHeight * aspect, plate.ring.plateHeight, 1);
            disposables.push(texture);
          }
          if (prefersReducedMotion) renderStill();
        })
        .catch(() => {
          /* font unavailable: keep the fallback rasterisation */
        });
    }

    // --- Listeners (all via the shared AbortController for clean teardown) -------
    const onPointerMove = (event: PointerEvent) => {
      if (dragging) {
        angularVel = THREE.MathUtils.clamp(
          angularVel + (event.clientX - lastPointerX) * 0.004,
          -1.6,
          1.6,
        );
        lastPointerX = event.clientX;
        return;
      }
      const rect = container.getBoundingClientRect();
      // The listener is on window, so clamp: a pointer far below the hero must
      // not keep pulling the camera further and further off-axis.
      mouse.x = THREE.MathUtils.clamp(((event.clientX - rect.left) / rect.width) * 2 - 1, -1, 1);
      mouse.y = THREE.MathUtils.clamp(((event.clientY - rect.top) / rect.height) * 2 - 1, -1, 1);
    };
    const onPointerDown = (event: PointerEvent) => {
      dragging = true;
      lastPointerX = event.clientX;
    };
    const onPointerUp = () => {
      dragging = false;
    };
    const onPointerLeave = () => {
      dragging = false;
      mouse.x = 0;
      mouse.y = 0;
    };
    container.addEventListener("pointerdown", onPointerDown, { signal });
    window.addEventListener("pointermove", onPointerMove, { signal });
    window.addEventListener("pointerup", onPointerUp, { signal });
    // touch-action: pan-y hands vertical swipes to the browser, which then
    // fires pointercancel (never pointerup). Without this `dragging` sticks
    // and the next touch injects a stale-delta velocity jump.
    window.addEventListener("pointercancel", onPointerUp, { signal });
    container.addEventListener("pointerleave", onPointerLeave, { signal });

    // Lost GL context (GPU reset, aggressive mobile tab management): stop the
    // loop and resume when the browser restores it.
    renderer.domElement.addEventListener(
      "webglcontextlost",
      (event) => {
        event.preventDefault();
        stop();
      },
      { signal },
    );
    renderer.domElement.addEventListener(
      "webglcontextrestored",
      () => {
        // Reduced motion never starts the loop, so repaint the still frame.
        if (prefersReducedMotion) renderStill();
        else start();
      },
      { signal },
    );

    const onScroll = () => {
      scrollDive = THREE.MathUtils.clamp(window.scrollY / Math.max(window.innerHeight, 1), 0, 1);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true, signal });

    // Pause whenever the hero is not being looked at: tab in the background
    // or hero scrolled past. The page is several screens tall, and animating
    // the orrery while the visitor reads the tool index is battery burn.
    let heroVisible = true;
    const syncRunning = () => {
      if (document.hidden || !heroVisible) stop();
      else start();
    };
    document.addEventListener("visibilitychange", syncRunning, { signal });
    const observer = new IntersectionObserver(
      (entries) => {
        heroVisible = entries.some((entry) => entry.isIntersecting);
        syncRunning();
      },
      { threshold: 0 },
    );
    observer.observe(container);

    // Coalesce resize events into one layout pass per frame.
    let resizeRaf = 0;
    const applyResize = () => {
      resizeRaf = 0;
      const width = container.clientWidth;
      const height = Math.max(container.clientHeight, 1);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height);
      measureTextZones();
      if (prefersReducedMotion) renderStill();
    };
    const onResize = () => {
      if (resizeRaf) return;
      resizeRaf = requestAnimationFrame(applyResize);
    };
    window.addEventListener("resize", onResize, { signal });

    // Hero text reflows without a window resize too (webfont swap, wrapping),
    // so re-measure whenever it or the hero changes size.
    const zoneObserver = new ResizeObserver(() => {
      measureTextZones();
      if (prefersReducedMotion) renderStill();
    });
    zoneObserver.observe(container);
    for (const ref of avoid ?? []) if (ref.current) zoneObserver.observe(ref.current);

    if (prefersReducedMotion) {
      system.rotation.y = 0.4;
      renderStill();
    } else {
      start();
    }

    // --- Teardown ----------------------------------------------------------------
    return () => {
      stop();
      if (resizeRaf) cancelAnimationFrame(resizeRaf);
      observer.disconnect();
      zoneObserver.disconnect();
      controller.abort();
      for (const d of disposables) d.dispose();
      scene.clear();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, [tools, avoid]);

  return (
    <div
      ref={containerRef}
      className={className}
      aria-hidden="true"
      style={{ touchAction: "pan-y" }}
    />
  );
}
