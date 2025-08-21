// animation_controller.js
import * as THREE from 'three';

// Anchor epoch used to align phases with Ruby (seconds since UNIX epoch)
const T_PERI_EPOCH_SEC = Date.parse('2024-01-03T00:00:00Z') / 1000;

export class AnimationController {
    
 constructor(renderer, scene, camera) {
    this.renderer = renderer;
    this.scene = scene;
    this.camera = camera;
    this.planets = [];
    this.star = null;
    this.animate = this.animate.bind(this);

    this.orbitPadding = 1;
    this.G = 6.67430e-38;   // Mkm^3 / kg / s^2

    // 🎛️ how fast sim time runs vs real time
    // e.g. 86400 = 1 sim day per real second; 604800 = 1 week/sec
    this.timeScale = 86400;

    // ⏱️ simulation clock
    this.simTime = 0;                   // seconds since start of sim
    this._lastNow = performance.now() / 1000;
      // Modes: 'idle' | 'raf' | 'tick'
    this.mode = 'idle';
    this._rafId = null;

    // Tick mode fields
    this.secondsPerTick = 0;
    this._tickBase = null;         // server tick from which simTime=0 is measured

    // Optional: OrbitControls reference (for re-render-on-change)
    this.controls = null;
  }

  setStar(star) { this.star = star; }

  setControls(controls) {
    this.controls = controls;
    // Always re-render on camera movement, even when idle/tick-paused
    this.controls.addEventListener('change', () => this.renderOnce());
  }

  addPlanet(planet) {
    // Keep physics in REAL units (Mkm); scale only when rendering
    const aRealMkm = planet.semiMajorAxisReal; // in Mkm, from API
    planet._aRealMkm = aRealMkm;
    const T = this.calculateOrbitalPeriod(aRealMkm, planet.starMass);
    planet._aScene = planet.semiMajorAxis / (this.unitScale || 1); // for drawing

    if (T && Number.isFinite(T) && T > 0) {
      planet._T = T;
      planet._n = 2 * Math.PI / T; // rad/sec (real)

      // Default M0 when simTime starts at 0 (RAF mode or before first tick):
      // M = n * (simTime - T_PERI_EPOCH_SEC)  ⇒  M0 = -n * T_PERI_EPOCH_SEC
      planet._M0 = this._wrap2pi(planet._n * (-T_PERI_EPOCH_SEC));
    } else {
      planet._T = null;
      planet._n = 0;
      planet._M0 = 0;
    }
    this.planets.push(planet);
  }

  _wrap2pi(x){ x %= (2*Math.PI); return x < 0 ? x + 2*Math.PI : x; }

  // ✅ Your original neighbor distances (kept)
  calculateDistances() {
    let distances = [];
    for (let i = 0; i < this.planets.length; i++) {
      for (let j = i + 1; j < this.planets.length; j++) {
        const pi = this.planets[i].mesh.position;
        const pj = this.planets[j].mesh.position;
        const d = Math.hypot(pi.x - pj.x, pi.y - pj.y, pi.z - pj.z);
        distances.push({
          pair: `${this.planets[i].name} ↔ ${this.planets[j].name}`,
          distance: d.toFixed(2)
        });
      }
    }
    return distances;
  }

  // 🆕 Distances from each planet to the star
  calculateStarDistances() {
    if (!this.star || !this.star.mesh) return [];
    const s = this.star.mesh.position;
    return this.planets.map(p => {
      const m = p.mesh.position;
      const d = Math.hypot(m.x - s.x, m.y - s.y, m.z - s.z);
      return { pair: `${p.name} → ${this.star.name}`, distance: d.toFixed(2) };
    });
  }

  // 🆕 render both lists
  updateHtmlWithDistances(starDistances, neighborDistances) {
    const el = document.getElementById('distances');
    if (!el) return;

    let html = '';
    if (this.star && starDistances.length) {
      html += `<h4>Distance to ${this.star.name}</h4>`;
      starDistances.forEach(d => (html += `<p>${d.pair}: ${d.distance} GM</p>`));
    }
    if (neighborDistances.length) {
      html += `<h4>Neighbor distances</h4>`;
      neighborDistances.forEach(d => (html += `<p>${d.pair}: ${d.distance} GM</p>`));
    }
    el.innerHTML = html;
  }

  // --------------------
  // RENDERING MODES
  // --------------------
  useRAF() {
    if (this.mode === 'raf') return;
    this.stopRAF(); // clear any stray loop then restart clean
    this.mode = 'raf';
    this._lastNow = performance.now() / 1000;
    this._rafId = requestAnimationFrame(this.animate);
  }

  stopRAF() {
    if (this._rafId) {
      cancelAnimationFrame(this._rafId);
      this._rafId = null;
    }
    if (this.mode === 'raf') this.mode = 'idle';
  }

  useTickClock(secondsPerTick) {
    this.stopRAF();
    this.mode = 'tick';
    this.secondsPerTick = secondsPerTick;
    console.log('tick Click Started: ', secondsPerTick);
    this._tickBase = null; // set on first tick we receive
  }

