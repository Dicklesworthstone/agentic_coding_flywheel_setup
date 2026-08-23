"use client";

import { useEffect, useRef } from "react";
import * as THREE from "three";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/examples/jsm/postprocessing/OutputPass.js";

/**
 * ToolStorm v2 — a tilted accretion-disk vortex of 16k GPU-animated particles
 * with real bloom, off-centered to the right so the hero's text column stays
 * on clean navy. Tool-name sprites ride the disk's differential rotation and
 * auto-fade whenever their projected position would cross the text column.
 *
 * Guards:
 * - DPR ≤ 1.5, adaptive down-grade to 1 if the warm-up FPS probe sags
 * - RAF loop pauses while document.hidden or the hero is scrolled off-screen
 * - no WebGL available → component renders nothing (CSS gradient hero remains)
 * - lost GL context stops the loop; restored context resumes it
 * - prefers-reduced-motion renders a single composed frame, no animation
 * - full teardown via AbortController + explicit disposal, aria-hidden canvas
 */

const PALETTE = {
  bg: 0x0a0e1a,
  green: "#9ece6a",
  cyan: "#7dcfff",
  purple: "#bb9af7",
  magenta: "#f7768e",
  amber: "#e0af68",
} as const;

// Tools rendered as glowing name plates riding the disk. Binary names as they
// land on PATH (see lib/generated/manifest-tools.ts). Kept to a readable
// handful: the full index lives further down the page.
const TOOL_NAMES = [
  "ntm", "cass", "am", "dcg", "bv", "slb", "ubs", "cm",
  "ru", "rch", "fsfs", "caam", "ee", "ms", "pt", "asb", "jfp", "br",
] as const;

const SPRITE_COLORS = [PALETTE.green, PALETTE.cyan, PALETTE.purple, PALETTE.amber] as const;

/** Disk geometry tuning */
const DISK_RADIUS = 16;
const ARM_COUNT = 3;
const SPIRAL_PITCH = 2.6; // strength of the log-spiral winding
const SHEAR = 0.55; // differential-rotation strength (higher = more shear)
const DISK_TILT_X = -1.08; // radians — how far the disk tips toward camera
const DISK_TILT_Z = 0.22;
const STORM_OFFSET_X = 3.4; // world units right — reserves the text column
const CAMERA_Z = 13.2;
const PLATE_HEIGHT = 0.8;

/** Approximate standard normal (Irwin–Hall, n=3). */
function randn(): number {
  return Math.random() + Math.random() + Math.random() - 1.5;
}

function pick<T>(items: readonly T[]): T {
  return items[Math.floor(Math.random() * items.length)] as T;
}

/** Color ramp by disk radius: white-gold core → green → cyan → purple/magenta rim. */
function diskColor(r: number): THREE.Color {
  const c = new THREE.Color();
  if (r < 2.0) c.set(pick(["#fff6df", "#ffe9b8", PALETTE.amber]));
  else if (r < 4.5) c.set(pick([PALETTE.green, "#d7ffab", PALETTE.cyan]));
  else if (r < 8.5) c.set(pick([PALETTE.cyan, PALETTE.green, PALETTE.purple, "#89ddff"]));
  else if (r < 12.5) c.set(pick([PALETTE.purple, "#89b4fa", PALETTE.magenta]));
  else c.set(pick(["#565f89", PALETTE.magenta, "#414868"]));
  return c;
}

