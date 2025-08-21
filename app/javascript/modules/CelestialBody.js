import * as THREE from "three";
import { createOrbit } from "OrbitCreator";

export class CelestialBody {
   constructor(scene, animationController, camera) {
    this.scene = scene;
    this.animationController = animationController;
    this.camera = camera;
    this.bodies = [];
    this.labels = [];

    this.SCALE_POS  = 5;   // Mkm → scene units (positions)
    this.SCALE_SIZE = 100;  // visual size shrink factor

    this.animationController.unitScale    = this.SCALE_POS;
    this.animationController.orbitPadding = 1;

    this.minPeriapsisScene = Infinity;
    this.starMesh = null;
    this.baseStarRadius = 10;
  }

  addCelestialBody(data, size, color, name, starMassInput) {
    const centralMass =
      starMassInput ??
      data.starMass ?? data.starmass ?? data.mass ?? 0;

    const geometry = new THREE.SphereGeometry(size, 32, 32);
    const material = new THREE.MeshBasicMaterial({ color });
    const body = new THREE.Mesh(geometry, material);

if (data["classification"] === "star_system") {
  const starVisualScale = 1 / this.SCALE_SIZE;
  body.scale.set(starVisualScale, starVisualScale, starVisualScale);

  this.starMesh = body;
  this.animationController.setStar({ mesh: body, name, mass: centralMass });

  // ⭐ label + expose to controller so it can update every frame
  this.starLabel = this.addLabel(name, body, this.camera);
  this.animationController.starLabel = this.starLabel;

  this.scene.add(body);
  this.bodies.push(body);

  // 👇 ensure it’s visible even before any planets set periapsis
  const minStarRadiusScene = 3.0;
  const currentRadiusScene = this.baseStarRadius * (1 / this.SCALE_SIZE);
  if (currentRadiusScene < minStarRadiusScene) {
    const needed = minStarRadiusScene / currentRadiusScene;
    body.scale.multiplyScalar(needed);
  }

  this.resizeStarIfNeeded?.();
  return;
}


    if (data["classification"] === "planet") {
const aReal  = (data.apoapsis + data.periapsis) / 2;      // Mkm (real units for physics)
const aScene = aReal / this.SCALE_POS;                     // scene units (for rendering)
const e      = (data.apoapsis - data.periapsis) / (data.apoapsis + data.periapsis);

      const periapsisScene = (data.periapsis) / this.SCALE_POS;
      this.minPeriapsisScene = Math.min(this.minPeriapsisScene ?? Infinity, periapsisScene);

      // ✅ keep planets visible: don’t let them get microscopic
      const baseScale = 1 / this.SCALE_SIZE;
      const minScale  = 0.35;                  // <-- tune: guaranteed visual size
      const bodyScale = Math.max(baseScale, minScale);
      body.scale.set(bodyScale, bodyScale, bodyScale);

      const orbitalSpeed = this.calculateOrbitalSpeed(aScene, centralMass);

      const planet = {
        mesh: body,
        semiMajorAxis: aScene,         // for drawing
        semiMajorAxisReal: aReal,      // for physics
        eccentricity: e,
        orbitalSpeed,
        name,
        starMass: centralMass,
        size,
        // ✅ pass the mesh so the label can compute real radius
        label: this.addLabel(name, body, this.camera)
      };

      this.animationController.addPlanet(planet);
      this.scene.add(body);
      this.bodies.push(body);
      this.resizeStarIfNeeded?.();
    }
  }

calculateOrbitalSpeed(semiMajorAxis, starMass) {
  const G = this.animationController?.G ?? 6.67430e-38; // ✅
  return Math.sqrt((G * starMass) / semiMajorAxis);
}

// helper: world radius (scene units) from a mesh
getWorldRadius(mesh) {
  const geomR =
    mesh.geometry?.parameters?.radius ??
    mesh.geometry?.boundingSphere?.radius ??
    1;
  return geomR * mesh.scale.x;
}

// helper: set world radius (scene units) on a mesh
setWorldRadius(mesh, targetR) {
  const geomR =
    mesh.geometry?.parameters?.radius ??
    mesh.geometry?.boundingSphere?.radius ??
    1;
  const targetScale = targetR / geomR;
  mesh.scale.setScalar(targetScale); // absolute set, not multiply
}

resizeStarIfNeeded() {
  if (!this.starMesh) return;

  // If we don't have a valid periapsis yet, make the star reasonably visible and bail.
  if (!Number.isFinite(this.minPeriapsisScene) || this.minPeriapsisScene <= 0 || this.minPeriapsisScene === Infinity) {
    const fallbackR = 3.0; // always-visible size
    this.setWorldRadius(this.starMesh, fallbackR);
    this.animationController.orbitPadding = 1;

    // keep camera out of the shell
    this.ensureCameraOutsideStar?.(this.camera, this.starMesh);
    if (this.animationController?.controls) {
      this.animationController.controls.minDistance = this.getWorldRadius(this.starMesh) * 1.2;
      this.animationController.controls.update?.();
    }
    return;
  }

  // Normal path once we have a valid periapsis
  const minR = 2.0;
  const maxR = this.minPeriapsisScene * 0.2;
  const targetStarRadiusScene = THREE.MathUtils.clamp(this.minPeriapsisScene * 0.15, minR, maxR);

  this.setWorldRadius(this.starMesh, targetStarRadiusScene);

  const requiredPadding = (targetStarRadiusScene * 1.1) / this.minPeriapsisScene;
  this.animationController.orbitPadding = Number.isFinite(requiredPadding) ? Math.max(1, requiredPadding) : 1;

  // keep camera out of the star after resizing
  this.ensureCameraOutsideStar?.(this.camera, this.starMesh);
  if (this.animationController?.controls) {
    this.animationController.controls.minDistance = this.getWorldRadius(this.starMesh) * 1.2;
    this.animationController.controls.update?.();
  }
}



