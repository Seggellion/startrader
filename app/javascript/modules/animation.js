// Physical propagation is server-owned. Camera changes only re-render the
// last immutable physical snapshot; there is no page-load simulation clock.
export class AnimationController {
  constructor(renderer, scene, camera) {
    this.renderer = renderer; this.scene = scene; this.camera = camera;
    this.renderOnce = this.renderOnce.bind(this);
  }
  setControls(controls) { this.controls = controls; controls.addEventListener('change', this.renderOnce); }
  renderOnce() { this.beforeRender?.(); this.renderer.render(this.scene, this.camera); }
  dispose() { this.controls?.removeEventListener('change', this.renderOnce); }
}
