import * as THREE from "three";

export class ThreeJSInitializer {
    constructor(element) {
        this.element = element;
        // Initialize scene, camera, renderer
        this.scene = new THREE.Scene();
        const { width, height } = this.dimensions();
         this.camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
      //  this.camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 100);
        // this.camera.position.z = 50;
        this.camera.position.z = 100;
        this.renderer = new THREE.WebGLRenderer({ antialias: true });
        this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
        this.renderer.setSize(width, height);
        
        element.appendChild(this.renderer.domElement);
        this.resizeHandler = () => this.resize();
        window.addEventListener("resize", this.resizeHandler);
    }

    dimensions() {
        const rect = this.element.getBoundingClientRect();
        return {
            width: Math.max(rect.width || window.innerWidth, 320),
            height: Math.max(rect.height || 360, 240)
        };
    }

    resize() {
        const { width, height } = this.dimensions();
        this.camera.aspect = width / height;
        this.camera.updateProjectionMatrix();
        this.renderer.setSize(width, height);
    }

    dispose() {
        window.removeEventListener("resize", this.resizeHandler);
        this.renderer.dispose();
    }
    
/*
    animate(planets) {
        requestAnimationFrame(() => this.animate(planets));
        planets.forEach(planet => {
            // Update planet positions
        });
        this.renderer.render(this.scene, this.camera);
    }
    */
}
