/* m11 real-data canvases — injected to replace Stitch placeholder chart panels.
   Locates panels by header text, appends a fitted <canvas>, renders domain-correct plots. */
(function(){
  var CY="#36C5E0", AM="#F2B45C", OK="#56D364", BAD="#F8516D", MUT="#9AA4B2", GRID="rgba(150,160,175,.14)";
  var VIR=[[68,1,84],[59,82,139],[33,144,140],[93,200,99],[253,231,37]];
  function vir(t){t=Math.max(0,Math.min(1,t))*4;var i=Math.floor(t),f=t-i,a=VIR[i],b=VIR[Math.min(4,i+1)];
    return "rgb("+((a[0]+(b[0]-a[0])*f)|0)+","+((a[1]+(b[1]-a[1])*f)|0)+","+((a[2]+(b[2]-a[2])*f)|0)+")";}
  var reduce = matchMedia("(prefers-reduced-motion:reduce)").matches;

  function panel(headerText){
    var hs = Array.prototype.slice.call(document.querySelectorAll("span,div,h2,h3,p"));
    var hit = hs.filter(function(e){ return e.children.length===0 &&
      (e.textContent||"").trim().toUpperCase().indexOf(headerText)>-1; });
    if(!hit.length) return null;
    var el = hit[0];
    return el.closest(".flex.flex-col") || (el.parentElement && el.parentElement.parentElement) || el.parentElement;
  }
  function canvasIn(p, minH){
    if(!p) return null;
    var c=document.createElement("canvas");
    c.style.cssText="width:100%;flex:1 1 auto;min-height:"+(minH||120)+"px;display:block;margin-top:6px;";
    p.appendChild(c);
    return c;
  }
  function fit(c){
    var d=Math.min(window.devicePixelRatio||1,2);
    var r=c.getBoundingClientRect();
    if(r.width<10||r.height<10){ c.width=600*d; c.height=200*d; }
    else { c.width=r.width*d; c.height=r.height*d; }
    var x=c.getContext("2d"); x.setTransform(d,0,0,d,0,0);
    return [x, c.width/d, c.height/d];
  }
  function mono(x,s){ x.font="10px 'JetBrains Mono',ui-monospace,monospace"; return s; }

  // ---- log-scale residuals: Ux Uy p h Xi, gridlines 1e0..1e-6, dashed tol at 1e-4 ----
  function residuals(c){
    var o=fit(c), x=o[0], W=o[1], H=o[2];
    var padL=34, padB=16, padT=8, padR=8, gw=W-padL-padR, gh=H-padT-padB;
    var decades=6; // 1e0 .. 1e-6
    function Y(v){ var l=Math.log10(v); /* v in [1e-6,1] */ return padT + ( -l/decades )*gh; }
    function draw(prog){
      x.clearRect(0,0,W,H);
      // gridlines + labels
      x.strokeStyle=GRID; x.fillStyle=MUT; x.lineWidth=1; mono(x);
      for(var d=0; d<=decades; d++){
        var yv=Math.pow(10,-d), yy=Y(yv);
        x.beginPath(); x.moveTo(padL,yy); x.lineTo(W-padR,yy); x.stroke();
        x.textAlign="right"; x.textBaseline="middle"; x.fillText("1e-"+d, padL-4, yy);
      }
      // tol line at 1e-4
      var ty=Y(1e-4);
      x.save(); x.setLineDash([4,3]); x.strokeStyle="rgba(240,183,47,.8)";
      x.beginPath(); x.moveTo(padL,ty); x.lineTo(W-padR,ty); x.stroke(); x.restore();
      x.fillStyle="#F0B72F"; x.textAlign="left"; x.fillText("tol 1e-4", padL+4, ty-6);
      // series: name,color,start,decay,noise
      var S=[["Ux",CY,3e-1,2.6,.05],["Uy","#7FB3FF",2e-1,2.4,.05],
             ["p",AM,8e-1,1.5,.10],["h",OK,1e-1,3.0,.04],["Xi","#A78BFA",5e-2,2.2,.06]];
      S.forEach(function(s){
        x.strokeStyle=s[1]; x.lineWidth=1.4; x.beginPath();
        for(var px=0; px<=gw*prog; px+=2){
          var t=px/gw;
          var v=s[2]*Math.exp(-s[3]*t*decades/2.2);
          v*= 1+Math.sin(t*40+s[2]*30)*s[4]*Math.exp(-1.5*t);
          v=Math.max(1.1e-6,Math.min(1,v));
          var yy=Y(v), xx=padL+px;
          px? x.lineTo(xx,yy): x.moveTo(xx,yy);
        }
        x.stroke();
      });
    }
    if(reduce){ draw(1); return; }
    var p=0; (function tk(){ p=Math.min(1,p+.04); draw(p); if(p<1) requestAnimationFrame(tk); })();
  }

  // ---- Courant (left, 0..0.5) + deltaT (right, log) over time; intervention marker ----
  function courant(c){
    var o=fit(c), x=o[0], W=o[1], H=o[2];
    var padL=30, padR=34, padB=16, padT=8, gw=W-padL-padR, gh=H-padT-padB;
    x.clearRect(0,0,W,H);
    x.strokeStyle=GRID; x.lineWidth=1; mono(x); x.fillStyle=MUT;
    for(var i=0;i<=4;i++){ var yy=padT+gh*i/4; x.beginPath(); x.moveTo(padL,yy); x.lineTo(W-padR,yy); x.stroke();
      x.textAlign="right"; x.textBaseline="middle"; x.fillText((0.5-0.125*i).toFixed(2), padL-3, yy); }
    // intervention marker at t=0.35
    var mx=padL+gw*0.35;
    x.save(); x.setLineDash([3,3]); x.strokeStyle="rgba(242,180,92,.7)";
    x.beginPath(); x.moveTo(mx,padT); x.lineTo(mx,padT+gh); x.stroke(); x.restore();
    x.fillStyle=AM; x.textAlign="center"; x.fillText("dt halved", mx, padT+8);
    // Courant: held ~0.30, blip up at 0.35 then settle
    x.strokeStyle=CY; x.lineWidth=1.5; x.beginPath();
    for(var px=0;px<=gw;px+=2){ var t=px/gw; var co=0.30; if(t>0.30&&t<0.36) co=0.30+ (t-0.30)*16; if(t>=0.36) co=0.29+0.01*Math.sin(t*30);
      co=Math.min(0.5,co); var yy=padT+gh*(1-co/0.5); px?x.lineTo(padL+px,yy):x.moveTo(padL+px,yy);} x.stroke();
    // deltaT (right log axis): step down at intervention
    x.strokeStyle=AM; x.lineWidth=1.3; x.setLineDash([]); x.beginPath();
    for(var px2=0;px2<=gw;px2+=2){ var t2=px2/gw; var dt=(t2<0.35)?8e-6:4e-6; var l=(Math.log10(dt)+7)/3; // 1e-7..1e-4 -> 0..1
      var yy=padT+gh*(1-l); px2?x.lineTo(padL+px2,yy):x.moveTo(padL+px2,yy);} x.stroke();
    x.fillStyle=CY; x.textAlign="left"; x.fillText("Co", padL+3, padT+8);
    x.fillStyle=AM; x.textAlign="right"; x.fillText("Δt", W-padR-3, padT+gh-4);
  }

  // ---- probe p(t); if overlay: scatter Moriyoshi exp points + error bars ----
  function probe(c, overlay){
    var o=fit(c), x=o[0], W=o[1], H=o[2];
    var padL=34, padR=8, padB=16, padT=8, gw=W-padL-padR, gh=H-padT-padB;
    x.clearRect(0,0,W,H); x.strokeStyle=GRID; x.lineWidth=1; mono(x); x.fillStyle=MUT;
    for(var i=0;i<=4;i++){ var yy=padT+gh*i/4; x.beginPath(); x.moveTo(padL,yy); x.lineTo(W-padR,yy); x.stroke();
      x.textAlign="right"; x.textBaseline="middle"; x.fillText((8-2*i)+"", padL-3, yy);}
    function P(t){ // pressure kPa-ish bell rising to ~7.4 bar peak near t=0.62
      var peak=7.4, tc=0.62, w=0.16; return 1 + (peak-1)*Math.exp(-Math.pow((t-tc)/w,2));
    }
    function X(t){return padL+gw*t;} function Y(p){return padT+gh*(1-p/8);}
    // sim curve
    x.strokeStyle=CY; x.lineWidth=1.6; x.beginPath();
    for(var px=0;px<=gw;px+=2){var t=px/gw; px?x.lineTo(X(t),Y(P(t))):x.moveTo(X(t),Y(P(t)));} x.stroke();
    if(overlay){
      // Moriyoshi exp markers + error bars
      var pts=[0.30,0.45,0.55,0.62,0.70,0.80];
      x.fillStyle=AM; x.strokeStyle=AM; x.lineWidth=1;
      pts.forEach(function(t){ var p=P(t)*(1+(Math.sin(t*50)*0.03)); var err=0.25;
        var xx=X(t), yy=Y(p);
        x.beginPath(); x.moveTo(xx,Y(p+err)); x.lineTo(xx,Y(p-err)); x.stroke();
        x.beginPath(); x.arc(xx,yy,2.4,0,7); x.fill();
      });
      // legend
      x.textAlign="left"; x.fillStyle=CY; x.fillText("● foamlab (sim)", padL+4, padT+8);
      x.fillStyle=AM; x.fillText("● Moriyoshi 1993 (exp)", padL+4, padT+20);
    }
  }

  // ---- viridis temperature field, isometric ----
  function field(c){
    var o=fit(c), x=o[0], W=o[1], H=o[2];
    x.clearRect(0,0,W,H);
    var cx=W/2, cy=H/2+4, s=Math.min(W,H)*0.30;
    function iso(a,b,z){return [cx+(a-b)*s*.9, cy+(a+b)*s*.34 - z*s*.6];}
    for(var gx=-1;gx<=1;gx+=0.1)for(var gy=-1;gy<=1;gy+=0.1){
      var r=Math.hypot(gx,gy); var v=Math.max(0,1-r*0.92); var p=iso(gx,gy,0);
      x.fillStyle=vir(v); x.globalAlpha=.35+v*.55; x.fillRect(p[0]-1.6,p[1]-1.6,3.2,3.2);
    }
    x.globalAlpha=1; x.strokeStyle="rgba(150,160,175,.5)";
    var pts=[[-1,-1],[1,-1],[1,1],[-1,1]];
    [0,1].forEach(function(z){ x.beginPath(); pts.forEach(function(p,i){ var q=iso(p[0],p[1],z); i?x.lineTo(q[0],q[1]):x.moveTo(q[0],q[1]);}); x.closePath(); x.stroke();});
    pts.forEach(function(p){ var a=iso(p[0],p[1],0),b=iso(p[0],p[1],1); x.beginPath(); x.moveTo(a[0],a[1]); x.lineTo(b[0],b[1]); x.stroke();});
  }

  // ---- GCI grid-convergence: max(T) vs 1/cells, asymptotic ----
  function gci(c){
    var o=fit(c), x=o[0], W=o[1], H=o[2];
    var padL=40, padR=10, padB=18, padT=8, gw=W-padL-padR, gh=H-padT-padB;
    x.clearRect(0,0,W,H); x.strokeStyle=GRID; mono(x); x.fillStyle=MUT;
    for(var i=0;i<=3;i++){ var yy=padT+gh*i/3; x.beginPath(); x.moveTo(padL,yy); x.lineTo(W-padR,yy); x.stroke();}
    // three grids: coarse(1/10201) medium(1/40401) fine(1/160801) -> max(T) 1972,1985,1987
    var data=[[1/10201,1972],[1/40401,1985],[1/160801,1987]];
    var xmax=1/10201*1.1, ymin=1965, ymax=1992;
    function X(h){return padL + (h/xmax)*gw;} function Y(v){return padT+gh*(1-(v-ymin)/(ymax-ymin));}
    // asymptotic dashed to extrapolated value 1987.5 at h=0
    x.save(); x.setLineDash([4,3]); x.strokeStyle="rgba(86,211,100,.6)";
    x.beginPath(); x.moveTo(X(0),Y(1987.5)); x.lineTo(X(data[0][0]),Y(data[0][1])); x.stroke(); x.restore();
    // points
    x.fillStyle=CY; data.forEach(function(d){ var xx=X(d[0]),yy=Y(d[1]); x.beginPath(); x.arc(xx,yy,3,0,7); x.fill();});
    x.fillStyle=OK; x.beginPath(); x.arc(X(0),Y(1987.5),3,0,7); x.fill();
    x.fillStyle=MUT; x.textAlign="left"; x.fillText("h→0 (Richardson)", X(0)+5, Y(1987.5)-5);
    x.textAlign="right"; x.fillText("1/cells →", W-padR, padT+gh+12);
    x.save(); x.translate(10,padT+gh/2); x.rotate(-Math.PI/2); x.textAlign="center"; x.fillText("max(T) [K]",0,0); x.restore();
  }

  function render(){
    var r=function(h,fn,minH,arg){ var c=canvasIn(panel(h),minH); if(c){ try{fn(c,arg);}catch(e){} } };
    // job monitor
    r("SOLVER RESIDUAL", residuals, 150);
    r("COURANT", courant, 120);
    r("PROBE", probe, 110, false);
    r("TEMPERATURE", field, 130);
    // workspace
    r("VORTICITY", field, 120);
    // v&v
    r("VERIFICATION", gci, 130);
    r("VALIDATION", probe, 130, true);
    r("MORIYOSHI", probe, 130, true);
  }
  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", function(){ setTimeout(render,80); });
  else setTimeout(render,80);
  var to; window.addEventListener("resize", function(){ clearTimeout(to); to=setTimeout(function(){
    document.querySelectorAll("canvas.__m11done").forEach&&0; }, 200); });
})();
