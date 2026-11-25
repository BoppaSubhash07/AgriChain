(function () {
  "use strict";

  var filterState = Object.create(null);
  var syncTimer = null;
  var syncInFlight = false;

  function escapeHtml(val) {
    return String(val == null ? "" : val)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function formatINR(num) {
    var n = Number(num) || 0;
    return n.toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  /* ---------- Toast Notifications ---------- */
  function showToast(message, kind) {
    var stack = document.getElementById("portal-toast-stack");
    if (!stack || !message) return;

    var toast = document.createElement("div");
    toast.className = "toast " + (kind === "error" ? "toast-error" : "toast-success");

    var body = document.createElement("div");
    body.textContent = message;

    var closeBtn = document.createElement("button");
    closeBtn.type = "button";
    closeBtn.className = "toast-close";
    closeBtn.setAttribute("aria-label", "Dismiss notification");
    closeBtn.innerHTML = "&times;";
    closeBtn.addEventListener("click", function () {
      toast.remove();
    });

    toast.appendChild(body);
    toast.appendChild(closeBtn);
    stack.appendChild(toast);

    window.setTimeout(function () {
      if (toast.parentNode) toast.remove();
    }, 5500);
  }

  /* ---------- Tabs & History Sync ---------- */
  function activateTab(tabId, skipHistory) {
    if (!tabId) return;
    var btn = document.querySelector('.tab-btn[data-tab-target="' + tabId + '"]');
    var panel = document.getElementById(tabId);
    if (!btn || !panel) return;

    document.querySelectorAll(".tab-btn").forEach(function (b) {
      b.classList.toggle("active", b === btn);
    });
    document.querySelectorAll(".tab-panel").forEach(function (p) {
      p.classList.toggle("active", p === panel);
    });

    if (!skipHistory && window.history && window.history.replaceState) {
      try {
        var url = new URL(window.location.href);
        url.searchParams.set("tab", tabId);
        window.history.replaceState({}, "", url.toString());
      } catch (err) {
        // Ignore history errors in sandboxed iframes
      }
    }
  }

  /* ---------- RBK Sequential Farmer Registration Wizard ---------- */
  function setWizardStep(stepNum) {
    var num = String(stepNum || "1");
    var steps = document.querySelectorAll("[data-wizard-step]");
    var panels = document.querySelectorAll("[data-wizard-panel]");
    if (!steps.length || !panels.length) return;

    steps.forEach(function (el) {
      var s = parseInt(el.dataset.wizardStep || "1", 10);
      var target = parseInt(num, 10);
      el.classList.toggle("active", String(s) === num);
      el.classList.toggle("done", s < target);
    });
    panels.forEach(function (p) {
      p.classList.toggle("hidden", p.dataset.wizardPanel !== num);
    });
  }
  window.setWizardStep = setWizardStep;

  /* ---------- QR Code Initializer ---------- */
  function initAllQRCodes(root) {
    if (typeof window.renderAgriQR !== "function") return;
    var scope = root || document;
    scope.querySelectorAll("[data-qr-code]").forEach(function (box) {
      var code = (box.dataset.qrCode || "").trim();
      if (!code) return;
      if (box.dataset.qrRendered === code && box.querySelector("svg")) return;
      box.innerHTML = "";
      window.renderAgriQR(box, code);
      box.dataset.qrRendered = code;
    });
  }

  /* ---------- Live RBK POS Quota & Subsidy Calculator ---------- */
  function updatePosPreview() {
    var preview = document.getElementById("pos_live_preview");
    var farmerSel = document.getElementById("pos_farmer_id");
    var batchSel = document.getElementById("pos_batch_id");
    var qtyInput = document.getElementById("pos_quantity");
    var aadhaarInput = document.getElementById("pos_aadhaar_last4");
    var payMethodSel = document.getElementById("pos_payment_method");

    if (!preview || !farmerSel || !batchSel) return;

    var fOpt = farmerSel.selectedOptions && farmerSel.selectedOptions[0];
    var bOpt = batchSel.selectedOptions && batchSel.selectedOptions[0];

    if (!fOpt || !fOpt.value || !bOpt || !bOpt.value) {
      preview.innerHTML =
        '<span class="text-muted">Select a registered farmer and RBK inventory batch above to compute live acreage quota, Aadhaar biometric match, and fertilizer subsidy savings.</span>';
      return;
    }

    var acres = parseFloat(fOpt.dataset.acres || "0");
    var bio = fOpt.dataset.bio || "Pending";
    var kccAvail = parseFloat(fOpt.dataset.kcc || "0");
    var storedAadhaar = (fOpt.dataset.aadhaar || "").trim();
    var enteredAadhaar = aadhaarInput ? aadhaarInput.value.trim() : "";

    var rbkPrice = parseFloat(bOpt.dataset.price || "0");
    var retailPrice = parseFloat(bOpt.dataset.retail || "0");
    var perAcre = parseFloat(bOpt.dataset.perAcre || "2");
    var stock = parseFloat(bOpt.dataset.stock || "0");
    var unit = bOpt.dataset.unit || "units";
    var qty = parseInt((qtyInput && qtyInput.value) || "1", 10) || 0;

    var maxAllowed = Math.max(1, Math.ceil(acres * perAcre));
    var total = qty * rbkPrice;
    var retailTotal = qty * retailPrice;
    var savings = Math.max(0, retailTotal - total);
    var quotaPct = Math.min(100, Math.round((qty / maxAllowed) * 100));
    var overQuota = qty > maxAllowed;
    var overStock = qty > stock;
    var payMethod = payMethodSel ? payMethodSel.value : "KCC";

    var bioBadge =
      bio === "Verified"
        ? '<span class="badge badge-green">Bio: Verified</span>'
        : '<span class="badge badge-red">Bio: ' + escapeHtml(bio) + "</span>";

    var aadhaarBadge = "";
    if (enteredAadhaar.length === 4 && storedAadhaar.length === 4) {
      aadhaarBadge =
        enteredAadhaar === storedAadhaar
          ? '<span class="badge badge-green">Aadhaar *' + escapeHtml(enteredAadhaar) + " Match</span>"
          : '<span class="badge badge-red">Aadhaar Mismatch (*' + escapeHtml(storedAadhaar) + ")</span>";
    } else if (storedAadhaar.length === 4) {
      aadhaarBadge = '<span class="badge badge-gray">Kiosk Check: ****' + escapeHtml(storedAadhaar) + "</span>";
    }

    var meterClass = overQuota ? "meter-danger" : quotaPct >= 75 ? "meter-warn" : "";
    var kccWarning =
      payMethod === "KCC" && total > kccAvail
        ? ' &bull; <span class="badge badge-red">Insufficient KCC (Avail: &#8377;' + escapeHtml(formatINR(kccAvail)) + ")</span>"
        : payMethod === "KCC"
          ? ' &bull; <span class="badge badge-blue">KCC Avail: &#8377;' + escapeHtml(formatINR(kccAvail)) + "</span>"
          : "";

    preview.innerHTML =
      '<div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:8px;">' +
      '<div><strong>Verified Entitlement:</strong> ' + acres.toFixed(2) + " acres &times; " + perAcre + " = <strong>" + maxAllowed + " " + escapeHtml(unit) + " cap</strong>" +
      ' <span style="margin-left:6px;">' + bioBadge + " " + aadhaarBadge + "</span></div>" +
      '<div class="mono" style="font-size:0.82rem;">' + qty + " / " + maxAllowed + " " + escapeHtml(unit) +
      (overQuota ? ' <span class="badge badge-red">OVER QUOTA</span>' : "") +
      (overStock ? ' <span class="badge badge-red">LOW STOCK (' + stock + ")</span>" : " &bull; Stock: " + stock) +
      "</div></div>" +
      '<div class="meter-track" style="margin-bottom:10px;"><div class="meter-fill ' + meterClass + '" style="width:' + quotaPct + '%"></div></div>' +
      '<div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px;align-items:center;">' +
      '<div><strong>RBK Billing Total:</strong> &#8377;' + escapeHtml(formatINR(total)) +
      ' <span class="text-muted">(Retail MRP: &#8377;' + escapeHtml(formatINR(retailTotal)) + ")</span>" + kccWarning + "</div>" +
      '<span class="badge badge-green">Farmer Saves &#8377;' + escapeHtml(formatINR(savings)) + "</span>" +
      "</div>";
  }

  /* ---------- Live Buyer Escrow Contract Calculator ---------- */
  function updateBuyerOrderPreview() {
    var preview = document.getElementById("buyer_order_preview");
    var batchSel = document.getElementById("order_crop_batch_id");
    var qtyInput = document.getElementById("order_quantity");
    var priceInput = document.getElementById("order_unit_price");

    if (!preview || !batchSel) return;
    var opt = batchSel.selectedOptions && batchSel.selectedOptions[0];
    if (!opt || !opt.value) {
      preview.innerHTML =
        '<span class="text-muted">Select a certified crop batch above or click "Order This Batch" in the marketplace table to calculate Escrow lock value.</span>';
      return;
    }

    var maxQty = parseFloat(opt.dataset.maxQty || "0");
    var suggested = parseFloat(opt.dataset.suggestedPrice || "0");
    var qty = parseFloat((qtyInput && qtyInput.value) || "0") || 0;
    var unitPrice = parseFloat((priceInput && priceInput.value) || "0") || 0;
    var escrowTotal = qty * unitPrice;
    var sharePct = maxQty > 0 ? Math.min(100, Math.round((qty / maxQty) * 100)) : 0;
    var overBatch = maxQty > 0 && qty > maxQty;

    preview.innerHTML =
      '<div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:8px;">' +
      '<div><strong>Lot Allocation:</strong> ' + qty.toFixed(0) + " kg of " + maxQty.toFixed(0) + " kg available (" + sharePct + "%)" +
      (overBatch ? ' <span class="badge badge-red">Exceeds Lot Stock</span>' : "") + "</div>" +
      '<div class="mono" style="font-size:0.82rem;">Suggested Grade Floor: &#8377;' + escapeHtml(formatINR(suggested)) + "/kg</div>" +
      "</div>" +
      '<div class="meter-track" style="margin-bottom:10px;"><div class="meter-fill ' + (overBatch ? "meter-danger" : "") + '" style="width:' + sharePct + '%"></div></div>' +
      '<div style="display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px;align-items:center;">' +
      '<div><strong>Escrow Contract Lock:</strong> <span class="mono" style="font-size:1.05rem;font-weight:600;">&#8377;' + escapeHtml(formatINR(escrowTotal)) + "</span></div>" +
      '<span class="badge badge-blue">ESCROW_HELD until delivery &amp; KCC auto-offset</span>' +
      "</div>";
  }

  /* ---------- Table Filtering & Column Sorting ---------- */
  function ensureFilterEntry(tbodyId) {
    if (!filterState[tbodyId]) {
      filterState[tbodyId] = { text: "", attr: "", chipVal: "all", maxMoisture: null };
    }
    return filterState[tbodyId];
  }

  function applyFilterToTbody(tbodyId) {
    var tbody = document.getElementById(tbodyId);
    if (!tbody) return;
    var st = ensureFilterEntry(tbodyId);
    var rows = Array.from(tbody.querySelectorAll("tr"));

    rows.forEach(function (row) {
      if (row.children.length === 1 && row.children[0].hasAttribute("colspan")) {
        row.classList.remove("hidden");
        return;
      }

      var matchesText = !st.text || row.textContent.toLowerCase().indexOf(st.text) !== -1;

      var matchesChip = true;
      if (st.chipVal && st.chipVal !== "all") {
        var target = st.chipVal.toLowerCase();
        var attrName = st.attr || "data-status";
        var attrVal = row.getAttribute(attrName);
        if (attrVal !== null) {
          matchesChip = attrVal.toLowerCase() === target;
        } else {
          matchesChip = row.textContent.toLowerCase().indexOf(target) !== -1;
        }
      }

      var matchesMoisture = true;
      if (st.maxMoisture !== null && !isNaN(st.maxMoisture)) {
        var mVal = parseFloat(row.getAttribute("data-moisture") || "");
        if (!isNaN(mVal)) {
          matchesMoisture = mVal <= st.maxMoisture;
        }
      }

      row.classList.toggle("hidden", !(matchesText && matchesChip && matchesMoisture));
    });
  }

  function reapplyAllTableFilters() {
    Object.keys(filterState).forEach(applyFilterToTbody);
  }

  function sortTableByHeader(th) {
    var table = th.closest("table");
    if (!table || !table.tBodies.length) return;
    var tbody = table.tBodies[0];
    var headers = Array.from(th.parentElement.children);
    var colIdx = headers.indexOf(th);
    if (colIdx < 0) return;

    var mode = th.dataset.sort || "text";
    var nextDir = th.dataset.sortDir === "asc" ? "desc" : "asc";
    headers.forEach(function (h) {
      if (h !== th) {
        h.removeAttribute("data-sort-dir");
        h.removeAttribute("aria-sort");
      }
    });
    th.dataset.sortDir = nextDir;
    th.setAttribute("aria-sort", nextDir === "asc" ? "ascending" : "descending");

    var rows = Array.from(tbody.querySelectorAll("tr")).filter(function (r) {
      return !(r.children.length === 1 && r.children[0].hasAttribute("colspan"));
    });
    if (rows.length < 2) return;

    rows.sort(function (a, b) {
      var aText = ((a.children[colIdx] && a.children[colIdx].textContent) || "").trim();
      var bText = ((b.children[colIdx] && b.children[colIdx].textContent) || "").trim();

      var cmp = 0;
      if (mode === "number") {
        var aNum = parseFloat(aText.replace(/[^0-9.-]/g, ""));
        var bNum = parseFloat(bText.replace(/[^0-9.-]/g, ""));
        cmp = (isNaN(aNum) ? -Infinity : aNum) - (isNaN(bNum) ? -Infinity : bNum);
      } else {
        cmp = aText.localeCompare(bText, undefined, { numeric: true, sensitivity: "base" });
      }
      return nextDir === "asc" ? cmp : -cmp;
    });

    rows.forEach(function (row) {
      tbody.appendChild(row);
    });
  }

  /* ---------- Passport Slide-Over Drawer ---------- */
  function openPassportDrawer(code) {
    var drawer = document.getElementById("passport-drawer");
    var body = document.getElementById("passport-drawer-body");
    var title = document.getElementById("passport-drawer-title");
    if (!drawer || !body || !code) return;

    if (title) title.textContent = "Agronomic QR Passport — " + code;
    body.innerHTML = '<p class="text-muted">Loading live agronomic audit trail from MySQL...</p>';
    drawer.classList.remove("hidden");
    drawer.setAttribute("aria-hidden", "false");

    fetch("/api/buyer/passport?code=" + encodeURIComponent(code), {
      headers: { "X-Requested-With": "fetch", "Accept": "application/json" }
    })
      .then(function (resp) {
        return resp.json().then(function (data) {
          return { status: resp.status, data: data };
        });
      })
      .then(function (res) {
        if (res.data && res.data.redirect) {
          window.location.href = res.data.redirect;
          return;
        }
        var passportMarkup = res.data && (res.data.html || res.data.passport_html);
        if (passportMarkup) {
          body.innerHTML = passportMarkup;
          initAllQRCodes(body);
        } else {
          body.innerHTML = '<div class="flash flash-error">Could not load agronomic passport.</div>';
        }
      })
      .catch(function () {
        body.innerHTML = '<div class="flash flash-error">Network error loading agronomic passport.</div>';
      });
  }

  function closePassportDrawer() {
    var drawer = document.getElementById("passport-drawer");
    if (!drawer) return;
    drawer.classList.add("hidden");
    drawer.setAttribute("aria-hidden", "true");
  }

  /* ---------- Dynamic Fragment Patching ---------- */
  function patchSelectOptions(selectEl, optionsHtml) {
    var prevVal = selectEl.value;
    var defaultOpt = selectEl.dataset.defaultOption;
    var prefix = defaultOpt ? '<option value="">' + escapeHtml(defaultOpt) + "</option>" : "";
    var nextMarkup = prefix + (optionsHtml || "");

    if (selectEl.dataset.lastOptions === nextMarkup) return;
    selectEl.dataset.lastOptions = nextMarkup;
    selectEl.innerHTML = nextMarkup;

    if (prevVal) {
      var exists = Array.from(selectEl.options).some(function (o) {
        return o.value === prevVal;
      });
      if (exists) selectEl.value = prevVal;
    }
  }

  function applyStatePayload(data, options) {
    if (!data || typeof data !== "object") return;
    var opts = options || {};
    var fragments = data.fragments || {};

    document.querySelectorAll("[data-bind]").forEach(function (el) {
      var key = el.dataset.bind;
      if (!(key in fragments)) return;
      var nextHtml = String(fragments[key] == null ? "" : fragments[key]);
      if (el.innerHTML !== nextHtml) {
        el.innerHTML = nextHtml;
        if (!opts.silent) {
          el.classList.remove("is-updated");
          void el.offsetWidth;
          el.classList.add("is-updated");
        }
      }
    });

    document.querySelectorAll("select[data-bind-options]").forEach(function (sel) {
      var key = sel.dataset.bindOptions;
      if (!(key in fragments)) return;
      patchSelectOptions(sel, String(fragments[key] == null ? "" : fragments[key]));
    });

    if (!opts.isBackgroundSync) {
      if (data.tab) activateTab(data.tab);
      var wizStep = data.step || data.wizard_step;
      if (wizStep) setWizardStep(wizStep);
      if (data.farmer_id) {
        ["step2_farmer_id", "step3_farmer_id"].forEach(function (fid) {
          var sel = document.getElementById(fid);
          if (sel) sel.value = data.farmer_id;
        });
      }
      if (data.selected_ids && typeof data.selected_ids === "object") {
        Object.keys(data.selected_ids).forEach(function (elId) {
          var targetEl = document.getElementById(elId);
          if (targetEl) targetEl.value = data.selected_ids[elId];
        });
      }
    }

    initAllQRCodes();
    reapplyAllTableFilters();
    updatePosPreview();
    updateBuyerOrderPreview();

    var syncTime = document.getElementById("live-sync-time");
    if (syncTime) {
      var now = new Date();
      syncTime.textContent = "Synced " + now.toTimeString().slice(0, 8);
    }
  }

  /* ---------- Live Portal Sync Polling ---------- */
  function syncPortalState(isManual) {
    var mainEl = document.querySelector(".portal-main[data-sync-endpoint]");
    if (!mainEl || syncInFlight) return;
    var endpoint = mainEl.dataset.syncEndpoint;
    if (!endpoint) return;

    if (!isManual) {
      var toggle = document.getElementById("live-sync-toggle");
      if (toggle && !toggle.checked) return;
      if (document.hidden) return;
      var active = document.activeElement;
      if (active && mainEl.contains(active) && /^(INPUT|TEXTAREA|SELECT)$/i.test(active.tagName)) {
        if (active.type !== "checkbox" && active.type !== "search") return;
      }
    }

    syncInFlight = true;
    fetch(endpoint, {
      headers: { "X-Requested-With": "fetch", "Accept": "application/json" }
    })
      .then(function (resp) {
        return resp.json().then(function (data) {
          return { status: resp.status, data: data };
        });
      })
      .then(function (res) {
        if (res.status === 401 && res.data && res.data.redirect) {
          window.location.href = res.data.redirect;
          return;
        }
        if (res.data && res.data.fragments) {
          applyStatePayload(res.data, { isBackgroundSync: !isManual, silent: !isManual });
          if (isManual) showToast("Live data synced from MySQL.", "success");
        }
      })
      .catch(function () {
        if (isManual) showToast("Live sync failed. Will retry shortly.", "error");
      })
      .finally(function () {
        syncInFlight = false;
      });
  }

  /* ---------- Delegated Event Listeners ---------- */
  document.addEventListener("click", function (e) {
    // 1. Tabs
    var tabBtn = e.target.closest("[data-tab-target]");
    if (tabBtn) {
      activateTab(tabBtn.dataset.tabTarget);
      return;
    }

    // 2. RBK Wizard Steps
    var wizBtn = e.target.closest("[data-wizard-step]");
    if (wizBtn) {
      setWizardStep(wizBtn.dataset.wizardStep);
      return;
    }

    // 3. Buyer Quick Order Batch Prefill
    var orderBtn = e.target.closest("[data-order-batch]");
    if (orderBtn) {
      var select = document.getElementById("order_crop_batch_id");
      var qtyEl = document.getElementById("order_quantity");
      var priceEl = document.getElementById("order_unit_price");
      var card = document.getElementById("buyer-order-form-card");
      if (select) {
        select.value = orderBtn.dataset.orderBatch;
        var opt = select.selectedOptions && select.selectedOptions[0];
        if (opt && qtyEl && opt.dataset.maxQty) {
          qtyEl.value = Math.min(Math.round(parseFloat(opt.dataset.maxQty)), 1500);
        }
        if (opt && priceEl && opt.dataset.suggestedPrice) {
          priceEl.value = opt.dataset.suggestedPrice;
        }
      }
      updateBuyerOrderPreview();
      if (card) {
        card.scrollIntoView({ behavior: "smooth", block: "center" });
        card.classList.remove("is-updated");
        void card.offsetWidth;
        card.classList.add("is-updated");
      }
      return;
    }

    // 4. Filter Chips
    var chipBtn = e.target.closest("[data-filter-chip]");
    if (chipBtn) {
      var tbodyId = chipBtn.dataset.filterChip;
      var attr = chipBtn.dataset.filterAttr || "data-status";
      var val = chipBtn.dataset.filterVal || "all";
      var st = ensureFilterEntry(tbodyId);
      st.attr = attr;
      st.chipVal = val;

      var group = chipBtn.closest(".filter-chips");
      if (group) {
        group.querySelectorAll("[data-filter-chip]").forEach(function (c) {
          c.classList.toggle("active", c === chipBtn);
        });
      }
      applyFilterToTbody(tbodyId);
      return;
    }

    // 5. Table Sort Headers
    var sortTh = e.target.closest("th[data-sort]");
    if (sortTh) {
      sortTableByHeader(sortTh);
      return;
    }

    // 6. Slide-Over QR Passport Drawer Trigger
    var auditBtn = e.target.closest("[data-audit-qr]");
    if (auditBtn) {
      e.preventDefault();
      openPassportDrawer(auditBtn.dataset.auditQr);
      return;
    }

    // 7. Drawer Close
    if (e.target.closest("#passport-drawer-close") || e.target.id === "passport-drawer") {
      closePassportDrawer();
      return;
    }

    // 8. Manual Live Sync Button
    if (e.target.closest("#live-sync-now")) {
      syncPortalState(true);
    }
  });

  document.addEventListener("input", function (e) {
    var target = e.target;
    if (!target) return;

    // 1. Live Table Search
    if (target.matches("[data-filter-input]")) {
      var tbodyId = target.dataset.filterInput;
      var st = ensureFilterEntry(tbodyId);
      st.text = (target.value || "").trim().toLowerCase();
      applyFilterToTbody(tbodyId);
      return;
    }

    // 2. Buyer Max Moisture Filter
    if (target.id === "buyer-max-moisture") {
      var mSt = ensureFilterEntry("tbody-buyer-market");
      var parsed = parseFloat(target.value);
      mSt.maxMoisture = target.value.trim() === "" || isNaN(parsed) ? null : parsed;
      applyFilterToTbody("tbody-buyer-market");
      return;
    }

    // 3. RBK Supply Accepted / Rejected Auto-Balance
    if (target.matches('input[name="accepted_quantity"]')) {
      var row = target.closest("[data-supply-row]");
      if (row) {
        var ordered = parseInt(row.dataset.ordered || "0", 10);
        var rej = row.querySelector('input[name="rejected_quantity"]');
        if (rej) {
          var acc = parseInt(target.value || "0", 10);
          rej.value = Math.max(0, ordered - (isNaN(acc) ? 0 : acc));
        }
      }
      return;
    }

    // 4. RBK POS & Buyer Order Calculators
    if (
      target.id === "pos_quantity" ||
      target.id === "pos_aadhaar_last4"
    ) {
      updatePosPreview();
      return;
    }
    if (target.id === "order_quantity" || target.id === "order_unit_price") {
      updateBuyerOrderPreview();
    }
  });

  document.addEventListener("change", function (e) {
    var target = e.target;
    if (!target) return;

    // 1. RBK Division Autofill
    if (target.id === "reg_division_select") {
      var opt = target.selectedOptions && target.selectedOptions[0];
      if (!opt || !opt.value) return;
      var fields = {
        reg_state: opt.dataset.state || "Andhra Pradesh",
        reg_district: opt.dataset.district || "",
        reg_mandal: opt.dataset.mandal || "",
        reg_village: opt.dataset.village || "",
        reg_pincode: opt.dataset.pincode || ""
      };
      Object.keys(fields).forEach(function (id) {
        var input = document.getElementById(id);
        if (input) input.value = fields[id];
      });
      return;
    }

    // 2. POS Selectors
    if (
      target.id === "pos_farmer_id" ||
      target.id === "pos_batch_id" ||
      target.id === "pos_payment_method"
    ) {
      updatePosPreview();
      return;
    }

    // 3. Buyer Batch Select Auto-Fill Suggested Rate & Preview
    if (target.id === "order_crop_batch_id") {
      var bOpt = target.selectedOptions && target.selectedOptions[0];
      var priceEl = document.getElementById("order_unit_price");
      var qtyEl = document.getElementById("order_quantity");
      if (bOpt && bOpt.value) {
        if (priceEl && !priceEl.value && bOpt.dataset.suggestedPrice) {
          priceEl.value = bOpt.dataset.suggestedPrice;
        }
        if (qtyEl && !qtyEl.value && bOpt.dataset.maxQty) {
          qtyEl.value = Math.min(Math.round(parseFloat(bOpt.dataset.maxQty)), 1500);
        }
      }
      updateBuyerOrderPreview();
      return;
    }

    // 4. Dynamic Passport Tab Selector
    if (target.id === "passport_code_select" && target.value) {
      var pForm = target.closest("form[data-passport-lookup-form]");
      if (pForm) pForm.requestSubmit ? pForm.requestSubmit() : pForm.dispatchEvent(new Event("submit", { cancelable: true, bubbles: true }));
      return;
    }

    // 5. Live Sync Toggle
    if (target.id === "live-sync-toggle") {
      var dot = document.getElementById("live-sync-dot");
      if (dot) dot.classList.toggle("is-paused", !target.checked);
    }
  });

  /* ---------- Async Portal Form Submission & Dynamic Passport Lookup ---------- */
  document.addEventListener("submit", function (e) {
    var form = e.target;
    if (!form || form.hasAttribute("data-no-async")) return;

    // 1. Dynamic QR Passport Lookup Form
    if (form.matches("form[data-passport-lookup-form]")) {
      e.preventDefault();
      var codeSel = form.querySelector('[name="code"]');
      var code = codeSel ? codeSel.value.trim() : "";
      if (!code) return;

      fetch("/api/buyer/passport?code=" + encodeURIComponent(code), {
        headers: { "X-Requested-With": "fetch", "Accept": "application/json" }
      })
        .then(function (resp) {
          return resp.json();
        })
        .then(function (data) {
          if (data && data.redirect) {
            window.location.href = data.redirect;
            return;
          }
          var container = document.getElementById("buyer-passport-container");
          var pMarkup = data && (data.html || data.passport_html);
          if (container && pMarkup) {
            container.innerHTML = pMarkup;
            initAllQRCodes(container);
          }
          if (window.history && window.history.replaceState) {
            try {
              var url = new URL(window.location.href);
              url.searchParams.set("tab", "btab-passport");
              url.searchParams.set("code", code);
              window.history.replaceState({}, "", url.toString());
            } catch (err) {
              // Ignore
            }
          }
        })
        .catch(function () {
          showToast("Failed to load passport audit.", "error");
        });
      return;
    }

    // 2. All Portal POST Action Forms
    var method = (form.getAttribute("method") || "GET").toUpperCase();
    var isPortalPost =
      method === "POST" && (form.hasAttribute("data-async-form") || Boolean(form.closest(".portal-main")));
    if (!isPortalPost) return;

    e.preventDefault();

    var submitter = e.submitter || null;
    var fd;
    try {
      fd = submitter ? new FormData(form, submitter) : new FormData(form);
    } catch (err) {
      fd = new FormData(form);
      if (submitter && submitter.name) {
        fd.append(submitter.name, submitter.value || "");
      }
    }

    var buttons = Array.from(form.querySelectorAll('button[type="submit"], input[type="submit"]'));
    buttons.forEach(function (b) {
      b.disabled = true;
    });

    fetch(form.getAttribute("action") || window.location.pathname, {
      method: "POST",
      headers: { "X-Requested-With": "fetch", "Accept": "application/json" },
      body: new URLSearchParams(fd)
    })
      .then(function (resp) {
        return resp.json().then(function (data) {
          return { status: resp.status, data: data };
        });
      })
      .then(function (res) {
        var data = res.data || {};
        if (res.status === 401 && data.redirect) {
          window.location.href = data.redirect;
          return;
        }

        // Clear any initial SSR flash alert so the live toast owns status updates
        var flashRegion = document.getElementById("portal-flash-region");
        if (flashRegion) flashRegion.innerHTML = "";

        showToast(data.message || (data.ok ? "Saved successfully." : "Request could not be completed."), data.ok ? "success" : "error");
        applyStatePayload(data, { isBackgroundSync: false, silent: false });

        if (data.ok && form.closest("#buyer-order-form-card")) {
          var qIn = document.getElementById("order_quantity");
          var pIn = document.getElementById("order_unit_price");
          if (qIn) qIn.value = "";
          if (pIn) pIn.value = "";
          updateBuyerOrderPreview();
        }
      })
      .catch(function () {
        showToast("Network or server error submitting form. Please try again.", "error");
      })
      .finally(function () {
        buttons.forEach(function (b) {
          b.disabled = false;
        });
      });
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") closePassportDrawer();
  });

  /* ---------- Initial Hydration ---------- */
  document.addEventListener("DOMContentLoaded", function () {
    var params = new URLSearchParams(window.location.search);
    var urlTab = params.get("tab");
    if (urlTab) {
      activateTab(urlTab, true);
    } else {
      var activeBtn = document.querySelector(".tab-btn.active");
      if (activeBtn) activateTab(activeBtn.dataset.tabTarget, true);
    }

    var stepParam = params.get("step");
    if (stepParam) setWizardStep(stepParam);

    initAllQRCodes();
    updatePosPreview();
    updateBuyerOrderPreview();

    if (document.querySelector(".portal-main[data-sync-endpoint]")) {
      syncTimer = window.setInterval(function () {
        syncPortalState(false);
      }, 15000);
    }
  });
})();
