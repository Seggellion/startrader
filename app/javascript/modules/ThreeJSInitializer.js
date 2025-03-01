import * as THREE from "three";

export class ThreeJSInitializer {
    constructor(element) {
        // Initialize scene, camera, renderer
        this.scene = new THREE.Scene();
         this.camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
      //  this.camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 100);
        // this.camera.position.z = 50;
        this.camera.position.z = 100;
        this.renderer = new THREE.WebGLRenderer();
        this.renderer.setSize(window.innerWidth, window.innerHeight);
        
        element.appendChild(this.renderer.domElement);
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
