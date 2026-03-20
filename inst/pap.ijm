// PAP %Area quantification using one common threshold per image
// ROI template order must be: TL, TM, TR, BL, BM, BR

// ---------- parse arguments ----------
arg = getArgument();
parts = split(arg, "\\*");

if (parts.length < 3) {
    exit("Expected arguments: inputDir*outputDir*roiZip");
}

inputDir = parts[0];
outDir   = parts[1];

if (parts.length >= 3 && parts[2] != "") {
    roiZip = parts[2];
} else {
    exit("ROI template not defined.");
}

// ensure trailing slash for directories
if (!endsWith(inputDir, "/"))
    inputDir = inputDir + "/";

if (!endsWith(outDir, "/"))
    outDir = outDir + "/";

// subfolders
qcDir   = outDir + "qc/";
maskDir = outDir + "mask/";
File.makeDirectory(outDir);
File.makeDirectory(qcDir);
File.makeDirectory(maskDir);

csvPath = outDir + "pap_area_results.csv";
File.saveString("image,well,roi_area,pos_area,percent_area\n", csvPath);

// ---------- helper ----------
function stripExtensions(s) {
    dot = lastIndexOf(s, ".");
    if (dot == -1) return s;
    return substring(s, 0, dot);
}

// ---------- tunable parameters ----------
measureRolling   = 450;
measureBlurSigma = 2;
measureMethod    = "Otsu";
saveQC           = true;

// ROI order must match the order inside pap2.zip
labels = newArray("TL","TM","TR","BL","BM","BR");

setBatchMode(false);
// ---------------------------------------

print("inputDir: " + inputDir);
print("outDir: " + outDir);
print("roiZip: " + roiZip);

if (!File.exists(roiZip)) {
    exit("ROI template not found: " + roiZip);
}

list = getFileList(inputDir);
total = 0;
for (i=0; i<list.length; i++) {
    name = list[i];
    if (endsWith(name, ".jpg") || endsWith(name, ".jpeg") ||
        endsWith(name, ".png") || endsWith(name, ".tif") || endsWith(name, ".tiff"))
        total++;
}
print("Total image files: " + total);

processed = 0;

for (i=0; i<list.length; i++) {
    name = list[i];

    if (!(endsWith(name, ".jpg") || endsWith(name, ".jpeg") ||
          endsWith(name, ".png") || endsWith(name, ".tif") || endsWith(name, ".tiff")))
        continue;

    processed++;
    print("Processing " + processed + "/" + total + ": " + name);
    showStatus("Processing " + processed + "/" + total + ": " + name);
    showProgress(processed, total);

    base = stripExtensions(name);

    roiManager("Reset");
    run("Clear Results");

    open(inputDir + name);
    origID = getImageID();
    origTitle = getTitle();

    // Load ROI template
    roiManager("Open", roiZip);
    nRoi = roiManager("count");
    if (nRoi != 6) {
        print("WARNING: ROI template does not contain 6 ROIs. Found: " + nRoi);
        selectImage(origID); close();
        roiManager("Reset");
        run("Clear Results");
        continue;
    }

    // --------------------------------------------------
    // Save QC overlay on original image
    // --------------------------------------------------
    if (saveQC) {
        selectImage(origID);
        run("Duplicate...", "title=__qc_tmp");
        qcID = getImageID();

        selectImage(qcID);
        roiManager("Show None");
        roiManager("Deselect");

        for (k=0; k<6; k++) {
            roiManager("Select", k);
            run("Draw");
        }

        saveAs("PNG", qcDir + base + "_qc.png");
        selectImage(qcID); close();
    }

    // --------------------------------------------------
    // Build ONE common mask for the whole image
    // --------------------------------------------------
    selectImage(origID);
    run("Duplicate...", "title=__mask_tmp");
    maskID = getImageID();

    selectImage(maskID);
    run("8-bit");
    run("Subtract Background...", "rolling=" + measureRolling);
    run("Gaussian Blur...", "sigma=" + measureBlurSigma);

    // IMPORTANT: one threshold for the whole image
    run("Auto Threshold", "method=" + measureMethod + " white");

    // force background black, positive white
    setOption("BlackBackground", true);
    run("Convert to Mask");

    // Save mask image for QC
    saveAs("PNG", maskDir + base + "_mask.png");

    // --------------------------------------------------
    // Measure all 6 wells on the same binary mask
    // --------------------------------------------------
    for (k=0; k<6; k++) {
        selectImage(maskID);
        roiManager("Select", k);

        // binary image: mean/255 = positive fraction
        getStatistics(roiArea, mean1, min1, max1, std1);

        pctArea = mean1 / 255 * 100;
        posArea = roiArea * mean1 / 255;

        line = base + "," + labels[k] + "," +
               d2s(roiArea, 3) + "," +
               d2s(posArea, 3) + "," +
               d2s(pctArea, 3) + "\n";

        File.append(line, csvPath);
    }

    // cleanup
    selectImage(maskID); close();
    selectImage(origID); close();

    roiManager("Reset");
    run("Clear Results");
}

print("Done.");
print("CSV saved to: " + csvPath);
print("QC images saved to: " + qcDir);
print("Mask images saved to: " + maskDir);
print("This batch will end after 5 seconds");
wait(5000);
run("Quit");