  // ✅ compute label offset/scale from the *actual* mesh radius
addLabel(name, mesh, camera) {
  const renderer = this.animationController?.renderer;
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const pad = 10;          // px padding
  const fontPx = 16;       // base CSS pixels (tweak for taste)

  // 1) measure text at DPR
  const meas = document.createElement('canvas').getContext('2d');
  meas.font = `${fontPx * dpr}px Arial`;
  const textW = Math.ceil(meas.measureText(name).width);
  const textH = Math.ceil(fontPx * dpr);

  // 2) paint to a DPR canvas
  const canvas = document.createElement('canvas');
  canvas.width  = textW + pad * dpr * 2;
  canvas.height = textH + pad * dpr * 2;
  const ctx = canvas.getContext('2d');
  ctx.font = `${fontPx * dpr}px Arial`;
  ctx.fillStyle = 'rgba(255,255,255,1)';
  ctx.textBaseline = 'top';
  ctx.fillText(name, pad * dpr, pad * dpr);

  const texture = new THREE.CanvasTexture(canvas);
  texture.needsUpdate = true;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.generateMipmaps = false;
  if (THREE.SRGBColorSpace) texture.colorSpace = THREE.SRGBColorSpace;

  const material = new THREE.SpriteMaterial({ map: texture, transparent: true, depthTest: false });
  const sprite = new THREE.Sprite(material);
  sprite.renderOrder = 999;

  // anchor just above the mesh
  const radius = (mesh.geometry?.parameters?.radius || 1) * mesh.scale.x;
  sprite.position.copy(mesh.position).add(new THREE.Vector3(0, radius * 1.5, 0));

  // 3) pixel-perfect world size from camera FOV
  const dist = camera.position.distanceTo(sprite.position);
  const viewportH = (renderer?.domElement?.clientHeight || window.innerHeight || 800);
  const vFOV = THREE.MathUtils.degToRad(camera.fov);
  const worldPerPixel = 2 * Math.tan(vFOV / 2) * dist / viewportH;

  let worldW = (canvas.width  / dpr) * worldPerPixel;
  let worldH = (canvas.height / dpr) * worldPerPixel;

  // 4) never let it be tiny
  const minWorldH = 1.2; // ≈ readable minimum; tweak if you want larger
  if (worldH < minWorldH) {
    const mul = minWorldH / worldH;
    worldH *= mul;
    worldW *= mul;
  }

  sprite.scale.set(worldW, worldH, 1);

  this.scene.add(sprite);
  sprite.lookAt(camera.position);

  this.labels.push(sprite);
  return sprite;
}

  clearCelestialBodies() {
    this.bodies.forEach(body => {
      this.scene.remove(body);
      body.geometry.dispose();
      body.material.dispose();
    });
    this.bodies = [];

    this.labels.forEach(label => {
      this.scene.remove(label);
      label.material.dispose();
      label.texture?.dispose();
    });
    this.labels = [];

    this.animationController.clearPlanets();
  }
}
