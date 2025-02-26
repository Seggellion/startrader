StarTrader Admin Interface

Welcome to the StarTrader project! This is a Ruby on Rails application, now known as "RailPress," featuring a WordPress-inspired admin interface for managing content like articles, services, atlas pages, and more. This project is tailored for the immersive world of Britannia.

Table of Contents

Installation

Configuration

Usage

Features

Deployment

Screenshot of the Week

Contributing

License

Installation

Prerequisites

Ensure you have the following installed:

Ruby (version 3.2.0 or newer)

Rails (version 8.0 or newer)

PostgreSQL

Node.js and Yarn

Redis (for ActiveJob)

Google Cloud Storage setup

Setup

Clone the repository:

git clone https://github.com/Seggellion/star_trader.git
cd star_trader

Install dependencies:

bundle install
yarn install

Set up the database:

rails db:create
rails db:migrate

Start the PostgreSQL service if it’s not already running:

service postgresql start

Install Active Storage:

rails active_storage:install
rails db:migrate

Start the server:

rails server

Access the application:

Open your browser and go to http://localhost:3000.

Configuration

Tailwind CSS

Tailwind CSS is used for styling. The configuration is located in tailwind.config.js. To compile Tailwind CSS, run:

npx tailwindcss -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/stylesheets/application.css --watch

Importing Custom Fonts

Add your custom fonts (e.g., Alegreya) to the app/assets/fonts/alegreya directory and configure them in app/assets/stylesheets/fonts.css.

Active Storage

Active Storage is configured to use Google Cloud Storage. Ensure your environment variables include:

GOOGLE_APPLICATION_CREDENTIALS_JSON: Base64-encoded JSON key for Google Cloud.

GOOGLE_APPLICATION_CREDENTIALS: Path to the decoded key file.

Turbo

Turbo is enabled for enhanced user experience. Ensure it is properly set up in app/javascript/packs/application.js.

Usage

Admin Interface

The admin interface allows you to manage various content types:

Articles

Testimonials

Services

Atlas Pages

Screenshots

To access the admin interface, go to /admin.

Managing Atlas Pages

Atlas pages represent unique content for Britannia’s cities.

Use the Playguide Controller for URLs like /playguide/atlas/trinsic.

Pages are listed alphabetically with navigation options.

Screenshot Management

Upload screenshots through /community/screenshots.

Approved screenshots are displayed with filtering options by staff or user.

A "Screenshot of the Week" feature highlights one selected screenshot on the homepage.

Features

Custom Admin Interface: WordPress-inspired design with Tailwind CSS styling.

Rich Text Editing: Manage content with Action Text (Trix).

File Uploads: Google Cloud Storage for Active Storage.

Atlas Navigation: Dedicated content for Britannia’s cities.

Screenshot Management: User and staff uploads, filtering, and featured screenshots.

Turbo Integration: Enhanced navigation and performance.

Deployment

Deploying to Heroku

Create a Heroku application:

heroku create

Set up the Heroku environment variables:

heroku config:set RAILS_ENV=production
heroku config:set GOOGLE_APPLICATION_CREDENTIALS_JSON=<base64-encoded-json>

Deploy the application:

git push heroku main

Run database migrations on Heroku:

heroku run rails db:migrate

Set OAuth Settings:

# Example Settings
<Setting key: "discord_client_id", value: "client_id_value", setting_type: "text">
<Setting key: "discord_client_secret", value: "client_secret_value", setting_type: "text">

Screenshot of the Week

This feature automatically selects an approved screenshot once a week for the homepage. It cycles through the approved screenshots and can be manually overridden if needed.

To implement:

Create a cron job or use the whenever gem to automate weekly selection.

Query approved screenshots and randomly select one for the homepage.

Contributing

We welcome contributions! Please fork the repository, create a new branch, and submit a pull request.

License

This project is licensed under the MIT License. See the LICENSE file for details.