  stopTickClock() {
    this.mode = 'idle';
    this.secondsPerTick = 0;
    this._tickBase = null;
  }

  // Rails will call this on every tick broadcast
  onTick(serverTickNumber) {
    if (this.mode !== 'tick') return;

    // On the very first tick, rebase M0 so that:
    //   M = n * (tick * secondsPerTick - T_PERI_EPOCH_SEC)
    if (this._tickBase == null) {
      this._tickBase = serverTickNumber;
      const baseOffsetSec = this._tickBase * this.secondsPerTick;

      for (const p of this.planets) {
        if (p._T && p._n) {
          p._M0 = this._wrap2pi(p._n * (-T_PERI_EPOCH_SEC + baseOffsetSec));
        }
      }
    }

    const ticksSinceBase = serverTickNumber - this._tickBase;
    this.simTime = ticksSinceBase * this.secondsPerTick;

    // console.log("[onTick]", { serverTickNumber, simTime: this.simTime.toFixed(2) });
    this.renderOnce();
  }

  // --------------------
  // MAIN LOOPS
  // --------------------
  animate() {
    // RAF mode only
    // console.log('animation has begun');
    if (this.mode !== 'raf') return;

    this._rafId = requestAnimationFrame(this.animate);

    const now = performance.now() / 1000;
    const dt = Math.max(0, Math.min(0.25, now - this._lastNow)); // clamp long pauses
    this._lastNow = now;

    this.simTime += dt * this.timeScale;
    this._renderAtSimTime(this.simTime);
  }

  renderOnce() {
    this._renderAtSimTime(this.simTime);
  }

  _renderAtSimTime(simTime) {
    for (const p of this.planets) {
      const e  = p.eccentricity || 0;
      const n  = p._n || 0;
      const M0 = p._M0 || 0;

      const M  = this._wrap2pi(M0 + n * simTime);
      const E  = this.solveKeplersEquation(e, M);
      const nu = this.calculateTrueAnomaly(E, e);

      // Physics radius in REAL units, then scale for scene
      const rReal  = p._aRealMkm * (1 - e * e) / (1 + e * Math.cos(nu));
      const rScene = (rReal / (this.unitScale || 1)) * this.orbitPadding;

      p.mesh.position.set(rScene * Math.cos(nu), rScene * Math.sin(nu), 0);

      if (p.label) {
        const rr = (p.mesh.geometry?.parameters?.radius || 1) * p.mesh.scale.x;
        p.label.position.copy(p.mesh.position).add(new THREE.Vector3(0, rr * 1.5, 0));
        p.label.lookAt(this.camera.position);
      }
    }

    if (this.star && this.star.mesh && this.starLabel) {
      const rStar = (this.star.mesh.geometry.parameters.radius || 1) * this.star.mesh.scale.x;
      this.starLabel.position.copy(this.star.mesh.position).add(new THREE.Vector3(0, rStar * 1.5, 0));
      this.starLabel.lookAt(this.camera.position);
    }

    const starDistances = this.calculateStarDistances();
    const neighborDistances = this.calculateDistances();
    this.updateHtmlWithDistances(starDistances, neighborDistances);

    this.renderer.render(this.scene, this.camera);
  }

  calculateOrbitalPeriod(a_Mkm, massCentralBody_kg) {
    const mu = this.G * massCentralBody_kg;
    if (!(a_Mkm > 0) || !(mu > 0)) return null;
    return 2 * Math.PI * Math.sqrt((a_Mkm ** 3) / mu);
  }

  calculateTrueAnomaly(E, e) {
    return 2 * Math.atan2(Math.sqrt(1 + e) * Math.sin(E / 2), Math.sqrt(1 - e) * Math.cos(E / 2));
  }
  
  calculateMeanAnomaly(currentTime, timeAtPerihelion, orbitalPeriodSeconds) {
    const n = (2 * Math.PI / orbitalPeriodSeconds) * this.timeScale;
    let M = n * (currentTime - timeAtPerihelion);
    M %= (2 * Math.PI);
    if (M < 0) M += 2 * Math.PI;
    return M;
  }

  solveKeplersEquation(e, M) {
    let E = M;
    let delta = 1;
    while (delta > 1e-6) {
      const Enew = E + (M - E + e * Math.sin(E)) / (1 - e * Math.cos(E));
      delta = Math.abs(Enew - E);
      E = Enew;
    }
    return E;
  }

  calculateOrbitalPosition(a, e, currentTime, timeAtPerihelion, muMass) {
    const T = this.calculateOrbitalPeriod(a, muMass);
    const M = this.calculateMeanAnomaly(currentTime, timeAtPerihelion, T);
    const E = this.solveKeplersEquation(e, M);
    const ν = this.calculateTrueAnomaly(E, e);

    const r = a * (1 - e * e) / (1 + e * Math.cos(ν));
    const rp = r * this.orbitPadding; // padded radius for rendering only
    const x = rp * Math.cos(ν);
    const y = rp * Math.sin(ν);
    const z = 0;

    return { x, y, z };
  }

  clearPlanets() {
    this.planets = [];
  }

  startAnimation() {
    this.animate();
  }
}
