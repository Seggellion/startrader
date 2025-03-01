import { Controller } from "@hotwired/stimulus";
import { ThreeJSInitializer } from "ThreeJSInitializer";
import { CelestialBody } from "CelestialBody";
import { AnimationController } from "AnimationController";
import { OrbitControls } from "OrbitControls";

export default class extends Controller {
    connect() {
        console.log('star_system');
        this.planets = [];
        this.threeJS = new ThreeJSInitializer(this.element);
        this.animationController = new AnimationController(this.threeJS.renderer, this.threeJS.scene, this.threeJS.camera);
        this.celestialBody = new CelestialBody(this.threeJS.scene, this.animationController, this.threeJS.camera); // Pass animationController here
      
        const controls = new OrbitControls(this.threeJS.camera, this.threeJS.renderer.domElement);
        this.fetchAndDisplayCelestialBodies(this.starSystemNameValue);
  
    }

    selectStarSystem(event) {
        const starSystemName = event.currentTarget.dataset.starSystemName;
        this.starSystemNameValue = starSystemName === "All" ? null : starSystemName;
        console.log(`Loading data for star system: ${this.starSystemNameValue || "All Systems"}`);
        
        // Clear the ThreeJS scene or reset necessary elements
        this.celestialBody.clearCelestialBodies(); 
        
        // Fetch and display the updated celestial bodies
        this.fetchAndDisplayCelestialBodies(this.starSystemNameValue);
    }

    fetchAndDisplayCelestialBodies(starSystemName = null) {
        // Construct the URL with an optional 'star' query parameter
        const url = starSystemName ? `/locations?star=${encodeURIComponent(starSystemName)}` : "/locations";
    
        fetch(url)
            .then(response => response.json())
            .then(data => {
                if (Array.isArray(data)) {
                    data.forEach(item => {                 
                        const attributes = item.attributes;
                        if (attributes["classification"] === "planet") {
                            this.celestialBody.addCelestialBody(attributes, 3, 0x00ff00, attributes.name, attributes.starMass);
                        } else if (attributes["classification"] === "star_system") {
                            this.celestialBody.addCelestialBody(attributes, 10, 0xffd700, attributes.name, attributes.starMass);
                        }
                    });
                }
            })
            .then(() => this.animationController.startAnimation());
    }
    
    
}
