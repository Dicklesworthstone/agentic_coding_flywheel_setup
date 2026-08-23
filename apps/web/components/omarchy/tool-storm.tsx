"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";

/**
 * ToolStorm — a swirling vortex of particles and tool-name sprites spiraling
 * into a glowing "flywheel" core, in Tokyo Night hues over Omarchy's deep
 * space navy. Raw three.js (no react-three-fiber), one canvas, fully disposed
 * on unmount.
 *
 * Performance & a11y guards:
 * - devicePixelRatio capped at 1.5
 * - particle count reduced below 768px viewports
 * - RAF loop pauses while document.hidden or the hero is scrolled off-screen
 * - no WebGL available → component renders nothing (CSS gradient hero remains)
 * - prefers-reduced-motion renders a single composed frame, no animation
 * - canvas is decorative (aria-hidden) — all content readable without it
 */

// Tokyo Night palette
const PALETTE = {
  bg: 0x0a0e1a,
  green: 0x9ece6a,
  cyan: 0x7dcfff,
  purple: 0xbb9af7,
  magenta: 0xf7768e,
  amber: 0xe0af68,
  white: 0xc0caf5,
} as const;

const TOOL_NAMES = [
  "ntm", "am", "ubs", "bv", "cass", "cm", "caam", "slb", "dcg", "ru",
  "rch", "fsfs", "pt", "sbh", "casr", "dsr", "asb", "pcr", "ee", "fmd",
  "pi", "pfr", "giil", "csctf", "xf", "tru", "rano", "mdwb", "s2p",
  "srps", "apr", "jfp", "brenner", "opencode",
] as const;

// Sprite glow colors cycle through the accent hues
const SPRITE_COLORS = ["#9ece6a", "#7dcfff", "#bb9af7", "#e0af68", "#f7768e"] as const;

const STORM_RADIUS = 15;
const ARM_COUNT = 3;
const ARM_TWIST = 0.5; // radians of wrap per unit radius — the spiral pitch
const BASE_SPIN = 0.05; // rad/s auto-rotation
const DRAG_DAMPING = 1.6; // exponential decay rate of flick angular velocity
const CAMERA_BASE_Z = 13;

interface ToolSprite {
  sprite: THREE.Sprite;
  material: THREE.SpriteMaterial;
  // Orthonormal basis of the sprite's orbital plane
  planeU: THREE.Vector3;
  planeV: THREE.Vector3;
  radius: number;
  speed: number;
  phase: number;
  baseOpacity: number;
  pulseSpeed: number;
  pulsePhase: number;
}

/** Approximate standard normal via sum of uniforms (Irwin–Hall, n=3). */
function randn(): number {
  return Math.random() + Math.random() + Math.random() - 1.5;
}

function pick<T>(items: readonly T[]): T {
  return items[Math.floor(Math.random() * items.length)] as T;
}

