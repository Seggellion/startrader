import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    static targets = ["firstName", "lastName", "email", "subject", "body", "submitButton", "form", "thankYouMessage"]

    connect() {
        
      this.submitButtonTarget.disabled = true;
    }
  
    validate() {
      const fields = [this.firstNameTarget, this.lastNameTarget, this.emailTarget, this.subjectTarget, this.bodyTarget];
      const allValid = fields.every(field => field.value.trim() !== "");
  
      this.submitButtonTarget.disabled = !allValid;
  
      fields.forEach(field => {
        if (field.value.trim() === "") {
          field.classList.add("border-red-500");
        } else {
          field.classList.remove("border-red-500");
        }
      });
    }

    submit(event) {
        
        event.preventDefault();
        const url = event.currentTarget.action; // Get the form action URL
        fetch(url, {
          method: "POST",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("[name=csrf-token]").content
          },
          body: JSON.stringify({
            contact_message: {
              first_name: this.firstNameTarget.value,
              last_name: this.lastNameTarget.value,
              email: this.emailTarget.value,
              subject: this.subjectTarget.value,
              body: this.bodyTarget.value
            }
          })
        })
          .then(response => response.json())
          .then(data => {
           
            if (data.success) {
            
              this.formTarget.classList.add("hidden");
              this.thankYouMessageTarget.classList.remove("hidden");
            } else {
              // Handle errors if needed
            }
          })
          .catch(error => console.error("Error:", error));
      }

}
