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
    this.viewSelect=document.createElement('select');
    this.viewSelect.setAttribute('aria-label','Orbital view');
    this.viewSelect.className='absolute top-14 left-3 right-3 z-10 text-xs bg-zinc-900 text-zinc-100';
    this.viewSelect.addEventListener('change',()=>{
      this.focusedBody=this.viewSelect.value; this.fittedSystem=null; this.fetchAndDisplayCelestialBodies();
    });
    this.element.appendChild(this.viewSelect);
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
    this.threeJS?.dispose(); this.threeJS?.renderer.domElement.remove(); this.status?.remove(); this.viewSelect?.remove();
  }
  selectStarSystem(event) {
    this.system=event.currentTarget.dataset.starSystemName; this.fittedSystem=null; this.focusedBody='';
    this.fetchAndDisplayCelestialBodies();
  }
  focusLocation(event) {
    this.element.dataset.focusedLocation=event.detail?.locationName || '';
    this.focusedBody=event.detail?.locationName || '';
    if (event.detail?.systemName) {this.system=event.detail.systemName;this.fittedSystem=null;this.fetchAndDisplayCelestialBodies();}
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
      const focus=rows.find(row=>row.name===this.focusedBody && row.available);
      const choices=rows.filter(row=>row.available && ['planet','moon','space_station'].includes(row.classification));
      this.viewSelect.replaceChildren();
      for (const [name,label] of [['','System overview'],...choices.map(row=>[row.name,`${row.name} · ${row.classification.replace('_',' ')}`])]) {
        const option=document.createElement('option'); option.value=name; option.textContent=label;
        this.viewSelect.appendChild(option);
      }
      this.viewSelect.value=choices.some(row=>row.name===focus?.name) ? focus.name : '';
      // Local views retain world coordinates and move only the camera. Omit
      // distant coorbital stations from a planet's close view; select one
      // explicitly or inspect its marker in the system overview.
      const displayed=focus ? rows.filter(row=>row.name===focus.name ||
        (focus.classification==='space_station' && row.name===focus.parent) ||
        (row.parent===focus.name && row.orbital_model!=='coorbital' && !['city','outpost'].includes(row.classification))) :
        rows.filter(row=>['planet','star','star_system'].includes(row.classification) ||
          (row.classification==='space_station' && (row.parent===this.system || row.orbital_model==='coorbital')) || row.name==='Levski');
      const center=(focus?.classification==='space_station' ? focus.parent_position_gm : focus?.position_gm) || {x:0,y:0,z:0};
      const separation=row=>Math.hypot(row.position_gm.x-center.x,row.position_gm.y-center.y,row.position_gm.z-center.z);
      const extent=Math.max(focus ? 0.001 : 15,...displayed.filter(row=>row.available).map(separation));
      displayed.forEach(row=>this.bodies.addCelestialBody({...row,
        visual_radius_gm:extent/50, draw_orbit:displayed.some(parent=>parent.name===row.parent),
        show_label:Boolean(focus) || row.classification!=='space_station'}));
      this.threeJS.renderer.domElement.setAttribute('role','img');
      this.threeJS.renderer.domElement.setAttribute('aria-label',`${this.system} orbital simulation. `+
        displayed.filter(row=>row.available).map(row=>`${row.name}: ${Math.hypot(row.position_gm.x,row.position_gm.y,row.position_gm.z).toFixed(4)} Gm from star`+
          (row.local_distance_gm!==null && row.parent!==this.system ? `; ${row.local_distance_gm.toFixed(4)} Gm from ${row.parent}` : '')).join('; '));
      const unavailable=rows.filter(r=>!r.available);
      const tick=rows[0]?.current_tick ?? this.desiredTick;
      this.element.dataset.catalogVersion=this.version; this.element.dataset.orbitalTick=String(tick);
      this.status.textContent=`${focus ? focus.name+' neighbourhood' : 'Orbital simulation'} · tick ${tick} · Gm${unavailable.length ? ` · ${unavailable.length} positions unavailable` : ''}`;
      this.status.title=unavailable.map(r=>`${r.name}: ${r.unavailable_reason}`).join('; ');
      const viewKey=`${this.system}:${focus?.name || ''}`;
      if (this.fittedSystem!==viewKey) {
        const camera=this.threeJS.camera;
        this.controls.minDistance=extent*0.02;
        this.controls.maxDistance=Math.max(1,extent*50);
        camera.near=Math.max(1e-8,extent*0.0001); camera.far=Math.max(10,extent*100);
        camera.updateProjectionMatrix();
        camera.position.set(center.x,center.y,center.z+extent*1.3/(Math.tan(camera.fov*Math.PI/360)*Math.min(1,camera.aspect)));
        this.controls.target.set(center.x,center.y,center.z); this.controls.update(); this.fittedSystem=viewKey;
      } else if (focus && this.viewCenter) {
        // Follow the same moving host across ticks while preserving user zoom.
        const dx=center.x-this.viewCenter.x,dy=center.y-this.viewCenter.y,dz=center.z-this.viewCenter.z;
        this.threeJS.camera.position.x+=dx; this.threeJS.camera.position.y+=dy; this.threeJS.camera.position.z+=dz;
        this.controls.target.set(center.x,center.y,center.z); this.controls.update();
      }
      this.viewCenter={...center};
      this.animation.renderOnce();
      this.element.dispatchEvent(new CustomEvent('orbital:snapshot',{detail:{rows,version:this.version,tick}}));
    } catch(error) {
      if (error.name!=='AbortError' && this.connected && seq===this.sequence) this.status.textContent=`Orbital positions unavailable: ${error.message}`;
    }
  }
}
