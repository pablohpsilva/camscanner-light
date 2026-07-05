#!/usr/bin/env python3
"""Host reference for the dual-polarity Otsu segmentation dot detector.

Mirrors _runPipeline in lib/features/scan/opencv_edge_detector.dart. libdartcv
can't run under host `flutter test`, so this cv2 replica is the fast host check
of the algorithm + constants. Run: `python3 apps/mobile/tool/detect_probe.py`.
Requires: pip install --break-system-packages opencv-python-headless numpy
"""
import sys
import cv2
import numpy as np

DETECT_MAX_SIDE = 1024
SEG_BLUR = 7
SEG_KERNEL_DIVISOR = 30
MIN_AREA_FRAC, MAX_AREA_FRAC, MIN_FILL = 0.05, 0.92, 0.55


def _quad_area(q):
    x, y = q[:, 0], q[:, 1]
    return abs(sum(x[i] * y[(i + 1) % 4] - x[(i + 1) % 4] * y[i]
                   for i in range(4))) / 2


def _sort_roles(q):
    """[TL, TR, BR, BL] — mirrors sortCornerRoles in detector_geometry.dart."""
    q = np.asarray(q, dtype=float).reshape(-1, 2)
    s = q[:, 0] + q[:, 1]
    d = q[:, 1] - q[:, 0]
    return np.array([q[np.argmin(s)], q[np.argmin(d)],
                     q[np.argmax(s)], q[np.argmax(d)]])


def _fill_mask(poly, shape):
    m = np.zeros(shape[:2], dtype=np.uint8)
    cv2.fillPoly(m, [np.asarray(poly, dtype=np.int32).reshape(-1, 2)], 255)
    return m


def _iou(det, truth, shape):
    md, mt = _fill_mask(det, shape), _fill_mask(truth, shape)
    inter = int(np.count_nonzero((md > 0) & (mt > 0)))
    union = int(np.count_nonzero((md > 0) | (mt > 0)))
    return inter / union if union else 0.0


def _corner_err_frac(det, truth, diag):
    """Mean per-corner Euclidean error as a fraction of the image diagonal."""
    d, t = _sort_roles(det), _sort_roles(truth)
    return float(np.mean(np.linalg.norm(d - t, axis=1))) / diag


def detect(img, max_side=DETECT_MAX_SIDE):
    """Return (confidence, areaFrac, fill, polarity, quad) or None."""
    h0, w0 = img.shape[:2]
    longest = max(h0, w0)
    if longest > max_side:
        s = max_side / longest
        img = cv2.resize(img, (round(w0 * s), round(h0 * s)),
                         interpolation=cv2.INTER_AREA)
    rows, cols = img.shape[:2]
    area = rows * cols
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (SEG_BLUR, SEG_BLUR), 0)
    ot, mb = cv2.threshold(blurred, 0, 255,
                           cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    _, md = cv2.threshold(blurred, ot, 255, cv2.THRESH_BINARY_INV)
    kseg = max(3, round(cols / SEG_KERNEL_DIVISOR))
    if kseg % 2 == 0:
        kseg += 1
    ker = cv2.getStructuringElement(cv2.MORPH_RECT, (kseg, kseg))
    best = None
    for name, mask in (("bright", mb), ("dark", md)):
        closed = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, ker)
        cnts, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL,
                                   cv2.CHAIN_APPROX_SIMPLE)
        cnts = [c for c in cnts if cv2.contourArea(c) >= area * 0.05]
        if not cnts:
            continue
        c = max(cnts, key=cv2.contourArea)
        carea = cv2.contourArea(c)
        peri = cv2.arcLength(c, True)
        ap = cv2.approxPolyDP(c, 0.02 * peri, True)
        if len(ap) == 4 and cv2.isContourConvex(ap):
            quad = ap.reshape(-1, 2).astype(float)
        else:
            quad = cv2.boxPoints(cv2.minAreaRect(c)).astype(float)
        qarea = _quad_area(quad)
        if qarea <= 0:
            continue
        area_frac = qarea / area
        fill = min(carea / qarea, 1.0)
        if not (MIN_AREA_FRAC <= area_frac <= MAX_AREA_FRAC and fill >= MIN_FILL):
            continue
        # NOTE: the Dart pipeline computes the angle term via angleScore(); here
        # it is approximated as 1.0 (rects/near-rects → ~1.0), so the reported
        # confidence for non-rect shapes is a slight over-estimate. This probe
        # validates polarity selection, the guards, and null/non-null outcomes
        # — not the exact angle contribution.
        conf = 0.5 * min(area_frac, 1.0) + 0.3 * 1.0 + 0.2 * fill
        if best is None or conf > best[0]:
            best = (conf, area_frac, fill, name, quad)
    return best


# True page rectangle shared by every known-page fixture (800x600 image, no
# downscale at max_side=1024). Corners: TL, TR, BR, BL.
PAGE_RECT = np.array([[150, 110], [650, 110], [650, 490], [150, 490]], float)


def _page_on(bg, page):
    img = np.full((600, 800, 3), bg, np.uint8)
    cv2.rectangle(img, (150, 110), (650, 490), (page, page, page), -1)
    return img


