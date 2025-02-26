import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "primaryImage",
    "thumbnailContainer",
    "modal",
    "modalImage",
    "modalTitle",
  ];
  static values = {
    staffScreenshots: Array,
  };

  connect() {
    console.log("screenshot controller loaded");

    // Load staff screenshots from data attribute
    this.staffScreenshots = JSON.parse(this.element.dataset.staffScreenshots || "[]");
  }

  updateStaffScreenshot(event) {
    const screenshotId = event.target.value; // Get selected screenshot ID
    if (screenshotId) {
      const screenshot = this.element.querySelector(
        `option[value="${screenshotId}"]`
      );

      if (screenshot) {
        const imageUrl = screenshot.dataset.imageUrl;
        const metaDescription =
          screenshot.dataset.metaDescription || "Untitled";
        const metaKeywords =
          screenshot.dataset.metaKeywords || "No description available.";

        // Update the primary image
        this.updatePrimaryImage({ imageUrl, metaDescription, metaKeywords });

        // Update thumbnails to display all staff screenshots
        const thumbnails = this.thumbnailContainerTarget;
        thumbnails.innerHTML = ""; // Clear existing thumbnails

        this.staffScreenshots.forEach((screenshot) => {
          const thumbnail = document.createElement("img");
          thumbnail.src = screenshot.image_url;
          thumbnail.alt = screenshot.meta_description || "Screenshot";
          thumbnail.className =
            "cursor-pointer rounded-lg shadow w-full h-24 object-cover";

          // On click, update the primary image
          thumbnail.addEventListener("click", () =>
            this.updatePrimaryImage({
              imageUrl: screenshot.image_url,
              metaDescription: screenshot.meta_description,
              metaKeywords: screenshot.meta_keywords,
            })
          );

          const thumbnailWrapper = document.createElement("div");
          thumbnailWrapper.appendChild(thumbnail);
          thumbnails.appendChild(thumbnailWrapper);
        });
      }
    }
  }

   // Select screenshot for the main image
   selectScreenshot(event) {
    // The clicked element is the target
    const thumbnail = event.target;
   
    // Extract data attributes from the clicked thumbnail
    const imageUrl = thumbnail.dataset.imageUrl || thumbnail.src; // Use src as fallback
    
    
    const metaDescription = thumbnail.alt || "Untitled";
  
    const metaKeywords = thumbnail.dataset.metaKeywords || "No description available.";
    
    // Update the primary image using extracted data
    this.updatePrimaryImage({ imageUrl, metaDescription, metaKeywords });
  }
  

  updateUserScreenshots(event) {
    const username = event.target.value;
  
    if (username) {
      fetch(`/community/user_screenshots?username=${username}`)
        .then((response) => {
          if (!response.ok) {
            throw new Error("User not found or no screenshots available.");
          }
          return response.json();
        })
        .then((data) => {
          if (data.primary_image) {
            this.updatePrimaryImage({
              imageUrl: data.primary_image,
              metaDescription: data.meta_description,
              metaKeywords: data.meta_keywords,
            });
          }

          // Update thumbnails to display user screenshots
          const thumbnails = this.thumbnailContainerTarget;
          thumbnails.innerHTML = ""; // Clear existing thumbnails
  
          data.thumbnails.forEach((screenshot) => {
            const thumbnail = document.createElement("img");
            thumbnail.src = screenshot.url;
            thumbnail.alt = screenshot.meta_description || "Screenshot";
            thumbnail.className =
              "cursor-pointer rounded-lg shadow w-full h-24 object-cover";
  
            // Add data attributes and Stimulus action
            thumbnail.dataset.action = "click->screenshot#selectScreenshot";
            thumbnail.dataset.imageUrl = screenshot.url;
            thumbnail.dataset.metaDescription =
              screenshot.meta_description || "Untitled";
            thumbnail.dataset.metaKeywords =
              screenshot.meta_keywords || "No description available.";
  
            const thumbnailWrapper = document.createElement("div");
            thumbnailWrapper.appendChild(thumbnail);
            thumbnails.appendChild(thumbnailWrapper);
          });
        })
        .catch((error) => {
          console.error("Error fetching user screenshots:", error);
          alert("Failed to load screenshots for the selected user.");
        });
       
    } else {      
      // Clear thumbnails and reset the primary image if no user is selected
      this.thumbnailContainerTarget.innerHTML = "";
      this.resetPrimaryImage();
    }    
  }

  resetPrimaryImage() {
    const img = this.primaryImageTarget.querySelector("img");
    const caption = this.primaryImageTarget.querySelector("h3");
    const description = this.primaryImageTarget.querySelector("p");
  
    if (img && caption && description) {
      img.src = ""; // Reset image source
      img.alt = "Default";
      caption.textContent = "Default Image";
      description.textContent = "No description available.";
    }
  }
  
  

  updatePrimaryImage({ imageUrl, metaDescription, metaKeywords }) {
    const img = this.primaryImageTarget.querySelector("img");
    const caption = this.primaryImageTarget.querySelector("h3");
    const description = this.primaryImageTarget.querySelector("p");
  
    // Ensure the primary image elements exist
    if (img && caption && description) {
      img.src = imageUrl;
      img.alt = metaDescription || "Untitled";
      caption.textContent = metaDescription || "Untitled";
      description.textContent = metaKeywords || "No description available.";
    } else {
      console.error("Primary image elements are missing!");
    }
    
  }
  

  openModal() {
    const img = this.primaryImageTarget.querySelector("img");
    const title = this.primaryImageTarget.querySelector("h3");
    const shard = this.primaryImageTarget.querySelector("p");

    this.modalImageTarget.src = img.src;
    this.modalImageTarget.alt = img.alt;

    const fullTitle = `${title.textContent} - ${shard.textContent} Shard`;


    this.modalTitleTarget.textContent = fullTitle;

    this.modalTarget.classList.remove("hidden");
    document.addEventListener("keydown", this.handleKeydown.bind(this));
  }

  closeModal() {
    this.modalTarget.classList.add("hidden");
    this.modalImageTarget.src = "";
    this.modalTitleTarget.textContent = "";
    document.removeEventListener("keydown", this.handleKeydown.bind(this));
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.closeModal();
    }
  }
}
