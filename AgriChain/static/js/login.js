/* =====================================================================
   AgriChain Login Interactions
   - Animated Eye Closing & Opening for Password Visibility Toggle
   - Farmer Password vs Biometric Thumbprint Sign-In Switcher
   - Interactive Demo Quick-Fill Helpers
   ===================================================================== */
document.addEventListener("DOMContentLoaded", () => {
  // 1. Animated Eye Opening / Closing on all password fields
  document.querySelectorAll("[data-eye-toggle]").forEach((btn) => {
    const targetId = btn.getAttribute("data-eye-toggle");
    const input = document.getElementById(targetId);
    if (!input) return;

    btn.setAttribute("data-state", "closed");

    btn.addEventListener("click", () => {
      const currentlyClosed = btn.getAttribute("data-state") === "closed";
      btn.classList.remove("is-animating");
      void btn.offsetWidth;
      btn.classList.add("is-animating");

      if (currentlyClosed) {
        input.type = "text";
        btn.setAttribute("data-state", "open");
        btn.setAttribute("aria-label", "Hide password");
      } else {
        input.type = "password";
        btn.setAttribute("data-state", "closed");
        btn.setAttribute("aria-label", "Show password");
      }
      input.focus();
    });

    setInterval(() => {
      if (btn.getAttribute("data-state") === "open") {
        btn.classList.add("is-animating");
        setTimeout(() => btn.classList.remove("is-animating"), 340);
      }
    }, 5200);
  });

  // 2. Farmer Login: Switch between Password and Biometric Authentication
  const modeButtons = document.querySelectorAll("[data-auth-mode]");
  if (modeButtons.length) {
    const pwdSection = document.getElementById("farmer-password-section");
    const bioSection = document.getElementById("farmer-biometric-section");
    const modeInput = document.getElementById("farmer-auth-mode");
    const pwdInput = document.getElementById("farmer_password");
    const bioInput = document.getElementById("farmer_aadhaar_last4");

    modeButtons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const mode = btn.getAttribute("data-auth-mode");
        modeButtons.forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        if (modeInput) modeInput.value = mode;

        if (mode === "biometric") {
          pwdSection?.classList.add("hidden");
          bioSection?.classList.remove("hidden");
          if (pwdInput) pwdInput.required = false;
          if (bioInput) bioInput.required = true;
        } else {
          bioSection?.classList.add("hidden");
          pwdSection?.classList.remove("hidden");
          if (pwdInput) pwdInput.required = true;
          if (bioInput) bioInput.required = false;
        }
      });
    });
  }

  // Biometric scanner pad click / keyboard simulation with live scan sequence
  const bioPad = document.getElementById("farmer-bio-pad");
  if (bioPad) {
    const triggerScan = () => {
      const statusText = document.getElementById("farmer-bio-status");
      bioPad.classList.remove("scanned");
      bioPad.classList.add("is-scanning");
      if (statusText) statusText.textContent = "Capturing thumbprint template at kiosk...";
      setTimeout(() => {
        bioPad.classList.remove("is-scanning");
        bioPad.classList.add("scanned");
        if (statusText) {
          statusText.textContent = "Thumbprint template captured — verify Aadhaar last 4 digits and Sign In";
        }
        document.getElementById("farmer_aadhaar_last4")?.focus();
      }, 420);
    };
    bioPad.addEventListener("click", triggerScan);
    bioPad.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        triggerScan();
      }
    });
  }

  // 3. Buyer Login: Toggle Sign-In vs Organization Onboarding Registration
  const buyerModeBtns = document.querySelectorAll("[data-buyer-mode]");
  if (buyerModeBtns.length) {
    const loginPanel = document.getElementById("buyer-login-panel");
    const regPanel = document.getElementById("buyer-register-panel");
    buyerModeBtns.forEach((btn) => {
      btn.addEventListener("click", () => {
        const mode = btn.getAttribute("data-buyer-mode");
        buyerModeBtns.forEach((b) => b.classList.remove("active"));
        btn.classList.add("active");
        if (mode === "register") {
          loginPanel?.classList.add("hidden");
          regPanel?.classList.remove("hidden");
        } else {
          regPanel?.classList.add("hidden");
          loginPanel?.classList.remove("hidden");
        }
      });
    });
  }

  // 4. Demo credential chips with active selection state
  const allChips = document.querySelectorAll("[data-fill-target]");
  allChips.forEach((chip) => {
    chip.addEventListener("click", () => {
      allChips.forEach((c) => c.classList.remove("is-selected"));
      chip.classList.add("is-selected");
      const pairs = chip.getAttribute("data-fill-target").split("|");
      pairs.forEach((p) => {
        const [fieldId, val] = p.split("=");
        const el = document.getElementById(fieldId);
        if (el) {
          el.value = val;
          el.dispatchEvent(new Event("input", { bubbles: true }));
        }
      });
    });
  });
});