// Source line number toggle button
// Adds a button to the header to show/hide Markdown source line numbers
(function () {
  var STORAGE_KEY = "mkdocs-source-lines";

  // Hash/number icon (represents line numbers)
  var ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<line x1="4" y1="9" x2="20" y2="9"/>' +
    '<line x1="4" y1="15" x2="20" y2="15"/>' +
    '<line x1="10" y1="3" x2="8" y2="21"/>' +
    '<line x1="16" y1="3" x2="14" y2="21"/>' +
    "</svg>";

  function isEnabled() {
    try {
      return localStorage.getItem(STORAGE_KEY) === "1";
    } catch (e) {
      return false;
    }
  }

  function setEnabled(val) {
    try {
      localStorage.setItem(STORAGE_KEY, val ? "1" : "0");
    } catch (e) {}
  }

  function applyState(enabled) {
    if (enabled) {
      document.documentElement.classList.add("show-source-lines");
    } else {
      document.documentElement.classList.remove("show-source-lines");
    }
  }

  function setup() {
    var headerInner = document.querySelector(".md-header__inner");
    if (!headerInner) return;

    // Don't duplicate
    if (headerInner.querySelector(".source-lines-toggle")) return;

    var btn = document.createElement("button");
    btn.className = "source-lines-toggle";
    btn.type = "button";
    btn.title = "ソース行番号の表示切替";
    btn.innerHTML = ICON;

    var enabled = isEnabled();
    if (enabled) btn.classList.add("active");
    applyState(enabled);

    btn.addEventListener("click", function () {
      var nowEnabled = !isEnabled();
      setEnabled(nowEnabled);
      applyState(nowEnabled);
      btn.classList.toggle("active", nowEnabled);
    });

    headerInner.appendChild(btn);
  }

  // Initial
  setup();

  // Instant loading support
  var container = document.querySelector("[data-md-component=container]");
  if (container && container.parentNode) {
    new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        for (var j = 0; j < mutations[i].addedNodes.length; j++) {
          var node = mutations[i].addedNodes[j];
          if (
            node.nodeType === 1 &&
            node.getAttribute &&
            node.getAttribute("data-md-component") === "container"
          ) {
            requestAnimationFrame(setup);
            return;
          }
        }
      }
    }).observe(container.parentNode, { childList: true });
  }
})();
