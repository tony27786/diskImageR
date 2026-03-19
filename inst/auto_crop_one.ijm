// Auto-crop one Petri dish image from black background
// Arguments: inputFile*outputFile

args = split(getArgument(), "*");
if (args.length < 2) {
    exit("Invalid arguments. Expected format: inputFile*outputFile");
}

inputFile  = args[0];
outputFile = args[1];

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

roiManager("Reset");
run("Clear Results");

open(inputFile);
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
    print("FAILED: No suitable dish ROI found");
    close(); // __work
    selectWindow(origTitle); close();
    exit();
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
    print("FAILED: Could not select best ROI");
    selectWindow("__work"); close();
    selectWindow(origTitle); close();
    exit();
}

roiManager("Select", best);
getSelectionBounds(x, y, w, h);

selectWindow("__work");
imgArea = getWidth() * getHeight();

if (bestArea > maxAreaFrac * imgArea) {
    print("FAILED: ROI too large, threshold likely failed");
    selectWindow("__work"); close();
    selectWindow(origTitle); close();
    exit();
}

selectWindow(origTitle);
x2 = maxOf(0, x - pad);
y2 = maxOf(0, y - pad);
w2 = minOf(getWidth()  - x2, w + 2 * pad);
h2 = minOf(getHeight() - y2, h + 2 * pad);

makeRectangle(x2, y2, w2, h2);
run("Crop");

saveAs("PNG", outputFile);

close(); // cropped original
selectWindow("__work"); close();

roiManager("Reset");
run("Clear Results");

print("SAVED: " + outputFile);