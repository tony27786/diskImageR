function alterImageSize(file) {
	selectWindow(file);
	picWidth = getWidth();
	picHeight = getHeight();
	run("Size...", "width=1000 constrain interpolation=None");
}

function makeLineE(centerX, centerY, length, angle) {
	angle = -angle * PI / 180;
	dX = cos(angle) * length;
	dY = sin(angle) * length;
	makeLine(centerX, centerY, centerX + dX, centerY + dY);
}

function findDisk(file){
	run("Clear Results");
	selectWindow(getTitle);
	run("Revert");
	alterImageSize(getTitle);
	run("8-bit");
	setThreshold(181, 255);
	run("Convert to Mask");
	roiManager("reset");
	roiManager("Show All with labels");
	roiManager("Show All");
	run("Analyze Particles...", "size=2500-4500 circularity=0.50-1.00 show=Outlines display exclude add");

	if (nResults == 0){
		print("Trying parameter set 2");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(150, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2500-4500 circularity=0.50-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 3");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(81, 255);
		run("Convert to Mask");
		run("Analyze Particles...", "size=2500-4500 circularity=0.50-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 4");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(200, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2500-4500 circularity=0.50-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 5");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(216, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2500-4500 circularity=0.50-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with less stringent circularity");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(181, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2000-5000 circularity=0.2-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with less stringent circularity, parameter set 2");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(150, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2000-4000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with less stringent circularity, parameter set 3");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(81, 255);
		run("Convert to Mask");
		run("Analyze Particles...", "size=2000-4000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with less stringent circularity, parameter set 4");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(200, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2000-4000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with different thresholding, parameter set 1");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(125, 162);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2000-4000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with different thresholding, parameter set 2");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(113, 134);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2000-50000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with different thresholding, parameter set 3");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(113, 173);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=2000-4000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying with different thresholding, parameter set 4b");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(97, 129);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=10000-50000 circularity=0.20-1.00 show=Outlines display exclude add");
	}

	if (nResults == 0){
		print("FAILED: Disk not identified");
		return(false);
	}
	if (nResults > 1){
		print("FAILED: More than one disk identified");
		return(false);
	}
	return(true);
}

function findDiskLarge(file){
	run("Clear Results");
	print("Trying large disk parameter set 1");
	selectWindow(getTitle);
	run("Revert");
	alterImageSize(getTitle);
	run("8-bit");
	setThreshold(181, 255);
	run("Convert to Mask");
	roiManager("reset");
	roiManager("Show All with labels");
	roiManager("Show All");
	run("Analyze Particles...", "size=6000-20000 circularity=0.20-1.00 show=Outlines display exclude add");

	if (nResults == 0){
		print("Trying parameter set 2");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(97, 129);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=8000-20000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 3");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(97, 150);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=8000-20000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 4");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(97, 200);
		run("Convert to Mask");
		run("Analyze Particles...", "size=10000-20000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 5");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(97, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=10000-20000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 6");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(255, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=8000-20000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 7");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(150, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=8000-20000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 8");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(200, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=4000-25000 circularity=0.20-1.00 show=Outlines display exclude add");
	}
	if (nResults == 0){
		print("Trying parameter set 9");
		close();
		selectWindow(getTitle);
		run("Revert");
		alterImageSize(getTitle);
		run("8-bit");
		setThreshold(243, 255);
		run("Convert to Mask");
		roiManager("reset");
		roiManager("Show All with labels");
		roiManager("Show All");
		run("Analyze Particles...", "size=4000-25000 circularity=0.20-1.00 show=Outlines display exclude add");
	}

	if (nResults == 0){
		print("FAILED: Disk not identified");
		return(false);
	}
	if (nResults > 1){
		print("FAILED: More than one disk identified");
		return(false);
	}
	return(true);
}

// Actual workflow starts here:
print("Starting imageJ macro");
parts = split(getArgument(), "*");

if (parts.length < 3) {
	exit("Invalid macro arguments. Expected format: inputDir*outputDir*diskDiameter");
}

dir1 = parts[0];
dir2 = parts[1];
knownDiam = parts[2];

print("Input directory: " + dir1);
print("Output directory: " + dir2);
print("Disk diameter: " + knownDiam);

diam10 = 10 / knownDiam;
list = getFileList(dir1);
print("Number of images: " + list.length);

failedList = "";
successCount = 0;
failedCount = 0;

setBatchMode(true);

// Append the appropriate file system separator, if required
if (!endsWith(dir1, File.separator)) {
	dir1 = dir1 + File.separator;
}
if (!endsWith(dir2, File.separator)) {
	dir2 = dir2 + File.separator;
}
outputFolder = dir2;

for (i = 0; i < list.length; i++) {
	showProgress(i + 1, list.length);

	// skip subfolders and hidden files
	if (File.isDirectory(dir1 + list[i])) {
		print("Skipping directory: " + list[i]);
		continue;
	}
	if (startsWith(list[i], ".")) {
		print("Skipping hidden file: " + list[i]);
		continue;
	}

	open(dir1 + list[i]);
	print("Current image: " + list[i]);

	filename = File.nameWithoutExtension;
	name = getTitle();

	run("Set Measurements...", "area mean centroid center perimeter redirect=None decimal=0");
	run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");

	ok = false;

	if (diam10 > 1.25) {
		print("small disk");
		ok = findDisk(getTitle());
	}
	if (diam10 <= 1.25) {
		print("Large disk");
		ok = findDiskLarge(getTitle());
	}

	if (ok) {
		close();
		run("Revert");
		alterImageSize(getTitle());

		centerX = getResult("X", 0);
		centerY = getResult("Y", 0);
		discDiam = 2 * sqrt(getResult("Area") / 3.1412);
		convert = discDiam / knownDiam;

		makePoint(centerX, centerY);
		run("Clear Results");

		setMinAndMax(50, 250);
		makeLineE(centerX, centerY, 40 * convert, 5);

		Angle = 0;
		while (Angle < 360) {
			Angle = Angle + 5;
			makeLineE(centerX, centerY, 40 * convert, Angle);

			profile = getProfile();
			for (j = 0; j < profile.length; j++) {
				k = nResults;
				setResult("X", k, j);
				setResult("Value", k, profile[j]);
			}
			updateResults();

			Plot.create("Profile", "X", "Value", profile);
		}

		saveAs("Results", outputFolder + filename + ".txt");
		close();

		successCount = successCount + 1;
		print("SUCCESS: " + list[i]);
	} else {
		failedList = failedList + list[i] + "\n";
		failedCount = failedCount + 1;

		print("Skipping file due to disk detection failure: " + list[i]);

		run("Clear Results");
		roiManager("reset");
		close("*");
	}
}

setBatchMode(false);

print("===== Processing finished =====");
print("Successful files: " + successCount);
print("Failed files: " + failedCount);
print("===== Failed file list =====");
print(failedList);