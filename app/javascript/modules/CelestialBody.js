import * as THREE from "three";
import { createOrbit } from "OrbitCreator";

export class CelestialBody {
    constructor(scene, animationController, camera) {
        this.scene = scene;
        this.animationController = animationController;
        this.camera = camera;
        this.bodies = []; // Store references to added bodies
        this.labels = []; // Store references to added labels (sprites)
    }
    
    addCelestialBody(data, size, color, name, starMass) {
        const geometry = new THREE.SphereGeometry(size, 32, 32);
        const material = new THREE.MeshBasicMaterial({ color });
        const body = new THREE.Mesh(geometry, material);

        if (data["classification"] === "planet") {
            const scale = 5;
            const semiMajorAxis = ((data.apoapsis + data.periapsis) / 2) / scale;
            const eccentricity = (data.apoapsis - data.periapsis) / (data.apoapsis + data.periapsis);
            const starMass = data.starmass;
            const orbitalSpeed = this.calculateOrbitalSpeed(semiMajorAxis, starMass);

            const planet = {
                mesh: body,
                semiMajorAxis,
                eccentricity,
                orbitalSpeed,
                name,
                starMass,
                size,
                label: this.addLabel(name, body.position, size, this.camera)
            };
            
            this.animationController.addPlanet(planet);
        }

        this.scene.add(body);
        this.bodies.push(body); // Store reference to the body
    }

    calculateOrbitalSpeed(semiMajorAxis, starMass) {
        const G = 6.67430e-10; // Gravitational constant in MKm^3/kg/s^2
        const orbitalSpeed = Math.sqrt(G * starMass / semiMajorAxis);
        return orbitalSpeed;
    }

    addLabel(name, position, size, camera) {
        const canvas = document.createElement('canvas');
        const context = canvas.getContext('2d');

        const fontSize = Math.ceil(size * 10);
        context.font = `${fontSize}px Arial`;
        context.fillStyle = 'rgba(255, 255, 255, 1.0)';
        context.fillText(name, 0, fontSize);

        const textWidth = context.measureText(name).width;
        canvas.width = textWidth;
        canvas.height = fontSize * 1.5;

        context.clearRect(0, 0, canvas.width, canvas.height);
        context.font = `${fontSize}px Arial`;
        context.fillStyle = 'rgba(255, 255, 255, 1.0)';
        context.fillText(name, 0, fontSize);

        const texture = new THREE.CanvasTexture(canvas);
        const spriteMaterial = new THREE.SpriteMaterial({ map: texture, transparent: true });
        const sprite = new THREE.Sprite(spriteMaterial);

        sprite.position.copy(position).add(new THREE.Vector3(0, size * 1.2, 0));

        const distance = camera.position.distanceTo(sprite.position);
        const scale = distance / 100 * (size * 5);
        sprite.scale.set(scale, scale / 2, 1);

        this.scene.add(sprite);
        sprite.lookAt(camera.position);

        this.labels.push(sprite); // Store reference to the label
        return sprite; 
    }

    // 🆕 New Method to Clear All Bodies and Labels
    clearCelestialBodies() {
        this.bodies.forEach(body => {
            this.scene.remove(body);
            body.geometry.dispose();
            body.material.dispose();
        });
        this.bodies = []; // Reset the array

        this.labels.forEach(label => {
            this.scene.remove(label);
            label.material.dispose();
            label.texture?.dispose(); // Cleanup texture if available
        });
        this.labels = []; // Reset the array

        // Clear animation controller if needed
        this.animationController.clearPlanets(); 
    }
}
