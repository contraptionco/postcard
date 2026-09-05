import { Controller } from "@hotwired/stimulus"

// Confirmation modal for account deletion. The submit button stays disabled
// until the typed value matches the account's postcard address.
export default class extends Controller {
  static targets = ["modal", "input", "submit"]
  static values = { expected: String }

  open(e) {
    e.preventDefault()
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.focus()
  }

  close(e) {
    if (e) e.preventDefault()
    this.modalTarget.classList.add("hidden")
    this.inputTarget.value = ""
    this.check()
  }

  closeBackground(e) {
    if (e.target === this.modalTarget) {
      this.close()
    }
  }

  closeWithKeyboard(e) {
    if (e.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      this.close()
    }
  }

  check() {
    const matches = this.inputTarget.value.trim().toLowerCase() === this.expectedValue.toLowerCase()
    this.submitTarget.disabled = !matches
  }
}
