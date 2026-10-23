import * as THREE from 'three';

export class CelestialBody {
  constructor(scene, animationController, camera) {
    this.scene = scene; this.animationController = animationController; this.camera = camera;
    this.objects = []; this.displayScale = 1; // scene units per physical Gm
  }
  addCelestialBody(data) {
    if (!data.available || !data.position_gm) return;
    const p = data.position_gm;
    if (![p.x,p.y,p.z].every(Number.isFinite)) return;
    const star = ['star','star_system'].includes(data.classification);
    const city = ['city','outpost'].includes(data.classification);
    const radius = star ? 2 : city ? 0.45 : 1;
    const mesh = new THREE.Mesh(new THREE.SphereGeometry(radius, 20, 16),
      new THREE.MeshBasicMaterial({color: star ? 0xfbbf24 : city ? 0x38bdf8 : 0x86efac}));
    mesh.position.set(p.x*this.displayScale,p.y*this.displayScale,p.z*this.displayScale);
    mesh.userData = {locationId: data.location_id, physicalPositionGm: {...p}};
    this.scene.add(mesh); this.objects.push(mesh);
    if (data.classification === 'planet' && data.periapsis === data.apoapsis) {
      const r = data.periapsis*this.displayScale;
      const points = new THREE.EllipseCurve(0,0,r,r,0,2*Math.PI,false,0).getPoints(160);
      const ring = new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(points),
        new THREE.LineBasicMaterial({color: 0x234150, transparent: true, opacity: 0.55}));
      ring.position.z=-0.1; this.scene.add(ring); this.objects.push(ring);
    }
    const canvas = document.createElement('canvas');
    const ctx=canvas.getContext('2d');
    const label=star ? data.name : `${data.name} · ${Math.hypot(p.x,p.y,p.z).toFixed(1)} Gm`;
    ctx.font='24px Arial'; canvas.width=Math.ceil(ctx.measureText(label).width)+20; canvas.height=40;
    ctx.font='24px Arial'; ctx.fillStyle='#e4e4e7'; ctx.fillText(label,10,28);
    const texture=new THREE.CanvasTexture(canvas);
    const sprite=new THREE.Sprite(new THREE.SpriteMaterial({map:texture,depthTest:false}));
    sprite.userData.label={anchor:mesh.position.clone(),width:canvas.width,height:canvas.height,below:city || star};
    this.scene.add(sprite); this.objects.push(sprite);
  }
  updateLabels() {
    const height=this.animationController.renderer.domElement.clientHeight || 520;
    for (const object of this.objects) {
      const label=object.userData.label;
      if (!label) continue;
      const worldPerPixel=2*Math.tan(this.camera.fov*Math.PI/360)*this.camera.position.distanceTo(label.anchor)/height;
      object.position.copy(label.anchor).add(new THREE.Vector3(0,(label.below ? -15 : 15)*worldPerPixel,0));
      object.scale.set(label.width*0.5*worldPerPixel,label.height*0.5*worldPerPixel,1);
    }
  }
  clearCelestialBodies() {
    for (const object of this.objects) {
      this.scene.remove(object); object.geometry?.dispose();
      object.material?.map?.dispose(); object.material?.dispose();
    }
    this.objects=[];
  }
}
