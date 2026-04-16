// Auto-crop 6-well plate from black background
// Strategy: rotate the image upright first, then apply the original bbox+pad crop.
// Tilt is detected via fit-ellipse angle on the initial mask.

args = split(getArgument(), "*");
if (args.length < 2) {
    exit("Invalid arguments. Expected format: inputDir*outputDir");
}

inputDir = args[0];
outDir   = args[1];

if (!endsWith(inputDir, File.separator)) inputDir = inputDir + File.separator;
if (!endsWith(outDir, File.separator)) outDir = outDir + File.separator;

File.makeDirectory(outDir);

function stripExtensions(s) {
    dot = lastIndexOf(s, ".");
    if (dot == -1) return s;
    return substring(s, 0, dot);
}

// Pick the largest ROI in the ROI Manager; return its index, or -1 if empty.
function pickLargestROI() {
    run("Set Measurements...", "area redirect=None decimal=3");
    run("Clear Results");
    bestIdx = -1;
    bestA   = -1;
    n = roiManager("count");
    for (r = 0; r < n; r++) {
        roiManager("Select", r);
        run("Measure");
        a = getResult("Area", nResults - 1);
        if (a > bestA) {
            bestA = a;
            bestIdx = r;
        }
    }
    return bestIdx;
}

// ---- tunable parameters ----
rolling     = 450;
blurSigma   = 3;
pad         = 30;
thrMethod   = "Otsu";
minSize     = 5000;
maxAreaFrac = 0.90;
rotateThreshDeg = 0.6;   // skip rotation if tilt is smaller than this
// ----------------------------

list = getFileList(inputDir);
processed = 0;
total = 0;

for (i = 0; i < list.length; i++) {
    name = list[i];
    if (endsWith(name, ".tif") || endsWith(name, ".tiff") ||
        endsWith(name, ".png") || endsWith(name, ".jpg") || endsWith(name, ".jpeg")) {
        total++;
    }
}
print("Total image files: " + total);
setBatchMode(false);

