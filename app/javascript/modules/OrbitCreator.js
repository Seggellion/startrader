import * as THREE from "three";

export function createOrbit(periapsis, apoapsis, material, scene) {
    const curve = new THREE.EllipseCurve(0, 0, apoapsis, periapsis, 0, 2 * Math.PI, false, 0);
    const points = curve.getPoints(50);
    const geometry = new THREE.BufferGeometry().setFromPoints(points);
    const ellipse = new THREE.Line(geometry, material);

    scene.add(ellipse);
    return ellipse;
}
