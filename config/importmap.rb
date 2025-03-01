# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/ujs", to: "https://cdn.jsdelivr.net/npm/@rails/ujs@7.1.3-4/app/assets/javascripts/rails-ujs.min.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "actiontext.esm.js"

pin "three", to: "https://cdnjs.cloudflare.com/ajax/libs/three.js/0.161.0/three.module.js"
pin "OrbitControls", to: "https://unpkg.com/three@0.161.0/examples/jsm/controls/OrbitControls.js", preload: true
pin "@rails/actioncable", to: "https://cdn.skypack.dev/@rails/actioncable"

pin "ThreeJSInitializer", to: "modules/ThreeJSInitializer.js"
pin "CelestialBody", to: "modules/CelestialBody.js"
pin "AnimationController", to: "modules/animation.js"
pin "OrbitCreator", to: "modules/OrbitCreator.js"