for (i = 0; i < list.length; i++) {
    name = list[i];

    if (!(endsWith(name, ".jpg") || endsWith(name, ".jpeg") ||
          endsWith(name, ".png") || endsWith(name, ".tif") || endsWith(name, ".tiff")))
        continue;

    print("Cropping " + (processed + 1) + "/" + total + ": " + name);
    showStatus("Cropping " + (processed + 1) + "/" + total + ": " + name);
    showProgress(processed + 1, total);

    roiManager("Reset");
    run("Clear Results");

    open(inputDir + name);
    origTitle = getTitle();
    origID = getImageID();

    workTitle = "__work_" + i;
    run("Duplicate...", "title=" + workTitle);
    workID = getImageID();
    selectImage(workID);
    Image.removeScale;
    run("8-bit");
    run("Subtract Background...", "rolling=" + rolling + " sliding");
    run("Gaussian Blur...", "sigma=" + blurSigma);

    run("Auto Threshold", "method=" + thrMethod + " white");
    run("Convert to Mask");
    run("Fill Holes");

    // ==========================================================
    // Step 1: initial detection to measure tilt
    // ==========================================================
    roiManager("Reset");
    run("Clear Results");
    run("Analyze Particles...", "size=" + minSize + "-Infinity pixel show=Nothing clear clear add");

    if (roiManager("count") == 0) {
        print("Nothing found in " + name + ", skipping...");
        selectImage(workID); close(); wait(50);
        selectWindow(origTitle); close(); wait(50);
        roiManager("Reset");
        run("Clear Results");
        processed++;
        continue;
    }

    best = pickLargestROI();
    if (best < 0) {
        print("Could not select best ROI: " + name + ", skipping...");
        selectImage(workID); close(); wait(50);
        selectWindow(origTitle); close(); wait(50);
        roiManager("Reset");
        run("Clear Results");
        processed++;
        continue;
    }

    // ==========================================================
    // Step 2: rotate original + mask upfront if tilted
    // ==========================================================
    run("Set Measurements...", "area fit redirect=None decimal=3");
    run("Clear Results");
    roiManager("Select", best);
    run("Measure");
    angle = getResult("Angle", 0);

    // Fit-ellipse angle range 0..180 -> minimal rotation in [-90, 90]
    if (angle > 90) {
        rotDeg = angle - 180;
    } else {
        rotDeg = angle;
    }

    if (abs(rotDeg) >= rotateThreshDeg) {
        print("  Board tilt = " + d2s(angle, 2) + " deg, counter-rotating by " + d2s(rotDeg, 2) + " deg");

        selectWindow(origTitle);
        run("Rotate... ", "angle=" + rotDeg + " grid=1 interpolation=Bilinear enlarge");

        selectImage(workID);
        run("Rotate... ", "angle=" + rotDeg + " grid=1 interpolation=None enlarge");

        // Re-detect board ROI on the rotated mask (coordinates have changed)
        roiManager("Reset");
        run("Clear Results");
        run("Analyze Particles...", "size=" + minSize + "-Infinity pixel show=Nothing clear clear add");

        if (roiManager("count") == 0) {
            print("Re-detection failed after rotation: " + name + ", skipping...");
            selectImage(workID); close(); wait(50);
            selectWindow(origTitle); close(); wait(50);
            roiManager("Reset");
            run("Clear Results");
            processed++;
            continue;
        }

        best = pickLargestROI();
        if (best < 0) {
            print("No ROI after rotation re-detection: " + name + ", skipping...");
            selectImage(workID); close(); wait(50);
            selectWindow(origTitle); close(); wait(50);
            roiManager("Reset");
            run("Clear Results");
            processed++;
            continue;
        }
    } else {
        print("  Board tilt = " + d2s(angle, 2) + " deg, no rotation needed");
    }
    // Pad canvas so bbox + pad never clips
    selectWindow(origTitle);
    curW = getWidth();
    curH = getHeight();
    run("Canvas Size...", "width=" + (curW + 2*pad) + " height=" + (curH + 2*pad) + " position=Center zero");

    selectImage(workID);
    run("Canvas Size...", "width=" + (curW + 2*pad) + " height=" + (curH + 2*pad) + " position=Center zero");

    // Re-detect on padded mask (board coords shifted by +pad, +pad)
    roiManager("Reset");
    run("Clear Results");
    run("Analyze Particles...", "size=" + minSize + "-Infinity pixel show=Nothing clear clear add");
    if (roiManager("count") == 0) {
        print("ROI lost after canvas pad: " + name + ", skipping...");
        selectImage(workID); close(); wait(50);
        selectWindow(origTitle); close(); wait(50);
        roiManager("Reset"); run("Clear Results");
        processed++;
        continue;
    }
    best = pickLargestROI();

    // ==========================================================
    // Step 3: sanity check on ROI size
    // ==========================================================
    selectImage(workID);
    imgArea = getWidth() * getHeight();
    roiManager("Select", best);
    run("Set Measurements...", "area redirect=None decimal=3");
    run("Clear Results");
    run("Measure");
    bestArea = getResult("Area", 0);
    if (bestArea > maxAreaFrac * imgArea) {
        print("Threshold likely failed (ROI too large) for " + name + ", skipping...");
        selectImage(workID); close(); wait(50);
        selectWindow(origTitle); close(); wait(50);
        roiManager("Reset");
        run("Clear Results");
        processed++;
        continue;
    }

    // ==========================================================
    // Step 4: original bbox + pad crop logic (unchanged)
    // ==========================================================
    roiManager("Select", best);
    getSelectionBounds(x, y, w, h);

    selectWindow(origTitle);
    x2 = maxOf(0, x - pad);
    y2 = maxOf(0, y - pad);
    w2 = minOf(getWidth()  - x2, w + 2 * pad);
    h2 = minOf(getHeight() - y2, h + 2 * pad);

    makeRectangle(x2, y2, w2, h2);
    run("Crop");

    // Defensive: make sure we're saving the ORIGINAL, not the mask
    selectWindow(origTitle);
    if (bitDepth() == 8 && is("binary")) {
        print("ERROR: About to save binary mask as crop for " + name + " - skipping save.");
        selectImage(workID); close(); wait(50);
        selectWindow(origTitle); close(); wait(50);
        roiManager("Reset");
        run("Clear Results");
        processed++;
        continue;
    }

    base = stripExtensions(name);
    saveAs("PNG", outDir + base + "_crop.png");

    // saveAs renames the active window; close by current-activity
    close(); wait(50);
    selectImage(workID); close(); wait(50);

    roiManager("Reset");
    run("Clear Results");

    processed++;
}

print("Done. Cropped images saved to: " + outDir);
print("This batch will end after 5 seconds");
wait(5000);
run("Quit");
