// PAP feature extraction per well: raw + CLAHE dual measurements
// ROI order must be: TL, TM, TR, BL, BM, BR
// This macro extracts grayscale features only.
// Blank subtraction / 128-well normalization should be done later in R.
//
// Output columns:
//   image, well, roi_area,
//   raw_mean, raw_median, raw_intden,
//   mean_gray, median_gray, sd_gray, min_gray, max_gray, intden_gray, cv_gray,
//   dark_frac_40, dark_frac_60, dark_frac_80
//
// raw_*   = pre-CLAHE absolute intensity (for 128-well / blank normalization in R)
// others  = post-CLAHE (for spatial texture / heterogeneity analysis)

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

if (!endsWith(inputDir, "/"))
    inputDir = inputDir + "/";
if (!endsWith(outDir, "/"))
    outDir = outDir + "/";

// ---------- output folders ----------
qcDir = outDir + "qc/";
File.makeDirectory(outDir);
File.makeDirectory(qcDir);

// ---------- output csv ----------
csvPath = outDir + "pap_feature_results.csv";
header = "image,well,roi_area,"
       + "raw_mean,raw_median,raw_intden,"
       + "mean_gray,median_gray,sd_gray,min_gray,max_gray,intden_gray,cv_gray,"
       + "dark_frac_40,dark_frac_60,dark_frac_80\n";
File.saveString(header, csvPath);

// ---------- settings ----------
labels = newArray("TL","TM","TR","BL","BM","BR");

// CLAHE settings
claheBlockSize = 127;
claheHistBins  = 256;
claheMaxSlope  = 3;

// QC overlay toggle
saveQC = true;

// ---------- batch mode ----------
// Fixed: unique titles per iteration prevent the alternating-failure bug.
// If issues reappear, set to false as fallback.
setBatchMode(true);

// ---------- helpers ----------
function stripExtensions(s) {
    dot = lastIndexOf(s, ".");
    if (dot == -1) return s;
    return substring(s, 0, dot);
}

// [FIX] Added imgIdx + wellIdx parameters for unique title in batch mode
function measureDarkFraction(threshValue, roiIndex, imgIdx, wellIdx) {
    tmpTitle = "__dark_" + imgIdx + "_" + wellIdx + "_" + threshValue;
    run("Duplicate...", "title=" + tmpTitle);
    darkID = getImageID();

    selectImage(darkID);
    setThreshold(0, threshValue);
    setOption("BlackBackground", true);
    run("Convert to Mask");

    roiManager("Select", roiIndex);
    getStatistics(area1, mean1, min1, max1, std1);
    frac = mean1 / 255 * 100;

    selectImage(darkID);
    close();
    wait(50);    // [FIX] give batch mode GC time
    return frac;
}

// ---------- count files ----------
list = getFileList(inputDir);
total = 0;
for (i = 0; i < list.length; i++) {
    name = list[i];
    if (endsWith(name, ".jpg") || endsWith(name, ".jpeg") ||
        endsWith(name, ".png") || endsWith(name, ".tif") || endsWith(name, ".tiff"))
        total++;
}

print("inputDir: " + inputDir);
print("outDir: " + outDir);
print("roiZip: " + roiZip);
print("Total image files: " + total);

if (!File.exists(roiZip)) {
    exit("ROI template not found: " + roiZip);
}

// ---------- main loop ----------
processed = 0;

