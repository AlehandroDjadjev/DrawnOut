(function () {
  function ensureOdd(k) {
    k = Math.max(1, Math.floor(k));
    return (k % 2 === 1) ? k : k + 1;
  }

  function resamplePolyline(points, spacing) {
    if (!points || points.length === 0) return [];
    const out = [];
    let prev = { x: points[0].x, y: points[0].y };
    out.push(prev);
    let acc = 0.0;
    for (let i = 1; i < points.length; i++) {
      const cur = points[i];
      const dx = cur.x - prev.x;
      const dy = cur.y - prev.y;
      const seg = Math.hypot(dx, dy);
      if (seg < 1e-6) continue;
      const dirx = dx / seg;
      const diry = dy / seg;
      let remain = seg;
      while (acc + remain >= spacing) {
        const t = (spacing - acc);
        prev = { x: prev.x + dirx * t, y: prev.y + diry * t };
        out.push(prev);
        remain -= t;
        acc = 0.0;
      }
      acc += remain;
      prev = { x: cur.x, y: cur.y };
    }
    const last = out[out.length - 1];
    if (Math.hypot(last.x - prev.x, last.y - prev.y) > 1e-3) out.push(prev);
    return out;
  }

  function matToPoints(mat) {
    // contour mat: Nx1x2 int points
    const data = mat.data32S;
    const pts = [];
    for (let i = 0; i < data.length; i += 2) {
      pts.push({ x: data[i], y: data[i + 1] });
    }
    return pts;
  }

  async function waitForCVReady(timeoutMs = 15000) {
    if (typeof cv === 'undefined') throw new Error('OpenCV.js not loaded');
    if (cv.Mat) return;
    await new Promise((resolve, reject) => {
      const start = Date.now();
      const check = setInterval(() => {
        if (cv && cv.Mat) { clearInterval(check); resolve(); }
        else if (Date.now() - start > timeoutMs) { clearInterval(check); reject(new Error('OpenCV.js init timeout')); }
      }, 25);
    });
  }

  async function vectorizeContours(imageData, opts) {
    await waitForCVReady();

    const blurK = ensureOdd(opts.blurK || 5);
    const edgeMode = opts.edgeMode || 'Canny';
    const cannyLo = opts.cannyLo ?? 50;
    const cannyHi = opts.cannyHi ?? 160;
    const dogSigma = opts.dogSigma ?? 1.2;
    const dogK = opts.dogK ?? 1.6;
    const dogThresh = opts.dogThresh ?? 6.0;
    const epsilon = opts.epsilon ?? 1.11875;
    const resampleSpacing = opts.resampleSpacing ?? 1.4107142857;
    const minPerimeter = opts.minPerimeter ?? 19.8392857143;
    const retrExternalOnly = opts.retrExternalOnly !== false;

    const src = cv.matFromImageData(imageData); // RGBA
    const gray = new cv.Mat();
    cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY);

    const blur = new cv.Mat();
    const ksize = new cv.Size(blurK, blurK);
    cv.GaussianBlur(gray, blur, ksize, 0, 0, cv.BORDER_DEFAULT);

    let edge = new cv.Mat();
    if (edgeMode === 'DoG') {
      const g1 = new cv.Mat();
      const g2 = new cv.Mat();
      cv.GaussianBlur(gray, g1, new cv.Size(0, 0), dogSigma, 0, cv.BORDER_DEFAULT);
      cv.GaussianBlur(gray, g2, new cv.Size(0, 0), dogSigma * dogK, 0, cv.BORDER_DEFAULT);
      const diff = new cv.Mat();
      cv.subtract(g1, g2, diff);
      const absd = new cv.Mat();
      cv.convertScaleAbs(diff, absd);
      cv.threshold(absd, edge, dogThresh, 255, cv.THRESH_BINARY);
      g1.delete(); g2.delete(); diff.delete(); absd.delete();
    } else {
      cv.Canny(blur, edge, cannyLo, cannyHi, 3, false);
    }

    const contours = new cv.MatVector();
    const hierarchy = new cv.Mat();
    const mode = retrExternalOnly ? cv.RETR_EXTERNAL : cv.RETR_LIST;
    cv.findContours(edge, contours, hierarchy, mode, cv.CHAIN_APPROX_NONE);

    const polylines = [];
    for (let i = 0; i < contours.size(); i++) {
      const cnt = contours.get(i);
      const peri = cv.arcLength(cnt, false);
      if (peri < minPerimeter) { cnt.delete(); continue; }

      const approx = new cv.Mat();
      cv.approxPolyDP(cnt, approx, epsilon, false);
      const pts = resamplePolyline(matToPoints(approx), resampleSpacing);
      if (pts.length >= 2) {
        polylines.push(pts.map(p => [p.x, p.y]));
      }
      approx.delete();
      cnt.delete();
    }

    // Cleanup
    src.delete(); gray.delete(); blur.delete(); edge.delete(); contours.delete(); hierarchy.delete();
    return { width: imageData.width, height: imageData.height, polylines };
  }

  // Expose as a Promise-returning function
  window.cvVectorizeContours = vectorizeContours;
})();
