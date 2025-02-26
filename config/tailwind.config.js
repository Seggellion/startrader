const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './app/views/**/*.html.erb',   // Include all ERB templates
    './app/helpers/**/*.rb',       // Include helper files
    './app/assets/javascripts/**/*.js',   // Include JavaScript files
    './app/javascript/**/*.js',    // Include other JavaScript files
    './app/components/**/*.html.erb', // Include any other custom paths
    './app/assets/stylesheets/**/*.css', // Ensure CSS files are included
    './app/assets/stylesheets/**/*.tailwind.css'  // Include Tailwind CSS files
  ],
  theme: {
    extend: {
      fontFamily: {
        alegreya: ['Alegreya', ...defaultTheme.fontFamily.sans]
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/container-queries'),
  ]
}