for (i = 0; i < list.length; i++) {
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

    roiManager("Open", roiZip);
    nRoi = roiManager("count");
    if (nRoi != 6) {
        print("WARNING: ROI count != 6 (found " + nRoi + "), skipping: " + name);
        selectImage(origID); close();
        roiManager("Reset");
        run("Clear Results");
        continue;
    }

    // --------------------------------------------------
    // QC overlay on original image
    // --------------------------------------------------
    if (saveQC) {
        // [FIX] unique title per image
        qcTitle = "__qc_" + processed;
        selectImage(origID);
        run("Duplicate...", "title=" + qcTitle);
        qcID = getImageID();

        selectImage(qcID);
        roiManager("Show None");
        roiManager("Deselect");
        for (k = 0; k < 6; k++) {
            roiManager("Select", k);
            run("Draw");
        }
        saveAs("PNG", qcDir + base + "_qc.png");
        selectImage(qcID);
        close();
        wait(50);    // [FIX]
    }

    // --------------------------------------------------
    // Per-well feature extraction
    // --------------------------------------------------
    for (k = 0; k < 6; k++) {
        // [FIX] unique title per well per image
        wellTitle = "__well_" + processed + "_" + k;
        selectImage(origID);
        run("Duplicate...", "title=" + wellTitle);
        wellID = getImageID();

        selectImage(wellID);
        roiManager("Select", k);
        setBackgroundColor(0, 0, 0);
        run("Clear Outside");
        run("8-bit");

        // =============================================
        // PASS 1: raw measurements (pre-CLAHE)
        // For 128-well / blank-plate normalization in R
        // =============================================
        run("Set Measurements...", "area mean median integrated redirect=None decimal=3");
        roiManager("Select", k);
        run("Measure");

        raw_row     = nResults - 1;
        roi_area    = getResult("Area",    raw_row);
        raw_mean    = getResult("Mean",    raw_row);
        raw_median  = getResult("Median",  raw_row);
        raw_intden  = getResult("IntDen",  raw_row);

        // =============================================
        // CLAHE
        // =============================================
        run("Enhance Local Contrast (CLAHE)",
            "blocksize=" + claheBlockSize
            + " histogram=" + claheHistBins
            + " maximum=" + claheMaxSlope);

        // =============================================
        // PASS 2: post-CLAHE measurements
        // For texture / spatial heterogeneity analysis
        // =============================================
        run("Set Measurements...", "area mean median min max integrated standard redirect=None decimal=3");
        roiManager("Select", k);
        run("Measure");

        clahe_row   = nResults - 1;
        mean_gray   = getResult("Mean",   clahe_row);
        median_gray = getResult("Median", clahe_row);
        sd_gray     = getResult("StdDev", clahe_row);
        min_gray    = getResult("Min",    clahe_row);
        max_gray    = getResult("Max",    clahe_row);
        intden_gray = getResult("IntDen", clahe_row);

        if (mean_gray > 0)
            cv_gray = sd_gray / mean_gray;
        else
            cv_gray = 0;

        // =============================================
        // dark_frac at 3 thresholds (on CLAHE image)
        // =============================================
        dark_frac_40 = measureDarkFraction(40, k, processed, k);
        selectImage(wellID);

        dark_frac_60 = measureDarkFraction(60, k, processed, k);
        selectImage(wellID);

        dark_frac_80 = measureDarkFraction(80, k, processed, k);
        selectImage(wellID);

        // =============================================
        // Write CSV row
        // =============================================
        line = base + "," + labels[k] + ","
             + d2s(roi_area,    3) + ","
             + d2s(raw_mean,    3) + ","
             + d2s(raw_median,  3) + ","
             + d2s(raw_intden,  3) + ","
             + d2s(mean_gray,   3) + ","
             + d2s(median_gray, 3) + ","
             + d2s(sd_gray,     3) + ","
             + d2s(min_gray,    3) + ","
             + d2s(max_gray,    3) + ","
             + d2s(intden_gray, 3) + ","
             + d2s(cv_gray,     6) + ","
             + d2s(dark_frac_40, 3) + ","
             + d2s(dark_frac_60, 3) + ","
             + d2s(dark_frac_80, 3) + "\n";

        File.append(line, csvPath);

        selectImage(wellID);
        close();
        wait(50);    // [FIX]
    }

    selectImage(origID);
    close();
    wait(50);    // [FIX]

    roiManager("Reset");
    run("Clear Results");
}

print("Done.");
print("CSV saved to: " + csvPath);
print("QC images saved to: " + qcDir);
print("This batch will end after 5 seconds");
wait(5000);
run("Quit");
