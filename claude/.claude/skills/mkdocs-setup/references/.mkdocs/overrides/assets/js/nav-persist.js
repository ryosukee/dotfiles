// サイドバーのセクション開閉状態を localStorage で永続化する
// instant loading による DOM 全置換に対応
(function () {
  var STORAGE_KEY = "mkdocs-nav-state";

  function saveState() {
    var state = {};
    document.querySelectorAll(".md-nav__toggle").forEach(function (el) {
      if (el.id && el.id.startsWith("__nav_")) {
        state[el.id] = el.checked;
      }
    });
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch (e) {}
  }

  function restoreState() {
    var raw;
    try {
      raw = localStorage.getItem(STORAGE_KEY);
    } catch (e) {
      return;
    }
    if (!raw) return;

    var state;
    try {
      state = JSON.parse(raw);
    } catch (e) {
      return;
    }

    document.querySelectorAll(".md-nav__toggle").forEach(function (el) {
      if (el.id && el.id in state) {
        el.classList.remove("md-toggle--indeterminate");
        el.checked = state[el.id];
      }
    });
  }

  // イベント委譲: DOM 置換後もリスナーが生き残る
  document.addEventListener("change", function (e) {
    if (
      e.target &&
      e.target.classList &&
      e.target.classList.contains("md-nav__toggle")
    ) {
      saveState();
    }
  });

  // 初回読み込み
  restoreState();

  // instant loading 対応: container の親を監視して DOM 置換を検知
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
            requestAnimationFrame(restoreState);
            return;
          }
        }
      }
    }).observe(container.parentNode, { childList: true });
  }
})();
