// 外部リンクに target="_blank" と rel="noopener" を自動付与
document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll('.md-content a[href^="http"]').forEach(function (a) {
    a.setAttribute("target", "_blank");
    a.setAttribute("rel", "noopener");
  });
});
