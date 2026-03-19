// Auto-crop 6-well plate from black background
// Uses auto_crop.ijm-style automation, but keeps 6-well plate detection logic

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

// ---- tunable parameters ----
rolling     = 450;
blurSigma   = 3;
pad         = 30;
thrMethod   = "Otsu";
minSize     = 5000;
maxAreaFrac = 0.90;
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

    workTitle = "__work_" + i;
    run("Duplicate...", "title=" + workTitle);
    selectWindow(workTitle);
    Image.removeScale;
    run("8-bit");
    run("Subtract Background...", "rolling=" + rolling + " sliding");
    run("Gaussian Blur...", "sigma=" + blurSigma);

    run("Auto Threshold", "method=" + thrMethod + " white");
    run("Convert to Mask");
    run("Fill Holes");

    // Keep the 6-well plate detection logic:
    // detect large bright object without circularity restriction
    roiManager("Reset");
    run("Clear Results");
    run("Analyze Particles...", "size=" + minSize + "-Infinity pixel show=Nothing clear clear add");

    if (roiManager("count") == 0) {
        print("Nothing found in " + name + ", skipping...");
        close(); // work
        selectWindow(origTitle); close();
        roiManager("Reset");
        run("Clear Results");
        processed++;
        setBatchMode(false);
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
        selectWindow(workTitle); close();
        selectWindow(origTitle); close();
        roiManager("Reset");
        run("Clear Results");
        processed++;
        setBatchMode(false);
        continue;
    }

    roiManager("Select", best);
    getSelectionBounds(x, y, w, h);

    selectWindow(workTitle);
    imgArea = getWidth() * getHeight();

    if (bestArea > maxAreaFrac * imgArea) {
        print("Threshold likely failed (ROI too large) for " + name + ", skipping...");
        selectWindow(workTitle); close();
        selectWindow(origTitle); close();
        roiManager("Reset");
        run("Clear Results");
        processed++;
        setBatchMode(false);
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
    selectWindow(workTitle); close();

    roiManager("Reset");
    run("Clear Results");

    processed++;
}

print("Done. Cropped images saved to: " + outDir);
print("This batch will end after 5 seconds");
wait(5000);
run("Quit");
