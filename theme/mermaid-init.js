// Load Mermaid.js from CDN and render ```mermaid code blocks
(function () {
  var script = document.createElement("script");
  script.src =
    "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js";
  script.onload = function () {
    mermaid.initialize({
      startOnLoad: false,
      theme: "default",
      securityLevel: "loose",
    });

    // mdbook renders ```mermaid as <code class="language-mermaid"> inside <pre>
    var blocks = document.querySelectorAll("code.language-mermaid");
    blocks.forEach(function (block, i) {
      var pre = block.parentElement;
      var container = document.createElement("div");
      container.className = "mermaid";
      container.textContent = block.textContent;
      pre.parentNode.replaceChild(container, pre);
    });

    mermaid.run();
  };
  document.head.appendChild(script);
})();
