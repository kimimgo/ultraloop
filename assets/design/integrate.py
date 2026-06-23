#!/usr/bin/env python3
import re, sys, pathlib

SRC = pathlib.Path("/home/imgyu/workspace/infra/services/artifacts/m11/.stitch/designs")
DST = pathlib.Path("/home/imgyu/workspace/infra/services/artifacts/public")

# design filename -> published filename
PAGES = {
    "dashboard.html":     "m11-dashboard.html",
    "workspace.html":     "m11-workspace.html",
    "evidence-gate.html": "m11-evidence.html",
    "job-monitor.html":   "m11-job.html",
    "vnv.html":           "m11-vnv.html",
}

# conservative token normalization (inline hex -> foamlab DESIGN.md)
COLOR = {
    "5de1fd": "36c5e0", "50d7f2": "36c5e0", "00f2ff": "36c5e0",  # cyan -> instrument cyan
    "fabb62": "f2b45c",                                           # amber -> agent amber
    "101418": "15181d",                                           # bg -> app base
}

NAV_JS = r"""
<script>/* m11 cross-navigation — wires real in-design affordances (tree/breadcrumb/rows) to sibling pages; NO pill switcher */
(function(){
  var MAP = [
    ["foamlab", "m11-dashboard.html", {exact:false, max:14}],
    ["Premixed CH4 flame", "m11-workspace.html", {exact:false, max:90}],
    ["Plan v2", "m11-workspace.html", {exact:false, max:24}],
    ["φ=0.90", "m11-evidence.html", {exact:false, max:30}],
    ["φ=0.70", "m11-vnv.html", {exact:false, max:30}],
    ["Job #13", "m11-job.html", {exact:false, max:30}],
  ];
  function go(url){ return function(ev){ ev.preventDefault(); ev.stopPropagation(); location.href=url; }; }
  function wire(match,url,opt){
    opt=opt||{};
    Array.prototype.slice.call(document.querySelectorAll("body *")).forEach(function(el){
      if(el.dataset.m11) return;
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
      if(t.dataset.m11) return;
      t.dataset.m11="1"; t.style.cursor="pointer"; t.setAttribute("title","→ "+url);
      t.addEventListener("mouseenter",function(){t.style.outline="1px solid rgba(54,197,224,.5)"; t.style.outlineOffset="-1px";});
      t.addEventListener("mouseleave",function(){t.style.outline="";});
      t.addEventListener("click", go(url));
    });
  }
  MAP.forEach(function(m){ wire(m[0],m[1],m[2]); });
})();
</script>
"""

def integrate(src_name, dst_name):
    html = (SRC/src_name).read_text(encoding="utf-8", errors="ignore")
    for a,b in COLOR.items():
        html = re.sub("#"+a, "#"+b, html, flags=re.I)
    if "</body>" in html:
        html = html.replace("</body>", NAV_JS + "\n</body>", 1)
    else:
        html += NAV_JS
    (DST/dst_name).write_text(html, encoding="utf-8")
    return len(html)

for s,d in PAGES.items():
    n = integrate(s,d)
    print(f"{d}: {n} bytes")
print("done")
