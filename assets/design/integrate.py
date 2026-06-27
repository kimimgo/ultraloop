#!/usr/bin/env python3
"""Design integrator (general) — token-normalize + cross-navigation injection.

Config-driven; NO project specifics are baked in. Supply a JSON config (or CLI flags)
per target project. This is a reusable template shipped with the ultraloop:design skill.

Usage:
  integrate.py --config integrate.config.json
  integrate.py --src DIR --dst DIR --pages '{"design.html":"out.html"}' \
               --colors '{"5de1fd":"36c5e0"}' --nav '[["Home","out.html",{"exact":false,"max":14}]]'

JSON config schema (all keys optional except src/dst/pages):
{
  "src":   "/abs/path/to/stitch/designs",      # source HTML dir
  "dst":   "/abs/path/to/published",           # output dir (created if missing)
  "pages": {"design.html": "published.html"},  # source -> published filename
  "colors":{"5de1fd": "36c5e0"},               # inline hex normalization (NO leading '#')
  "nav":   [["match text","target.html",{"exact": false, "max": 14}]]  # cross-nav wiring
}
"""
import re
import sys
import json
import argparse
import pathlib

# Generic cross-navigation: wires in-design affordances (tree/breadcrumb/rows) whose text
# matches an entry to its sibling page. No pill switcher. MAP is injected from config.
NAV_TEMPLATE = r"""
<script>/* cross-navigation — wires visible affordances to sibling pages (config-driven) */
(function(){
  var MAP = __MAP__;
  function go(url){ return function(ev){ ev.preventDefault(); ev.stopPropagation(); location.href=url; }; }
  function wire(match,url,opt){
    opt=opt||{};
    Array.prototype.slice.call(document.querySelectorAll("body *")).forEach(function(el){
      if(el.dataset.xnav) return;
      var txt=(el.textContent||"").replace(/\s+/g," ").trim();
      if(!txt) return;
      var hit = opt.exact ? (txt===match) : (txt.indexOf(match)>-1 && txt.length<=(opt.max||60));
      if(!hit) return;
      var deeper = Array.prototype.some.call(el.children, function(c){
        var t=(c.textContent||"").replace(/\s+/g," ").trim();
        return opt.exact ? (t===match) : (t.indexOf(match)>-1 && t.length<=(opt.max||60));
      });
      if(deeper) return; // let the smallest matching element own it
      var t = el.closest("button,a,li,tr,[role=row],[role=button],div") || el;
      if(t.dataset.xnav) return;
      t.dataset.xnav="1"; t.style.cursor="pointer"; t.setAttribute("title","→ "+url);
      t.addEventListener("mouseenter",function(){t.style.outline="1px solid rgba(120,170,255,.5)"; t.style.outlineOffset="-1px";});
      t.addEventListener("mouseleave",function(){t.style.outline="";});
      t.addEventListener("click", go(url));
    });
  }
  MAP.forEach(function(m){ wire(m[0],m[1],m[2]); });
})();
</script>
"""


def build_nav(nav_map):
    return NAV_TEMPLATE.replace("__MAP__", json.dumps(nav_map))


def integrate(src_path, dst_path, colors, nav_js):
    html = src_path.read_text(encoding="utf-8", errors="ignore")
    for a, b in colors.items():
        html = re.sub("#" + a, "#" + b, html, flags=re.I)
    if nav_js:
        if "</body>" in html:
            html = html.replace("</body>", nav_js + "\n</body>", 1)
        else:
            html += nav_js
    dst_path.write_text(html, encoding="utf-8")
    return len(html)


def main():
    ap = argparse.ArgumentParser(description="Config-driven design integrator (token-normalize + cross-nav).")
    ap.add_argument("--config", help="JSON config with src/dst/pages/colors/nav")
    ap.add_argument("--src", help="source HTML dir (overrides config)")
    ap.add_argument("--dst", help="output dir (overrides config)")
    ap.add_argument("--pages", help="JSON object {src.html: out.html}")
    ap.add_argument("--colors", help="JSON object {hex: hex} (no leading #)")
    ap.add_argument("--nav", help="JSON array of [match, url, opts]")
    a = ap.parse_args()

    cfg = {}
    if a.config:
        cfg = json.loads(pathlib.Path(a.config).read_text(encoding="utf-8"))

    src = a.src or cfg.get("src")
    dst = a.dst or cfg.get("dst")
    pages = json.loads(a.pages) if a.pages else cfg.get("pages", {})
    colors = json.loads(a.colors) if a.colors else cfg.get("colors", {})
    nav = json.loads(a.nav) if a.nav else cfg.get("nav", [])

    if not src or not dst or not pages:
        sys.exit("need --src, --dst and --pages (or a --config providing them)")

    src_dir, dst_dir = pathlib.Path(src), pathlib.Path(dst)
    dst_dir.mkdir(parents=True, exist_ok=True)
    nav_js = build_nav(nav) if nav else ""

    for s, d in pages.items():
        n = integrate(src_dir / s, dst_dir / d, colors, nav_js)
        print(f"{d}: {n} bytes")
    print("done")


if __name__ == "__main__":
    main()
