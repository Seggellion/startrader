import { Controller } from '@hotwired/stimulus';
import { ThreeJSInitializer } from 'ThreeJSInitializer';
import { CelestialBody } from 'CelestialBody';
import { AnimationController } from 'AnimationController';
import { OrbitControls } from 'OrbitControls';
import consumer from 'channels/consumer';

export default class extends Controller {
  connect() {
    this.connected=true; this.system='Stanton'; this.sequence=0; this.desiredTick=null;
    this.threeJS=new ThreeJSInitializer(this.element);
    this.animation=new AnimationController(this.threeJS.renderer,this.threeJS.scene,this.threeJS.camera);
    this.controls=new OrbitControls(this.threeJS.camera,this.threeJS.renderer.domElement);
    this.controls.minDistance=4; this.controls.maxDistance=600;
    this.animation.setControls(this.controls);
    this.bodies=new CelestialBody(this.threeJS.scene,this.animation,this.threeJS.camera);
    this.animation.beforeRender=()=>this.bodies.updateLabels();
    this.status=document.createElement('p');
    this.status.className='absolute bottom-2 left-2 right-2 text-xs text-zinc-300';
    this.status.setAttribute('aria-live','polite'); this.element.appendChild(this.status);
    this.status.textContent='Loading orbital simulation…';
    this.tickSub=consumer.subscriptions.create({channel:'TickChannel'},{received:data=>{
      if (!this.connected || !['tick','status','tick_stopped','tick_started'].includes(data.type)) return;
      const versionChanged=Boolean(data.catalog_version && this.version && data.catalog_version!==this.version);
      const tick=Number(data.tick);
      if (!versionChanged && Number.isFinite(tick) && this.desiredTick!==null && tick<this.desiredTick) return;
      if (Number.isFinite(tick)) this.desiredTick=tick;
      if (versionChanged) {
        this.version=null; this.bodies.clearCelestialBodies();
      }
      this.fetchAndDisplayCelestialBodies();
    }});
    this.fetchAndDisplayCelestialBodies();
  }
  disconnect() {
    this.connected=false; this.sequence++; this.request?.abort(); this.tickSub?.unsubscribe();
    this.animation?.dispose(); this.controls?.dispose(); this.bodies?.clearCelestialBodies();
    this.threeJS?.dispose(); this.threeJS?.renderer.domElement.remove(); this.status?.remove();
  }
  selectStarSystem(event) {
    this.system=event.currentTarget.dataset.starSystemName; this.fittedSystem=null;
    this.fetchAndDisplayCelestialBodies();
  }
  focusLocation(event) {
    if (event.detail?.systemName) {this.system=event.detail.systemName;this.fittedSystem=null;this.fetchAndDisplayCelestialBodies();}
    this.element.dataset.focusedLocation=event.detail?.locationName || '';
  }
  async fetchAndDisplayCelestialBodies() {
    const seq=++this.sequence; this.request?.abort(); this.request=new AbortController();
    const query=new URLSearchParams({star:this.system});
    if (this.desiredTick!==null) query.set('tick',String(this.desiredTick));
    if (this.version) query.set('version',this.version);
    try {
      const response=await fetch(`/locations?${query}`,{signal:this.request.signal,cache:'no-store'});
      if (!this.connected || seq!==this.sequence) return;
      if (response.status===409) {this.version=null;return this.fetchAndDisplayCelestialBodies();}
      const data=await response.json();
      if (!response.ok || !Array.isArray(data)) throw new Error(data.error || 'Positions unavailable');
      if (!this.connected || seq!==this.sequence) return;
      this.version=response.headers.get('X-Orbital-Catalog-Version');
      const rows=data.map(item=>({...item.attributes,location_id:item.id}));
      if (rows.some(r=>r.catalog_version!==this.version)) throw new Error('Inconsistent orbital snapshot');
      this.bodies.clearCelestialBodies();
      // Surface sites share their host center. Show a selected site (and
      // Levski's explicit host relationship) without stacking dozens of labels.
      const displayed=rows.filter(row=>!['city','outpost'].includes(row.classification) ||
        row.name==='Levski' || row.name===this.element.dataset.focusedLocation);
      displayed.forEach(row=>this.bodies.addCelestialBody(row));
      this.threeJS.renderer.domElement.setAttribute('role','img');
      this.threeJS.renderer.domElement.setAttribute('aria-label',`${this.system} orbital simulation. `+
        displayed.filter(row=>row.available).map(row=>`${row.name}: ${Math.hypot(row.position_gm.x,row.position_gm.y,row.position_gm.z).toFixed(1)} Gm`).join('; '));
      const unavailable=rows.filter(r=>!r.available);
      const tick=rows[0]?.current_tick ?? this.desiredTick;
      this.element.dataset.catalogVersion=this.version; this.element.dataset.orbitalTick=String(tick);
      this.status.textContent=`Orbital simulation · tick ${tick} · Gm${unavailable.length ? ` · ${unavailable.length} positions unavailable` : ''}`;
      this.status.title=unavailable.map(r=>`${r.name}: ${r.unavailable_reason}`).join('; ');
      if (this.fittedSystem!==this.system) {
        const extent=Math.max(15,...rows.filter(r=>r.available).map(r=>Math.hypot(r.position_gm.x,r.position_gm.y)));
        const camera=this.threeJS.camera;
        camera.position.set(0,0,extent*1.3/(Math.tan(camera.fov*Math.PI/360)*Math.min(1,camera.aspect)));
        this.controls.target.set(0,0,0); this.controls.update(); this.fittedSystem=this.system;
      }
      this.animation.renderOnce();
      this.element.dispatchEvent(new CustomEvent('orbital:snapshot',{detail:{rows,version:this.version,tick}}));
    } catch(error) {
      if (error.name!=='AbortError' && this.connected && seq===this.sequence) this.status.textContent=`Orbital positions unavailable: ${error.message}`;
    }
  }
}