/** Radial-gradient glow texture for the flywheel core. */
function makeGlowTexture(inner: string, outer: string): THREE.CanvasTexture {
  const size = 256;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas context unavailable");
  const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  gradient.addColorStop(0, inner);
  gradient.addColorStop(0.25, outer);
  gradient.addColorStop(1, "rgba(10, 14, 26, 0)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

/** Monospace tool-name texture with a soft neon glow. */
function makeToolTexture(name: string, color: string): { texture: THREE.CanvasTexture; aspect: number } {
  const fontSize = 44;
  const pad = 28;
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas context unavailable");
  const font = `600 ${fontSize}px "JetBrains Mono", ui-monospace, monospace`;
  ctx.font = font;
  const metrics = ctx.measureText(name);
  canvas.width = Math.ceil(metrics.width + pad * 2);
  canvas.height = fontSize + pad * 2;
  ctx.font = font;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  // Two passes: wide soft glow, then crisp core text
  ctx.shadowColor = color;
  ctx.shadowBlur = 22;
  ctx.fillStyle = color;
  ctx.fillText(name, canvas.width / 2, canvas.height / 2);
  ctx.shadowBlur = 6;
  ctx.fillStyle = "#eaf2ff";
  ctx.fillText(name, canvas.width / 2, canvas.height / 2);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return { texture, aspect: canvas.width / canvas.height };
}

export default function ToolStorm({ className }: { className?: string }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const isMobile = window.innerWidth < 768;

    // --- Renderer / scene / camera -------------------------------------
    // three throws synchronously when no WebGL context can be created
    // (webgl.disabled, some VDI/remote-desktop setups, software-only VMs).
    // The hero's CSS gradient is a perfectly good fallback, so bail quietly
    // instead of letting the error unmount the whole route.
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({
        antialias: !isMobile,
        alpha: true,
        // Mobile GPUs: let the browser pick the power-efficient GPU.
        powerPreference: isMobile ? "default" : "high-performance",
      });
    } catch {
      return;
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.setSize(container.clientWidth, container.clientHeight);
    renderer.setClearColor(0x000000, 0);
    renderer.domElement.style.display = "block";
    container.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    // Fog fades distant particles into the page's navy background
    scene.fog = new THREE.FogExp2(PALETTE.bg, 0.03);

    const camera = new THREE.PerspectiveCamera(
      60,
      container.clientWidth / Math.max(container.clientHeight, 1),
      0.1,
      100,
    );
    camera.position.set(0, 2.4, CAMERA_BASE_Z);

    const disposables: Array<{ dispose: () => void }> = [];
    // One AbortController tears down every listener; also used to ignore
    // async work (font loading) that resolves after unmount.
    const controller = new AbortController();
    const { signal } = controller;
    const stormGroup = new THREE.Group();
    scene.add(stormGroup);

    // --- Particle vortex -------------------------------------------------
    const PARTICLE_COUNT = isMobile ? 2200 : 6000;
    const positions = new Float32Array(PARTICLE_COUNT * 3);
    const colors = new Float32Array(PARTICLE_COUNT * 3);
    const tmpColor = new THREE.Color();

    // Inner regions run hot (green/white); outer arms cool into cyan,
    // purple, and magenta — the classic galaxy gradient in Tokyo Night hues.
    for (let i = 0; i < PARTICLE_COUNT; i++) {
      const radius = Math.pow(Math.random(), 0.65) * STORM_RADIUS;
      const arm = i % ARM_COUNT;
      const angle =
        (arm / ARM_COUNT) * Math.PI * 2 + radius * ARM_TWIST + randn() * 0.35;
      const spread = 0.5 + radius * 0.1;

      const i3 = i * 3;
      positions[i3] = Math.cos(angle) * radius + randn() * spread;
      positions[i3 + 1] = randn() * (1.5 * Math.exp(-radius / 7) + 0.35);
      positions[i3 + 2] = Math.sin(angle) * radius + randn() * spread;

      if (radius < 3.5) {
        tmpColor.setHex(Math.random() < 0.6 ? PALETTE.green : PALETTE.white);
      } else if (radius < 8) {
        tmpColor.setHex(pick([PALETTE.green, PALETTE.cyan, PALETTE.cyan, PALETTE.amber]));
      } else {
        tmpColor.setHex(pick([PALETTE.cyan, PALETTE.purple, PALETTE.purple, PALETTE.magenta]));
      }
      // Per-particle brightness jitter keeps the field from looking flat
      const brightness = 0.55 + Math.random() * 0.45;
      colors[i3] = tmpColor.r * brightness;
      colors[i3 + 1] = tmpColor.g * brightness;
      colors[i3 + 2] = tmpColor.b * brightness;
    }

    const particleGeometry = new THREE.BufferGeometry();
    particleGeometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    particleGeometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
    const particleMaterial = new THREE.PointsMaterial({
      size: isMobile ? 0.09 : 0.07,
      sizeAttenuation: true,
      vertexColors: true,
      transparent: true,
      opacity: 0.9,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    stormGroup.add(new THREE.Points(particleGeometry, particleMaterial));
    disposables.push(particleGeometry, particleMaterial);

    // --- Flywheel core ----------------------------------------------------
    const coreGlowTexture = makeGlowTexture("rgba(240, 248, 255, 0.95)", "rgba(158, 206, 106, 0.55)");
    const coreMaterial = new THREE.SpriteMaterial({
      map: coreGlowTexture,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const core = new THREE.Sprite(coreMaterial);
    core.scale.setScalar(6);
    stormGroup.add(core);
    disposables.push(coreGlowTexture, coreMaterial);

    const hotCoreTexture = makeGlowTexture("rgba(255, 255, 255, 1)", "rgba(224, 175, 104, 0.7)");
    const hotCoreMaterial = new THREE.SpriteMaterial({
      map: hotCoreTexture,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const hotCore = new THREE.Sprite(hotCoreMaterial);
    hotCore.scale.setScalar(2);
    stormGroup.add(hotCore);
    disposables.push(hotCoreTexture, hotCoreMaterial);

    // Thin tilted torus — the "spinning wheel" reading
    const wheel = new THREE.Group();
    const ringGeometry = new THREE.TorusGeometry(3.4, 0.035, 8, 160);
    const ringMaterial = new THREE.MeshBasicMaterial({
      color: PALETTE.green,
      transparent: true,
      opacity: 0.75,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const ring = new THREE.Mesh(ringGeometry, ringMaterial);
    ring.rotation.x = Math.PI / 2 - 0.35;
    wheel.add(ring);
    const haloGeometry = new THREE.TorusGeometry(3.4, 0.12, 8, 160);
    const haloMaterial = new THREE.MeshBasicMaterial({
      color: PALETTE.purple,
      transparent: true,
      opacity: 0.18,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const halo = new THREE.Mesh(haloGeometry, haloMaterial);
    halo.rotation.x = Math.PI / 2 - 0.35;
    wheel.add(halo);
    stormGroup.add(wheel);
    disposables.push(ringGeometry, ringMaterial, haloGeometry, haloMaterial);

    // --- Tool-name sprites -------------------------------------------------
    const toolSprites: ToolSprite[] = [];
    const up = new THREE.Vector3(0, 1, 0);
    TOOL_NAMES.forEach((name, index) => {
      const color = SPRITE_COLORS[index % SPRITE_COLORS.length] as string;
      const { texture, aspect } = makeToolTexture(name, color);
      const material = new THREE.SpriteMaterial({
        map: texture,
        transparent: true,
        depthWrite: false,
        opacity: 0.9,
      });
      const sprite = new THREE.Sprite(material);
      const height = 0.5;
      sprite.scale.set(height * aspect, height, 1);

      // Randomly inclined orbital plane, biased toward the galactic plane so
      // sprites read as part of the vortex rather than a sphere around it.
      const normal = new THREE.Vector3(randn() * 0.45, 1 + Math.abs(randn()) * 0.5, randn() * 0.45).normalize();
      const planeU = new THREE.Vector3().crossVectors(normal, up).normalize();
      const planeV = new THREE.Vector3().crossVectors(normal, planeU).normalize();

      toolSprites.push({
        sprite,
        material,
        planeU,
        planeV,
        radius: 4.5 + Math.random() * 9,
        speed: (0.08 + Math.random() * 0.16) * (Math.random() < 0.12 ? -1 : 1),
        phase: Math.random() * Math.PI * 2,
        baseOpacity: 0.55 + Math.random() * 0.35,
        pulseSpeed: 0.5 + Math.random() * 1.2,
        pulsePhase: Math.random() * Math.PI * 2,
      });
      stormGroup.add(sprite);
      disposables.push(texture, material);
    });

    // The labels are baked onto <canvas> with "JetBrains Mono". With
    // font-display: swap the webfont is usually not ready on first paint, so
    // every sprite would be rasterised in the fallback face. Re-bake once the
    // real font is available (no-op if it already was).
    if (typeof document.fonts?.load === "function") {
      document.fonts
        .load('600 44px "JetBrains Mono"')
        .then(() => {
          if (signal.aborted) return;
          toolSprites.forEach((tool, index) => {
            const color = SPRITE_COLORS[index % SPRITE_COLORS.length] as string;
            const { texture, aspect } = makeToolTexture(TOOL_NAMES[index] as string, color);
            tool.material.map?.dispose();
            tool.material.map = texture;
            tool.material.needsUpdate = true;
            tool.sprite.scale.set(0.5 * aspect, 0.5, 1);
            disposables.push(texture);
          });
          if (prefersReducedMotion) renderer.render(scene, camera);
        })
        .catch(() => {
          /* font unavailable — keep the fallback rasterisation */
        });
    }

    // --- Interaction state ---------------------------------------------------
    let raf = 0;
    let running = false;
    let angularVel = 0; // flick velocity from pointer drag, rad/s
    let dragging = false;
    let lastPointerX = 0;
    const mouse = { x: 0, y: 0 };
    let scrollZoom = 0; // 0..1 while the hero is on screen
    const clock = new THREE.Clock();

    const renderFrame = (dt: number) => {
      const elapsed = clock.elapsedTime;

      // Spin: constant base + flick inertia with exponential damping
      stormGroup.rotation.y += (BASE_SPIN + angularVel) * dt;
      angularVel *= Math.exp(-DRAG_DAMPING * dt);
      wheel.rotation.z += 0.4 * dt;
      core.scale.setScalar(6 + Math.sin(elapsed * 1.4) * 0.25);

      // Camera parallax toward the pointer, plus scroll-driven dive
      const damp = 1 - Math.exp(-3 * dt);
      camera.position.x += (mouse.x * 1.3 - camera.position.x) * damp;
      camera.position.y += (2.4 - mouse.y * 0.9 - camera.position.y) * damp;
      camera.position.z += (CAMERA_BASE_Z - scrollZoom * 1.8 - camera.position.z) * damp;
      camera.lookAt(0, 0.3, 0);
      camera.rotation.x -= scrollZoom * 0.12;

      // Orbit + opacity-pulse every tool sprite
      for (const tool of toolSprites) {
        const a = tool.phase + elapsed * tool.speed;
        tool.sprite.position
          .copy(tool.planeU)
          .multiplyScalar(Math.cos(a) * tool.radius)
          .addScaledVector(tool.planeV, Math.sin(a) * tool.radius);
        tool.material.opacity =
          tool.baseOpacity * (0.78 + 0.22 * Math.sin(elapsed * tool.pulseSpeed + tool.pulsePhase));
      }

      renderer.render(scene, camera);
    };

    const loop = () => {
      raf = requestAnimationFrame(loop);
      const dt = Math.min(clock.getDelta(), 0.05);
      renderFrame(dt);
    };

    const start = () => {
      if (running || prefersReducedMotion) return;
      running = true;
      clock.getDelta(); // drop the pause gap so the first frame doesn't jump
      loop();
    };

    const stop = () => {
      running = false;
      cancelAnimationFrame(raf);
    };

    // --- Listeners (all via the shared AbortController for clean teardown) ---
    const onPointerMove = (event: PointerEvent) => {
      if (dragging) {
        angularVel = THREE.MathUtils.clamp(
          angularVel + (event.clientX - lastPointerX) * 0.0035,
          -1.5,
          1.5,
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
    // fires pointercancel (never pointerup) — without this `dragging` sticks
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
    renderer.domElement.addEventListener("webglcontextrestored", () => start(), { signal });

    const onScroll = () => {
      const heroHeight = Math.max(window.innerHeight, 1);
      scrollZoom = THREE.MathUtils.clamp(window.scrollY / heroHeight, 0, 1);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true, signal });

    // Pause whenever the hero is not being looked at: tab in the background
    // OR scrolled past. The page is ~5 screens tall; 6000 additive points at
    // 60fps while the user reads the tool index is pure battery burn.
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

    const onResize = () => {
      const width = container.clientWidth;
      const height = Math.max(container.clientHeight, 1);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height);
      if (prefersReducedMotion) renderer.render(scene, camera);
    };
    window.addEventListener("resize", onResize, { signal });

    // --- Reduced motion: one composed frame, no loop -------------------------
    if (prefersReducedMotion) {
      stormGroup.rotation.y = 0.6;
      renderFrame(0);
    } else {
      start();
    }

    // --- Full teardown --------------------------------------------------------
    return () => {
      stop();
      observer.disconnect();
      controller.abort();
      for (const disposable of disposables) disposable.dispose();
      scene.clear();
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);

  return (
    <div
      ref={containerRef}
      className={className}
      aria-hidden="true"
      // Allow vertical page scroll on touch; horizontal drags spin the storm
      style={{ touchAction: "pan-y" }}
    />
  );
}