/** Radial-gradient glow texture. */
function makeGlowTexture(inner: string, mid: string): THREE.CanvasTexture {
  const size = 256;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas context unavailable");
  const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  g.addColorStop(0, inner);
  g.addColorStop(0.22, mid);
  g.addColorStop(1, "rgba(10, 14, 26, 0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, size, size);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Monospace tool-name plate with neon glow. */
function makeToolTexture(name: string, color: string): { texture: THREE.CanvasTexture; aspect: number } {
  const fontSize = 52;
  const pad = 30;
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas context unavailable");
  const font = `700 ${fontSize}px "JetBrains Mono", ui-monospace, monospace`;
  ctx.font = font;
  const metrics = ctx.measureText(name);
  canvas.width = Math.ceil(metrics.width + pad * 2);
  canvas.height = fontSize + pad * 2;
  ctx.font = font;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  // Backing plate: translucent dark pill keeps names legible over particles
  const r = 14;
  ctx.fillStyle = "rgba(10, 14, 26, 0.62)";
  ctx.beginPath();
  ctx.roundRect(4, 4, canvas.width - 8, canvas.height - 8, r);
  ctx.fill();
  ctx.strokeStyle = `${color}66`;
  ctx.lineWidth = 2;
  ctx.stroke();
  // Glow pass then crisp core
  ctx.shadowColor = color;
  ctx.shadowBlur = 24;
  ctx.fillStyle = color;
  ctx.fillText(name, canvas.width / 2, canvas.height / 2 + 1);
  ctx.shadowBlur = 0;
  ctx.fillStyle = "#f2f7ff";
  ctx.fillText(name, canvas.width / 2, canvas.height / 2 + 1);
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

    // three throws synchronously when no WebGL context can be created
    // (webgl.disabled, some VDI/remote-desktop setups, software-only VMs).
    // The hero's CSS gradient is a perfectly good fallback, so bail quietly
    // instead of letting the error unmount the whole route.
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({
        antialias: false,
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
    scene.fog = new THREE.FogExp2(PALETTE.bg, 0.024);

    const camera = new THREE.PerspectiveCamera(
      58,
      container.clientWidth / Math.max(container.clientHeight, 1),
      0.1,
      200,
    );
    camera.position.set(0, 2.7, CAMERA_Z);

    const disposables: Array<{ dispose: () => void }> = [];
    // One AbortController tears down every listener; also used to ignore
    // async work (font loading) that resolves after unmount.
    const controller = new AbortController();
    const { signal } = controller;

    const disk = new THREE.Group();
    disk.position.set(STORM_OFFSET_X, -0.4, 0);
    disk.rotation.x = DISK_TILT_X;
    disk.rotation.z = DISK_TILT_Z;
    scene.add(disk);

    // --- Distant static starfield (depth backdrop) -------------------------
    {
      const STAR_COUNT = isMobile ? 350 : 900;
      const positions = new Float32Array(STAR_COUNT * 3);
      for (let i = 0; i < STAR_COUNT; i++) {
        const v = new THREE.Vector3().randomDirection().multiplyScalar(60 + Math.random() * 40);
        positions[i * 3] = v.x;
        positions[i * 3 + 1] = v.y;
        positions[i * 3 + 2] = v.z;
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
      const mat = new THREE.PointsMaterial({
        color: 0xc0caf5,
        size: 0.9,
        sizeAttenuation: false,
        transparent: true,
        opacity: 0.45,
        depthWrite: false,
      });
      const stars = new THREE.Points(geo, mat);
      scene.add(stars);
      disposables.push(geo, mat);
    }

    // --- Particle disk (GPU-animated) --------------------------------------
    const PARTICLES = isMobile ? 6000 : 16000;
    const radiusAttr = new Float32Array(PARTICLES);
    const angleAttr = new Float32Array(PARTICLES);
    const speedAttr = new Float32Array(PARTICLES);
    const yAttr = new Float32Array(PARTICLES);
    const sizeAttr = new Float32Array(PARTICLES);
    const seedAttr = new Float32Array(PARTICLES);
    const colorArr = new Float32Array(PARTICLES * 3);
    const tmpColor = new THREE.Color();

    for (let i = 0; i < PARTICLES; i++) {
      const i3 = i * 3;
      // Radius: dense toward center, long tail outward
      const r = Math.pow(Math.random(), 0.72) * DISK_RADIUS + 0.4;
      radiusAttr[i] = r;

      // Three log-spiral arms + scatter that widens with radius
      const arm = (i % ARM_COUNT) * ((Math.PI * 2) / ARM_COUNT);
      const scatter = 0.22 + (r / DISK_RADIUS) * 0.85;
      angleAttr[i] = arm + SPIRAL_PITCH * Math.log(r + 1) + randn() * scatter;

      // Differential (Keplerian-ish) rotation: inner orbits much faster
      speedAttr[i] = (1.15 / Math.pow(r + 0.9, 0.85)) * SHEAR;

      // Disk thickness: central bulge, thin rim
      yAttr[i] = randn() * (1.35 * Math.exp(-r / 4.2) + 0.16);
      // Power-law sizes: mostly dust, occasional bright stars
      sizeAttr[i] = 1.4 + Math.pow(Math.random(), 3.2) * 5.2;
      seedAttr[i] = Math.random();

      tmpColor.copy(diskColor(r));
      // Brightness jitter, hotter inward
      const b = (0.5 + Math.random() * 0.5) * (r < 3 ? 1.25 : 1);
      colorArr[i3] = tmpColor.r * b;
      colorArr[i3 + 1] = tmpColor.g * b;
      colorArr[i3 + 2] = tmpColor.b * b;
    }

    const particleGeo = new THREE.BufferGeometry();
    particleGeo.setAttribute("position", new THREE.BufferAttribute(new Float32Array(PARTICLES * 3), 3)); // unused by shader but required
    particleGeo.setAttribute("aRadius", new THREE.BufferAttribute(radiusAttr, 1));
    particleGeo.setAttribute("aAngle", new THREE.BufferAttribute(angleAttr, 1));
    particleGeo.setAttribute("aSpeed", new THREE.BufferAttribute(speedAttr, 1));
    particleGeo.setAttribute("aY", new THREE.BufferAttribute(yAttr, 1));
    particleGeo.setAttribute("aSize", new THREE.BufferAttribute(sizeAttr, 1));
    particleGeo.setAttribute("aSeed", new THREE.BufferAttribute(seedAttr, 1));
    particleGeo.setAttribute("aColor", new THREE.BufferAttribute(colorArr, 3));
    particleGeo.boundingSphere = new THREE.Sphere(new THREE.Vector3(), DISK_RADIUS + 4);

    const particleUniforms = { uTime: { value: 0 }, uPixelRatio: { value: pixelRatio } };
    const particleMat = new THREE.ShaderMaterial({
      uniforms: particleUniforms,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      vertexShader: /* glsl */ `
        attribute float aRadius;
        attribute float aAngle;
        attribute float aSpeed;
        attribute float aY;
        attribute float aSize;
        attribute float aSeed;
        attribute vec3 aColor;
        uniform float uTime;
        uniform float uPixelRatio;
        varying vec3 vColor;
        varying float vTwinkle;
        void main() {
          float angle = aAngle + uTime * aSpeed;
          vec3 pos = vec3(cos(angle) * aRadius, aY, sin(angle) * aRadius);
          vec4 mv = modelViewMatrix * vec4(pos, 1.0);
          gl_PointSize = aSize * uPixelRatio * (95.0 / max(-mv.z, 0.1));
          vColor = aColor;
          vTwinkle = 0.7 + 0.3 * sin(uTime * (1.2 + fract(aSeed) * 2.4) + aSeed * 41.7);
          gl_Position = projectionMatrix * mv;
        }
      `,
      fragmentShader: /* glsl */ `
        varying vec3 vColor;
        varying float vTwinkle;
        void main() {
          vec2 uv = gl_PointCoord - 0.5;
          float d = length(uv);
          float alpha = smoothstep(0.5, 0.06, d);
          alpha *= alpha;
          gl_FragColor = vec4(vColor * vTwinkle, alpha);
        }
      `,
    });
    const particles = new THREE.Points(particleGeo, particleMat);
    particles.frustumCulled = false;
    disk.add(particles);
    disposables.push(particleGeo, particleMat);

    // --- Flywheel core -------------------------------------------------------
    const glowA = makeGlowTexture("rgba(255, 250, 235, 1)", "rgba(158, 206, 106, 0.6)");
    const glowB = makeGlowTexture("rgba(255, 255, 255, 1)", "rgba(224, 175, 104, 0.75)");
    const coreMatA = new THREE.SpriteMaterial({
      map: glowA,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const coreMatB = new THREE.SpriteMaterial({
      map: glowB,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const coreOuter = new THREE.Sprite(coreMatA);
    coreOuter.scale.setScalar(4.6);
    disk.add(coreOuter);
    const coreInner = new THREE.Sprite(coreMatB);
    coreInner.scale.setScalar(1.7);
    disk.add(coreInner);
    disposables.push(glowA, coreMatA, glowB, coreMatB);

    const composer = new EffectComposer(renderer);
    composer.setPixelRatio(pixelRatio);
    composer.setSize(container.clientWidth, container.clientHeight);
    composer.addPass(new RenderPass(scene, camera));
    const bloom = new UnrealBloomPass(
      new THREE.Vector2(container.clientWidth, container.clientHeight),
      0.42, // strength
      0.5, // radius
      0.42, // threshold — mid particles stay clean; only the core and hot stars bloom
    );
    composer.addPass(bloom);
    composer.addPass(new OutputPass());
    disposables.push(bloom, composer as unknown as { dispose: () => void });

    // Bright rim ring + soft halo, lying in the disk plane
    const ringGeo = new THREE.TorusGeometry(3.6, 0.05, 8, 180);
    const ringMat = new THREE.MeshBasicMaterial({
      color: 0xb8ee7a,
      transparent: true,
      opacity: 0.85,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.rotation.x = Math.PI / 2;
    disk.add(ring);
    const haloGeo = new THREE.TorusGeometry(3.6, 0.22, 8, 180);
    const haloMat = new THREE.MeshBasicMaterial({
      color: 0xbb9af7,
      transparent: true,
      opacity: 0.22,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });
    const halo = new THREE.Mesh(haloGeo, haloMat);
    halo.rotation.x = Math.PI / 2;
    disk.add(halo);
    disposables.push(ringGeo, ringMat, haloGeo, haloMat);

    // --- Tool-name sprites riding the disk -----------------------------------
    interface ToolRider {
      sprite: THREE.Sprite;
      material: THREE.SpriteMaterial;
      radius: number;
      angle: number;
      speed: number;
      baseOpacity: number;
    }
    const riders: ToolRider[] = [];
    TOOL_NAMES.forEach((name, index) => {
      const color = SPRITE_COLORS[index % SPRITE_COLORS.length];
      const { texture, aspect } = makeToolTexture(name, color);
      const material = new THREE.SpriteMaterial({
        map: texture,
        transparent: true,
        depthWrite: false,
        opacity: 0,
      });
      const sprite = new THREE.Sprite(material);
      sprite.scale.set(PLATE_HEIGHT * aspect, PLATE_HEIGHT, 1);
      const radius = 5.2 + ((index * 2.7) % 8.5) + Math.random() * 1.2;
      riders.push({
        sprite,
        material,
        radius,
        angle: (index / TOOL_NAMES.length) * Math.PI * 2 + Math.random() * 0.8,
        speed: (1.15 / Math.pow(radius + 0.9, 0.85)) * SHEAR,
        baseOpacity: 1,
      });
      disk.add(sprite);
      disposables.push(texture, material);
    });

    // The plates are baked onto <canvas> with "JetBrains Mono". With
    // font-display: swap the webfont is usually not ready on first paint, so
    // every plate would be rasterised in the fallback face. Re-bake once the
    // real font is available (no-op if it already was).
    if (typeof document.fonts?.load === "function") {
      document.fonts
        .load('700 52px "JetBrains Mono"')
        .then(() => {
          if (signal.aborted) return;
          riders.forEach((rider, index) => {
            const color = SPRITE_COLORS[index % SPRITE_COLORS.length];
            const { texture, aspect } = makeToolTexture(TOOL_NAMES[index] as string, color);
            rider.material.map?.dispose();
            rider.material.map = texture;
            rider.material.needsUpdate = true;
            rider.sprite.scale.set(PLATE_HEIGHT * aspect, PLATE_HEIGHT, 1);
            disposables.push(texture);
          });
          if (prefersReducedMotion) composer.render();
        })
        .catch(() => {
          /* font unavailable — keep the fallback rasterisation */
        });
    }

    // --- Interaction state ----------------------------------------------------
    let raf = 0;
    let running = false;
    let angularVel = 0;
    let dragging = false;
    let lastPointerX = 0;
    const mouse = { x: 0, y: 0 };
    let scrollDive = 0;
    const clock = new THREE.Clock();
    const projHelper = new THREE.Vector3();

    // Adaptive quality: if the average FPS sags early, drop internal resolution
    let warmupFrames = 0;
    let warmupTime = 0;
    let qualityDegraded = false;

    const applyFrame = (dt: number) => {
      const t = clock.elapsedTime;
      particleUniforms.uTime.value = t;

      // Rigid slow precession + flick inertia; the shader handles shear
      disk.rotation.y += (0.02 + angularVel) * dt;
      angularVel *= Math.exp(-1.7 * dt);
      ring.rotation.z += 0.5 * dt;
      halo.rotation.z -= 0.3 * dt;
      coreOuter.scale.setScalar(7 + Math.sin(t * 1.2) * 0.35);

      // Camera: parallax toward pointer + scroll-driven dive
      const damp = 1 - Math.exp(-3 * dt);
      camera.position.x += (mouse.x * 0.9 - camera.position.x) * damp;
      camera.position.y += (2.7 - mouse.y * 0.7 - camera.position.y) * damp;
      camera.position.z += (CAMERA_Z - scrollDive * 1.6 - camera.position.z) * damp;
      camera.lookAt(STORM_OFFSET_X * 0.55, 0.1, 0);

      // Tool riders: Keplerian orbit on the disk plane…
      for (const rider of riders) {
        rider.angle += rider.speed * dt;
        rider.sprite.position.set(
          Math.cos(rider.angle) * rider.radius,
          Math.sin(rider.angle * 0.5) * 0.12,
          Math.sin(rider.angle) * rider.radius,
        );

        // …projected into screen space so we can fade them out of the
        // left-hand text column and dim far-side plates.
        projHelper.copy(rider.sprite.position).applyMatrix4(disk.matrixWorld).project(camera);
        const inTextZone = projHelper.x < -0.52 && projHelper.z < 1;
        const depthDim = THREE.MathUtils.clamp(1.25 - (projHelper.z + 1) * 0.5, 0.35, 1);
        const target = (inTextZone ? 0.1 : 1) * depthDim * rider.baseOpacity;
        rider.material.opacity += (target - rider.material.opacity) * Math.min(dt * 6, 1);
      }

      composer.render();
    };

    const loop = () => {
      raf = requestAnimationFrame(loop);
      const dt = Math.min(clock.getDelta(), 0.05);
      applyFrame(dt);

      // Warmup FPS probe → degrade resolution once if this GPU struggles
      if (!qualityDegraded && warmupFrames < 120) {
        warmupFrames += 1;
        warmupTime += dt;
        if (warmupFrames === 120) {
          const fps = warmupFrames / warmupTime;
          if (fps < 40) {
            qualityDegraded = true;
            pixelRatio = 1;
            renderer.setPixelRatio(pixelRatio);
            composer.setPixelRatio(pixelRatio);
            composer.setSize(container.clientWidth, container.clientHeight);
            particleUniforms.uPixelRatio.value = pixelRatio;
          }
        }
      }
    };

    const start = () => {
      if (running || prefersReducedMotion) return;
      running = true;
      clock.getDelta(); // swallow the pause gap
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
          angularVel + (event.clientX - lastPointerX) * 0.004,
          -1.8,
          1.8,
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
      scrollDive = THREE.MathUtils.clamp(window.scrollY / Math.max(window.innerHeight, 1), 0, 1);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true, signal });

    // Pause whenever the hero is not being looked at: tab in the background
    // OR scrolled past. The page is ~5 screens tall; 16k particles plus a
    // bloom pass at 60fps while the user reads the tool index is pure battery
    // burn.
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
      composer.setSize(width, height);
      if (prefersReducedMotion) composer.render();
    };
    window.addEventListener("resize", onResize, { signal });

    // Reduced motion: one composed frame, no loop
    if (prefersReducedMotion) {
      particleUniforms.uTime.value = 42; // developed spiral for the still frame
      disk.rotation.y = 0.5;
      for (const rider of riders) {
        rider.material.opacity = rider.baseOpacity;
        rider.sprite.position.set(
          Math.cos(rider.angle) * rider.radius,
          0,
          Math.sin(rider.angle) * rider.radius,
        );
      }
      composer.render();
    } else {
      start();
    }

    // --- Teardown ----------------------------------------------------------------
    return () => {
      stop();
      observer.disconnect();
      controller.abort();
      for (const d of disposables) d.dispose();
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
      style={{ touchAction: "pan-y" }}
    />
  );
}
