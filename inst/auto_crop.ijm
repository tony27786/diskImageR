// Auto-crop round Petri dish from black background
// Stable GUI mode version for Fiji

inputDir = getDirectory("Choose input folder");
outDir   = inputDir + "cropped/";
File.makeDirectory(outDir);

function stripExtensions(s) {
    dot = lastIndexOf(s, ".");
    if (dot == -1) return s;
    return substring(s, 0, dot);
}

// ---- tunable parameters ----
rolling     = 300;
blurSigma   = 2;
pad         = 40;
thrMethod   = "Otsu";
minSize     = 50000;
minCirc     = 0.30;
maxCirc     = 1.00;
maxAreaFrac = 0.95;
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

// IMPORTANT: use GUI mode for stability
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

    run("Duplicate...", "title=__work");
    selectWindow("__work");
    Image.removeScale;
    run("8-bit");
    run("Subtract Background...", "rolling=" + rolling + " sliding");
    run("Gaussian Blur...", "sigma=" + blurSigma);

    run("Auto Threshold", "method=" + thrMethod + " white");
    run("Convert to Mask");
    run("Fill Holes");

    roiManager("Reset");
    run("Clear Results");
    run("Analyze Particles...", "size=" + minSize + "-Infinity circularity=" + minCirc + "-" + maxCirc + " show=Nothing clear clear add");

    if (roiManager("count") == 0) {
        print("No suitable dish ROI found: " + name + ", skipping...");
        close(); // __work
        selectWindow(origTitle); close();
        roiManager("Reset");
        run("Clear Results");
        processed++;
        continue;
    }

    run("Set Measurements...", "area redirect=None decimal=3");
    run("Clear Results");

    best = -1;
    bestArea = -1;

    for (r = 0; r < roiManager("count"); r++) {
        roiManager("Select", r);
        run("Measure");
        a = getResult("Area", nResults - 1);
        if (a > bestArea) {
            bestArea = a;
            best = r;
        }
    }

    if (best < 0) {
        print("Could not select best ROI: " + name + ", skipping...");
        selectWindow("__work"); close();
        selectWindow(origTitle); close();
        roiManager("Reset");
        run("Clear Results");
        processed++;
        continue;
    }

    roiManager("Select", best);
    getSelectionBounds(x, y, w, h);

    selectWindow("__work");
    imgArea = getWidth() * getHeight();

    if (bestArea > maxAreaFrac * imgArea) {
        print("Threshold likely failed (ROI too large) for " + name + ", skipping...");
        selectWindow("__work"); close();
        selectWindow(origTitle); close();
        roiManager("Reset");
        run("Clear Results");
        processed++;
        continue;
    }

    selectWindow(origTitle);
    x2 = maxOf(0, x - pad);
    y2 = maxOf(0, y - pad);
    w2 = minOf(getWidth()  - x2, w + 2 * pad);
    h2 = minOf(getHeight() - y2, h + 2 * pad);

    makeRectangle(x2, y2, w2, h2);
    run("Crop");

    base = stripExtensions(name);
    saveAs("PNG", outDir + base + "_crop.png");

    close(); // cropped original
    selectWindow("__work"); close();

    roiManager("Reset");
    run("Clear Results");

    processed++;
}

print("Done. Cropped images saved to: " + outDir);