def _page_nub(bg, page):
    """Page + bright nubs straddling the border — simulates text/close-bridge
    bleed that pushes approxPolyDP off 4 points, so the pre-fix fitter falls
    back to a loose minAreaRect that swallows the nubs."""
    img = np.full((600, 800, 3), bg, np.uint8)
    cv2.rectangle(img, (150, 110), (650, 490), (page, page, page), -1)
    cv2.rectangle(img, (300, 82), (360, 130), (page, page, page), -1)   # top nub: +28px
    cv2.rectangle(img, (642, 250), (692, 310), (page, page, page), -1)  # right nub: +42px
    return img


def _shape(kind):
    """White shape on black — mirrors the opencv_edge_detector_test fixtures."""
    import math
    img = np.zeros((480, 640, 3), np.uint8)
    if kind == "circle":
        cv2.circle(img, (320, 240), 160, (255, 255, 255), -1)
    elif kind == "triangle":
        cv2.fillPoly(img, [np.array([[320, 80], [120, 400], [520, 400]])],
                     (255, 255, 255))
    elif kind == "pentagon":
        c, r = (320, 240), 170
        p = np.array([[c[0] + r * math.cos(2 * math.pi * i / 5 - math.pi / 2),
                       c[1] + r * math.sin(2 * math.pi * i / 5 - math.pi / 2)]
                      for i in range(5)], np.int32)
        cv2.fillPoly(img, [p], (255, 255, 255))
    elif kind == "concave":
        cv2.fillPoly(img, [np.array([[320, 100], [500, 400], [320, 300],
                                     [140, 400]], np.int32)], (255, 255, 255))
    return img


def _cases():
    blank = np.full((600, 800, 3), 200, np.uint8)
    noise = np.random.RandomState(1).randint(100, 130, (600, 800, 3), np.uint8)
    clutter = np.full((600, 800, 3), 50, np.uint8)
    rs = np.random.RandomState(2)
    for _ in range(40):
        x, y = rs.randint(0, 700), rs.randint(0, 500)
        cv2.rectangle(clutter, (x, y),
                      (x + rs.randint(10, 60), y + rs.randint(10, 60)),
                      (int(rs.randint(0, 255)),) * 3, -1)
    # page brighter than desk, with a soft horizontal shadow across the page
    shadow = np.full((600, 800, 3), 55, np.uint8)
    for x in range(150, 651):
        v = int(235 - 85 * (x - 150) / 500)
        cv2.line(shadow, (x, 110), (x, 490), (v, v, v), 1)
    return [
        ("blank", blank, None),
        ("noise", noise, None),
        ("clutter", clutter, None),
        ("page-on-dark", _page_on(55, 225), "bright"),
        ("page-on-light", _page_on(235, 180), "dark"),
        ("soft-shadow-on-dark", shadow, "bright"),
        # Shape fixtures mirror opencv_edge_detector_test: a shape whose fill is
        # below 0.55 is rejected (triangle, concave dart); circle/pentagon pass.
        ("shape-circle", _shape("circle"), "bright"),
        ("shape-pentagon", _shape("pentagon"), "bright"),
        ("shape-triangle", _shape("triangle"), None),
        ("shape-concave", _shape("concave"), None),
        ("page-nub-on-dark", _page_nub(55, 225), "bright"),
    ]


def main():
    failures = 0
    for name, img, expect_polarity in _cases():
        r = detect(img)
        if expect_polarity is None:
            ok = r is None
            got = "NULL" if r is None else f"quad({r[3]} conf={r[0]:.2f})"
        else:
            ok = r is not None and r[3] == expect_polarity and 0.30 <= r[0] <= 1.0
            got = "NULL" if r is None else f"{r[3]} conf={r[0]:.2f} area={r[1]*100:.0f}% fill={r[2]:.2f}"
        print(f"[{'PASS' if ok else 'FAIL'}] {name:22s} expect={expect_polarity or 'NULL'} got={got}")
        if not ok:
            failures += 1
        # Tightness gate: for known-page fixtures, the detected quad must hug
        # the true page rectangle. diag of the 800x600 working image = 1000.
        TIGHT = {"page-on-dark", "page-on-light", "soft-shadow-on-dark",
                 "page-nub-on-dark"}
        T_IOU, T_ERR = 0.95, 0.015  # IoU floor, corner-error ceiling (frac diag)
        if name in TIGHT and r is not None:
            quad = r[4]
            iou = _iou(quad, PAGE_RECT, img.shape)
            err = _corner_err_frac(quad, PAGE_RECT, 1000.0)
            tight_ok = iou >= T_IOU and err <= T_ERR
            print(f"[{'PASS' if tight_ok else 'FAIL'}] {name:22s} "
                  f"tightness IoU={iou:.3f} (>= {T_IOU}) "
                  f"cornerErr={err*100:.2f}% (<= {T_ERR*100:.1f}%)")
            if not tight_ok:
                failures += 1
        r400 = detect(img, max_side=400)
        coarse_ok = (r is None) == (r400 is None) and (
            r is None or r[3] == r400[3])
        if not coarse_ok:
            print(f"[FAIL] {name:22s} 400px parity: "
                  f"1024={'NULL' if r is None else r[3]} "
                  f"400={'NULL' if r400 is None else r400[3]}")
            failures += 1
    print(f"\n{failures} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
