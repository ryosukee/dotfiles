// 右サイドバー（TOC）の表示/非表示トグル
// ヘッダーの GitHub リンクの右隣に配置
// 閉じた状態でホバーすると一時的にピーク表示
(function () {
  var STORAGE_KEY = "mkdocs-toc-collapsed";
  var PEEK_CLOSE_DELAY = 300; // ms: サイドバーから離れてから閉じるまでの猶予

  // 開いてる時: 右矢印 (閉じる方向)
  var ICON_OPENED =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">' +
    '<path d="M3 3h18v18H3V3zm12 2v14M10 8l3 4-3 4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' +
    "</svg>";

  // 閉じてる時: 左矢印 (開く方向)
  var ICON_CLOSED =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">' +
    '<path d="M3 3h18v18H3V3zm12 2v14M11 8l-3 4 3 4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' +
    "</svg>";

  function isCollapsed() {
    try {
      return localStorage.getItem(STORAGE_KEY) === "1";
    } catch (e) {
      return false;
    }
  }

  function setCollapsed(val) {
    try {
      localStorage.setItem(STORAGE_KEY, val ? "1" : "0");
    } catch (e) {}
  }

  function setup() {
    var sidebar = document.querySelector(".md-sidebar--secondary");
    if (!sidebar) return;

    var headerInner = document.querySelector(".md-header__inner");
    if (!headerInner) return;

    // 既にボタンがあれば何もしない
    if (headerInner.querySelector(".toc-toggle")) return;

    var btn = document.createElement("button");
    btn.className = "toc-toggle";
    btn.type = "button";
    btn.title = "目次の表示切替";

    var collapsed = isCollapsed();
    btn.innerHTML = collapsed ? ICON_CLOSED : ICON_OPENED;
    if (collapsed) sidebar.classList.add("toc-collapsed");

    // クリックで永続的に開閉
    btn.addEventListener("click", function () {
      // ピーク中なら解除
      sidebar.classList.remove("toc-peeking");
      clearTimeout(peekTimer);

      var isNowCollapsed = sidebar.classList.toggle("toc-collapsed");
      btn.innerHTML = isNowCollapsed ? ICON_CLOSED : ICON_OPENED;
      setCollapsed(isNowCollapsed);
    });

    // --- ピーク機能 ---
    var peekTimer = null;

    function startPeek() {
      if (!sidebar.classList.contains("toc-collapsed")) return;
      clearTimeout(peekTimer);
      sidebar.classList.add("toc-peeking");
    }

    function schedulClosePeek() {
      clearTimeout(peekTimer);
      peekTimer = setTimeout(function () {
        sidebar.classList.remove("toc-peeking");
      }, PEEK_CLOSE_DELAY);
    }

    function cancelClosePeek() {
      clearTimeout(peekTimer);
    }

    // ボタンにホバー → ピーク開始
    btn.addEventListener("mouseenter", startPeek);
    btn.addEventListener("mouseleave", schedulClosePeek);

    // サイドバーにホバー中 → ピーク維持
    sidebar.addEventListener("mouseenter", function () {
      if (sidebar.classList.contains("toc-peeking")) {
        cancelClosePeek();
      }
    });
    sidebar.addEventListener("mouseleave", function () {
      if (sidebar.classList.contains("toc-peeking")) {
        schedulClosePeek();
      }
    });

    // ヘッダーの末尾に追加（GitHub リンクの右隣）
    headerInner.appendChild(btn);
  }

  // 初回
  setup();

  // instant loading 対応
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
