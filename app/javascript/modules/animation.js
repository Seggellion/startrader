// animation_controller.js
import * as THREE from 'three';

export class AnimationController {
    constructor(renderer, scene, camera) {
        this.renderer = renderer;
        this.scene = scene;
        this.camera = camera;
        this.planets = [];
        this.animate = this.animate.bind(this);
        this.G = 6.67430e-20; // Adjust as needed for your units

    }

    calculateDistances() {
        let distances = [];
      
        for (let i = 0; i < this.planets.length; i++) {
            for (let j = i + 1; j < this.planets.length; j++) {
                const distance = Math.sqrt(
                    Math.pow(this.planets[i].mesh.position.x - this.planets[j].mesh.position.x, 2) +
                    Math.pow(this.planets[i].mesh.position.y - this.planets[j].mesh.position.y, 2) +
                    Math.pow(this.planets[i].mesh.position.z - this.planets[j].mesh.position.z, 2)
                );
                distances.push({
                    pair: `${this.planets[i].name} to ${this.planets[j].name}`,
                    distance: distance.toFixed(2) // Keeping two decimal points for clarity
                });
            }
        }
        return distances;
    }

    
    updateHtmlWithDistances(distances) {
   
        const distancesElement = document.getElementById('distances'); // Ensure this element exists in your HTML
        distancesElement.innerHTML = ''; // Clear previous frame's distances
        distances.forEach(dist => {
            distancesElement.innerHTML += `<p>${dist.pair}: ${dist.distance} Mkm</p>`; // Update with new distances
        });
    }

    addPlanet(planet) {
        this.planets.push(planet);
    }

    animate() {
      //  requestAnimationFrame(() => this.animate());
        requestAnimationFrame(this.animate);

        const speedFactor = 0.1; // Reduce this value to slow down the animation
        const time = Date.now() * 0.00005 * speedFactor;
      
        this.planets.forEach(planet => {

            // Assuming these values are defined somewhere in your application
            let currentTime = Date.now(); // Current time in milliseconds since the Unix Epoch
            let timeAtPerihelion = new Date('2024-01-03').getTime(); // Example: Perihelion for Earth on January 3, 2024
           // let orbitalPeriodYears = 1; // Earth's orbital period, in years
            let massCentralBody = planet.starMass;
            // Convert `currentTime` and `timeAtPerihelion` to seconds since epoch
            currentTime /= 1000;
            timeAtPerihelion /= 1000;

            const angle = time * planet.orbitalSpeed;
            const r = planet.semfiMajorAxis * (1 - planet.eccentricity ** 2) / (1 + planet.eccentricity * Math.cos(angle));
            const position = this.calculateOrbitalPosition(planet.semiMajorAxis, planet.eccentricity, currentTime, timeAtPerihelion, massCentralBody);

            planet.mesh.position.set(position.x, position.y, position.z); // Assuming a simple 2D orbit for illustration
 
            // Added February 24
          //  planet.label = this.addLabel(planet.name, planet.mesh.position, planet.size, this.camera);

        if (planet.mesh && planet.label) {
            // Your existing logic to update planet.mesh.position
            planet.mesh.position.set(position.x, position.y, position.z);
    
            // Also update the label's position to follow the planet
            planet.label.position.copy(planet.mesh.position).add(new THREE.Vector3(0, planet.size * 1.2, 0));
            planet.label.lookAt(this.camera.position);
        } else {
            console.warn("Planet or label is undefined, skipping position update for this planet.");
        }


        //    planet.mesh.position.x = r * Math.cos(angle);
        //    planet.mesh.position.z = r * Math.sin(angle);
        });

        const distances = this.calculateDistances();
        this.updateHtmlWithDistances(distances); 

        this.renderer.render(this.scene, this.camera);
    }

    calculateOrbitalPeriod(semiMajorAxis, massCentralBody) {
        // const G = 6.67430e-20; // Adjusted gravitational constant in MKm^3/kg/s^2
        const G = 6.67430e-10;
        // Ensure semiMajorAxis is in MKm and massCentralBody in kg
        const orbitalPeriodSeconds = 2 * Math.PI * Math.sqrt(Math.pow(semiMajorAxis, 3) / (G * massCentralBody));      
        const orbitalPeriodSecondsRounded = parseFloat(orbitalPeriodSeconds.toFixed(10)); // Round to 10 decimal places

        return orbitalPeriodSecondsRounded; // Returns the orbital period in seconds
    }
    
    calculateTrueAnomaly(eccentricAnomaly, eccentricity) {
        const trueAnomaly = 2 * Math.atan2(
            Math.sqrt(1 + eccentricity) * Math.sin(eccentricAnomaly / 2),
            Math.sqrt(1 - eccentricity) * Math.cos(eccentricAnomaly / 2)
        );
        return trueAnomaly;
    }

    calculateMeanAnomaly(currentTime, timeAtPerihelion, orbitalPeriodYears) {
        const orbitalPeriodSeconds = orbitalPeriodYears;
        const meanMotion = 2 * Math.PI / orbitalPeriodSeconds; // radians per second
        const elapsedTime = currentTime - timeAtPerihelion; // Assuming both times are in seconds
        const meanAnomaly = meanMotion * elapsedTime; // radians

        return meanAnomaly;
    }
    

    solveKeplersEquation(eccentricity, meanAnomaly) {
        let e = meanAnomaly;
        let delta = 1;
        while (delta > 1e-6) {
            let eNew = e + (meanAnomaly - e + eccentricity * Math.sin(e)) / (1 - eccentricity * Math.cos(e));
            delta = Math.abs(eNew - e);
            e = eNew;
        }
        return e;
    }
    
    
    calculateOrbitalPosition(semiMajorAxis, eccentricity, currentTime, timeAtPerihelion, massCentralBody) {
        // First, calculate the mean anomaly

        const orbitalPeriod = this.calculateOrbitalPeriod(semiMajorAxis, massCentralBody);



        const meanAnomaly = this.calculateMeanAnomaly(currentTime, timeAtPerihelion, orbitalPeriod);

        const eccentricAnomaly = this.solveKeplersEquation(eccentricity, meanAnomaly);
        const trueAnomaly = this.calculateTrueAnomaly(eccentricAnomaly, eccentricity);
        const distance = semiMajorAxis * (1 - eccentricity ** 2) / (1 + eccentricity * Math.cos(trueAnomaly));

        // Assuming 2D position for simplicity
        const x = distance * Math.cos(trueAnomaly);
        const y = distance * Math.sin(trueAnomaly);

        return { x, y };
    }
    

    clearPlanets() {
        this.planets = []; // Simply reset the planets array
    }

    startAnimation() {

        this.animate(); // Kick off the animation loop
    }
}
