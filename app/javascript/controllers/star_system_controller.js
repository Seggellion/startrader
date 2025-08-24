import { Controller } from "@hotwired/stimulus";
import { ThreeJSInitializer } from "ThreeJSInitializer";
import { CelestialBody } from "CelestialBody";
import { AnimationController } from "AnimationController";
import { OrbitControls } from "OrbitControls";
import consumer from "channels/consumer"

export default class extends Controller {
    connect() {
        console.log('star_system');
        this.planets = [];
        this.threeJS = new ThreeJSInitializer(this.element);
        this.animationController = new AnimationController(this.threeJS.renderer, this.threeJS.scene, this.threeJS.camera);
        this.celestialBody = new CelestialBody(this.threeJS.scene, this.animationController, this.threeJS.camera); // Pass animationController here
      
        const controls = new OrbitControls(this.threeJS.camera, this.threeJS.renderer.domElement);
            this.animationController.setControls(controls);
   this.subscribeToTicks();
        this.fetchAndDisplayCelestialBodies(this.starSystemNameValue);
       // this.animationController.startAnimation();
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

 subscribeToTicks() {
    this.tickSub = consumer.subscriptions.create(
      { channel: "TickChannel" },
      {
        received: (data) => {
          switch (data.type) {
            case "tick_started":
              // server says: generator is on
                this.animationController.useTickStep(data.seconds_per_tick);
              break;
            case "tick":
              this.animationController.onTick(data.tick);
              break;
            case "tick_stopped":
              this.animationController.stopTickClock();
              break;
            case "status":
              // initial status message after subscribe
              if (data.running) {
                 this.animationController.useTickStep(data.seconds_per_tick);
                this.animationController.onTick(data.tick);
              } else {
                this.animationController.stopTickClock();
                this.animationController.renderOnce(); // draw static scene
              }
              break;
          }
        }
      }
    );
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
                        if (attributes["classification"] === "star_system") {
                                                        this.celestialBody.addCelestialBody(attributes, 10, 0xffd700, attributes.name, attributes.starMass);
                        } else if (attributes["classification"] === "planet") {
                                                        this.celestialBody.addCelestialBody(attributes, 3, 0x00ff00, attributes.name, attributes.starMass);
                        }
                    });
                }
            }).then(() => this.animationController.renderOnce()); 
    }
    
    
}
