# diskImageR (fork)

> **Fork notice.** This repository is a fork of [acgerstein/diskImageR](https://github.com/acgerstein/diskImageR). It fixes several launcher and path issues and adds a Fiji-based workflow for six-well population analysis profile (PAP) plates. It is community-maintained and is **not** an official upstream release. If you use the disk diffusion methods, please cite the original package (see [Citation](#citation)).

`diskImageR` is an R package that quantifies microbial growth from photographs of agar plates. Fiji/ImageJ macros bundled with the package extract pixel-intensity measurements, and R functions turn them into summary tables and figures.

This fork contains two independent workflows:

| Workflow | Input | Main functions | Main output |
| --- | --- | --- | --- |
| **A. Six-well PAP** (added in this fork) | Photographs of six-well plates containing a fluconazole (FLC) gradient | `AutoCrop()`, `PAPArea()`, `PAPSingle()`, `PAPDual()` | Per-well grayscale/texture features mapped to FLC concentrations, with optional normalization |
| **B. Disk diffusion** (original package) | Photographs of plates with one central drug disk | `IJMacro()`, `plotRaw()`, `maxLik()`, `createDataframe()` and helpers | Resistance (RAD) and tolerance (FoG) estimates per photograph |

The PAP workflow reports grayscale features only. It does **not** calculate a PAP area under the curve (AUC) and does **not** classify isolates as heteroresistant.

This README describes package version **1.1.0.9066**.

## Contents

- [Installation](#installation)
- [Fiji/ImageJ setup](#fijiimagej-setup)
- [Workflow A: six-well PAP](#workflow-a-six-well-pap)
- [Workflow B: disk diffusion](#workflow-b-disk-diffusion)
- [Known issues and limitations](#known-issues-and-limitations)
- [Repository layout](#repository-layout)
- [Acknowledgements](#acknowledgements)
- [Citation](#citation)
- [Contact](#contact)

## Installation

```r
install.packages(c("devtools", "dplyr", "stringr", "tidyr"))
devtools::install_github("tony27786/diskImageR")
```

`DESCRIPTION` declares `zoo`, `subplex`, `tcltk` and `methods`, so those are installed automatically. The PAP wrappers also need `dplyr`, `stringr` and `tidyr`. These are **not** declared as dependencies, so install them yourself as shown above.

`PAPSingle()` and `PAPDual()` use the `%>%` pipe but do not import it. Attach `dplyr` before calling them:

```r
library(dplyr)
library(diskImageR)
```

## Fiji/ImageJ setup

Every image-processing step runs as a Fiji/ImageJ macro launched from R. The R session waits until Fiji exits. Most bundled macros call `Quit` when they finish, so the Fiji instance started by R closes itself.

| R function | Macro (`inst/`) | Needs Fiji specifically? |
| --- | --- | --- |
| `AutoCrop()` | `auto_crop.ijm`, `auto_crop_six.ijm` | Yes: uses the *Auto Threshold* plugin |
| `PAPArea()` (also called by `PAPSingle()`/`PAPDual()`) | `pap.ijm` | Yes: uses *Enhance Local Contrast (CLAHE)* |
| `IJMacro()` | `IJ_diskImageR.ijm` | No: core ImageJ commands only |
| `IJMacro16()` | `IJ_diskImageR16.ijm` | No (legacy launcher, see below) |

### How the application is located

**macOS** (`AutoCrop()`, `PAPArea()`, `IJMacro()`):

1. `/Applications/Fiji/Fiji.app`, if it exists. This location takes precedence **even when `imageJLoc` is supplied**.
2. `imageJLoc`, if it is an existing directory. It can be a `.app` bundle or a folder that contains `Fiji.app`.
3. `/Applications/Fiji.app`, `/Applications/ImageJ.app`, `/Applications/ImageJ/ImageJ.app`, in that order.

Inside the bundle, the launcher is looked up in `Contents/MacOS/` in this order: `fiji-macos-arm64`, `fiji-macos`, `fiji-macos-x64`, `jaunch-macos-arm64`, `jaunch-macos`, `jaunch-macos-x64`, `ImageJ-macosx`, `ImageJ`, `JavaApplicationStub`, `ImageJ-linux`. With `debug = TRUE`, `AutoCrop()` and `PAPArea()` print each candidate and the Fiji output. `IJMacro()` always prints the candidates.

**Windows:** all launchers look for a file named exactly `ImageJ.exe` in `C:\Program Files\ImageJ\` or `C:\Program Files (x86)\ImageJ\`. `AutoCrop()` and `PAPArea()` also accept a directory containing `ImageJ.exe` through `imageJLoc`. `IJMacro()` and `IJMacro16()` effectively ignore `imageJLoc` on Windows (see [Known issues](#known-issues-and-limitations)).

**Linux:** not supported. The non-Windows code path expects the macOS bundle layout (`Contents/MacOS/`).

### Paths

Arguments are passed to Fiji on the command line without shell quoting. Keep the project, photograph, output and R library paths free of spaces and special characters. Only lowercase `.jpg`, `.jpeg`, `.png`, `.tif` and `.tiff` extensions are recognised by `AutoCrop()` and `PAPArea()`.

## Workflow A: six-well PAP

```text
raw photos ──AutoCrop(plate = "six")──▶ *_crop.png ──PAPArea()──▶ pap_feature_results.csv + qc/
                                                                   │
                                            PAPSingle() / PAPDual() (FLC mapping, normalization, averaging)
```

`PAPSingle()` and `PAPDual()` call `PAPArea()` for you when `run_macro = TRUE` (the default). Call `PAPArea()` directly only when you want the per-well features without any concentration mapping.

### Step 1: crop the plates (optional)

```r
AutoCrop(
  photoDir  = "/path/to/raw_images",
  outputDir = "/path/to/cropped_images",
  plate     = "six",                    # required: "six" or "standard"
  imageJLoc = "/Applications/Fiji.app"
)
```

For each image, the six-well macro:

1. converts a copy to 8-bit, subtracts background (rolling ball 450), applies a Gaussian blur (σ = 3), thresholds with Otsu and fills holes;
2. keeps the largest particle of at least 5,000 px as the plate;
3. estimates plate tilt from the fitted-ellipse angle and rotates the original image when the tilt is ≥ 0.6°;
4. pads the canvas, re-detects the plate and crops its bounding box plus 30 px;
5. saves the result as `<original name>_crop.png` in `outputDir`.

An image is skipped, with a message in the Fiji log, when no plate is found or the detected plate covers more than 90 % of the image.

- Photograph the plate in **landscape orientation** on a dark background. The macro converts the ellipse angle to the smallest rotation in [−90°, 90°], so a plate photographed in portrait is rotated by about 90°. That changes which wells end up in the TL…BR positions.
- `plate = "standard"` uses `auto_crop.ijm` instead. It is meant for round Petri dishes: it keeps the largest particle ≥ 50,000 px with circularity 0.22–1.00 and pads the crop by 40 px. It does not rotate.
- Existing `*_crop.png` files in `outputDir` are overwritten without warning.
- The crop macro runs with batch mode off, so Fiji windows appear while it works.

### Step 2: check the ROI template and file names

`pap.ijm` measures six oval ROIs from `inst/papROISet.zip`. The ROIs are stored at fixed pixel positions, in this order:

| Index | Well | Position | ROI bounding box (x, y, w, h in px) |
| ---: | :---: | --- | --- |
| 1 | `TL` | top left | 365, 288, 758, 763 |
| 2 | `TM` | top middle | 1386, 268, 782, 796 |
| 3 | `TR` | top right | 2410, 268, 777, 794 |
| 4 | `BL` | bottom left | 350, 1297, 766, 791 |
| 5 | `BM` | bottom middle | 1376, 1312, 788, 800 |
| 6 | `BR` | bottom right | 2432, 1320, 768, 768 |

The template assumes images of roughly 3,200 × 2,120 px or larger, with the wells in the same places. Keep camera position, zoom and cropping consistent. If your images have a different geometry, create your own six-ROI zip in Fiji (in the order above) and pass it as `roiZip`. An image is skipped if the ROI zip does not contain exactly six ROIs.

File names become sample identifiers:

- The macro removes the last extension. The R wrappers then remove one more trailing `.<alphanumeric>` part and a trailing `_crop`. **Avoid dots in base names**: `iso_1.5_crop.png` becomes `iso_1`.
- `PAPSingle()`: the remaining name is the `sample_id`. `isolate01_rep1` and `isolate01_rep2` stay separate samples.
- `PAPDual()`: the name must end in an uppercase `L` (low-concentration plate) or `H` (high-concentration plate), e.g. `104L.png` / `104H_crop.png`, which both give `sample_id = "104"`. Names without the suffix are dropped with a warning.
- Any image whose base name matches `blank_pattern` (default regular expression `^000blank`) is treated as a blank plate and **removed from the samples in every normalization mode**. Set `blank_pattern = NULL` to disable this.

### Step 3: extract features with `PAPArea()`

```r
pap_features <- PAPArea(
  inputDir   = "/path/to/cropped_images",
  projectDir = "/path/to/pap_project",
  imageJLoc  = "/Applications/Fiji.app"
)
```

For every image and every ROI, `pap.ijm`:

1. duplicates the image, clears everything outside the ROI to black and converts it to 8-bit;
2. **raw pass:** measures area, mean, median and integrated density inside the ROI;
3. applies CLAHE with the ROI selected (block size 127, 256 bins, maximum slope 3);
4. **CLAHE pass:** measures mean, median, SD, min, max and integrated density; `cv_gray = sd_gray / mean_gray` (0 if the mean is 0);
5. computes the percentage of ROI pixels with CLAHE gray value ≤ 40, ≤ 60 and ≤ 80.

It also saves one QC image per photograph with the six ROI outlines drawn on it.

Files written to `projectDir`:

| Path | Content |
| --- | --- |
| `pap_feature_results.csv` | Six rows per successfully processed image |
| `qc/<image>_qc.png` | ROI overlay for visual QC |

Columns of the CSV and of the returned data frame:

| Column | Meaning |
| --- | --- |
| `image` | File name without extension |
| `well` | `TL`, `TM`, `TR`, `BL`, `BM`, `BR` (spatial position) |
| `roi_area` | ROI area (pixels for uncalibrated images) |
| `raw_mean`, `raw_median`, `raw_intden` | Pre-CLAHE 8-bit intensity: mean, median, integrated density |
| `mean_gray`, `median_gray`, `sd_gray`, `min_gray`, `max_gray`, `intden_gray` | Post-CLAHE statistics |
| `cv_gray` | Post-CLAHE coefficient of variation |
| `dark_frac_40`, `dark_frac_60`, `dark_frac_80` | Post-CLAHE percentage (0–100) of pixels at or below 40 / 60 / 80 |
| `pap_step` | Added in R: `well` as an ordered factor following `wellOrder` |
| `pap_index` | Added in R: position (1–6) of `well` in `wellOrder` |

Notes:

- `PAPArea()` **stops** if `pap_feature_results.csv` or `qc/` already exists in `projectDir`. `overwrite = TRUE` deletes both before running.
- `wellOrder` only controls `pap_step` and `pap_index`. It never changes the FLC mapping used by `PAPSingle()`/`PAPDual()`.
- With `projectName = "x"`, the data frame is also assigned to `x` in the global environment.
- `PAPArea()` does not normalize anything and does not assign concentrations.

### Step 4A: single-plate design, `PAPSingle()`

One plate per sample, with this fixed layout:

| Well | `TL` | `TM` | `TR` | `BL` | `BM` | `BR` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLC (µg/mL) | 0 | 8 | 12 | 16 | 24 | 32 |

```r
single <- PAPSingle(
  inputDir      = "/path/to/single_plate_images",
  projectDir    = "/path/to/single_project",
  imageJLoc     = "/Applications/Fiji.app",
  normalization = "0",       # default; or "000blank"
  assign_global = FALSE
)
```

A warning is issued for any sample that does not have all six wells.

### Step 4B: paired low/high plates, `PAPDual()`

Two plates per sample, with this fixed layout:

| Plate | `TL` | `TM` | `TR` | `BL` | `BM` | `BR` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Low (`L`) | 0 | 0.5 | 1 | 2 | 4 | 8 |
| High (`H`) | 0 | 8 | 16 | 32 | 64 | 128 |

FLC 0 and 8 µg/mL occur on both plates and are used for overlap QC.

```r
dual <- PAPDual(
  inputDir      = "/path/to/dual_plate_images",
  projectDir    = "/path/to/dual_project",
  imageJLoc     = "/Applications/Fiji.app",
  normalization = "highest", # default; or "0" or "000blank"
  assign_global = FALSE
)
```

A warning is issued for any sample that does not have both an `H` and an `L` plate. Provide exactly one `H` and one `L` image per sample. Duplicate plate images are not handled as replicates, and they break the one-value-per-cell layout of `overlap_qc`.

### Normalization

Normalization only **adds** `norm_mean`, `norm_median` and `norm_intden`, computed as `raw_* − reference`. The `raw_*` columns are never changed, and post-CLAHE features are not normalized.

| `normalization` | Available in | Reference subtracted |
| --- | --- | --- |
| `"0"` | `PAPSingle()` (default), `PAPDual()` | Per sample: the FLC = 0 well. Single: `TL`. Dual: mean of `L`-`TL` and `H`-`TL`. |
| `"highest"` | `PAPDual()` only (default) | Per sample: the `H`-`BR` well (128 µg/mL). |
| `"000blank"`, `blank_mode = "global"` | both | One value per feature: mean over all blank rows. |
| `"000blank"`, `blank_mode = "per_well"` | both | One value per feature and well position: mean of the blank rows at that position. |

Things to keep in mind when choosing a reference:

- With `"0"`, the reference is the no-drug well, so `norm_*` is usually negative at higher concentrations.
- `"highest"` assumes the 128 µg/mL well is a valid no-growth baseline. `PAPSingle()` deliberately does not offer it, because 32 µg/mL may still show growth.
- The wrappers only subtract. Whether a larger gray value means more or less growth depends on your lighting and background, so check the direction before interpreting signs.
- A sample that lacks the reference well gets `NA` in `norm_*`, with a warning.

**Blank plates** come from one of two sources:

- an image in the input folder matching `blank_pattern`, e.g. `000blank.png`;
- a feature CSV passed via `blank_csv`, e.g. the `pap_feature_results.csv` of a separate blank-only run. It must contain `well`, `raw_mean`, `raw_median` and `raw_intden`. `blank_csv` takes precedence over an in-folder blank, and it is ignored (with a warning) unless `normalization = "000blank"`.

The wrappers print the blank's six-well mean, SD and CV of `raw_mean`. If the CV exceeds 5 %, they suggest `blank_mode = "per_well"`.

```r
# In-folder blank, per-position subtraction
PAPSingle(projectDir = "/path/to/single_project", run_macro = FALSE,
          normalization = "000blank", blank_mode = "per_well",
          assign_global = FALSE)

# External blank CSV
PAPDual(projectDir = "/path/to/dual_project", run_macro = FALSE,
        normalization = "000blank", blank_mode = "global",
        blank_csv = "/path/to/blank_project/pap_feature_results.csv",
        assign_global = FALSE)
```

### Re-analysing without Fiji

With `run_macro = FALSE`, the wrappers read `projectDir/pap_feature_results.csv` and skip Fiji entirely. `inputDir`, `roiZip`, `imageJLoc` and `overwrite` are then irrelevant. Use this to compare normalization modes on the same measurements.

### Return value

With `return_mode = "all"` (default), both wrappers return a list:

| Element | `PAPSingle()` | `PAPDual()` |
| --- | --- | --- |
| `raw` | Per-image, per-well rows with `image_raw`, `image_base`, `sample_id`, `plate` (always `"S"`), `flc`, `norm_*` | Same, with `plate` = `"H"` or `"L"` |
| `overlap_qc` | `NULL` | One row per sample and FLC ∈ {0, 8}: `plate_H`, `plate_L` (both `norm_mean`), `diff = plate_H − plate_L`, `abs_diff` |
| `avg` | Mean of every numeric feature per `sample_id` × `flc` | Same; at FLC 0 and 8 the `H` and `L` values are averaged |

With `return_mode = "avg"`, only `avg` is returned. In `avg`, `n_plate` is the number of rows that were averaged: normally 1, or 2 at FLC 0/8 for a complete dual pair.

If `projectName` is given and `assign_global = TRUE` (the default), the list is also assigned to that name in the global environment. The processed tables are **not** written to disk. Save what you need:

```r
write.csv(dual$avg,        "/path/to/dual_project/pap_dual_avg.csv", row.names = FALSE)
write.csv(dual$overlap_qc, "/path/to/dual_project/pap_dual_overlap_qc.csv", row.names = FALSE)
```

### PAP checklist

- Open every image in `qc/` and confirm that each ROI sits inside the correct well. A shifted template invalidates every feature from that image.
- Review `overlap_qc$abs_diff` for dual plates. Large differences point to imaging or plate problems.
- Check the Fiji log output (use `debug = TRUE`) for skipped images.

## Workflow B: disk diffusion

This is the original `diskImageR` pipeline. The macro draws radial lines from the centre of a drug disk and records pixel intensity along each line. The R functions fit logistic models to the averaged profile and derive resistance and tolerance parameters.

```text
photos ──IJMacro()──▶ radial profiles ──plotRaw()──▶ QC figure
                                     └─maxLik()───▶ model fits ──createDataframe()──▶ RAD / FoG table
                                                                   └─ addType(), aggregateData(), calcMIC(), *ParamPlot()
```

### Preparing photographs

- Use consistent manual camera settings and even lighting without shadows. Photograph the plate on a dark background and crop it close to the plate. `AutoCrop(plate = "standard")` can do the cropping.
- The macro finds the disk as a bright, roughly circular particle of a fixed size. Avoid other similar-sized bright circles, such as label text.
- Put only the photographs in the photograph directory: no sub-folders and no other files.
- Name photographs `line_factor1_factor2_..._rep.ext`. The text before the first `_` becomes `line`, and later parts can be extracted as factor columns. Photographs are processed in alphabetical order, and that order defines the photograph numbers used by `clearHalo`.
- Take one photograph of a plate with a disk and no growth, and name it so that it sorts first (e.g. `a.jpg`). You can then use it as `clearHalo = 1` and drop it later with `removeClear = TRUE`.

### Project name and working directory

- `projectName` is passed as a string. Downstream functions look it up with `eval(parse(text = projectName))`, so it must be a syntactically valid R name. Start with a letter and avoid spaces and hyphens, e.g. `"newProject"`.
- All functions after `IJMacro()` read and write relative to the **current working directory**. `IJMacro()` and `readInExistingIJ()` switch the working directory to the project directory. In a new R session, call `setwd("/path/to/projectDir")` first.

### `IJMacro()`: extract radial profiles

```r
IJMacro("newProject",
        projectDir = "/path/to/projectDir",
        photoDir   = "/path/to/photos",
        imageJLoc  = "/Applications/Fiji.app",
        diskDiam   = 6)
```

If `projectDir` or `photoDir` is `NA`, a folder-picker dialog opens. For each photograph, the macro:

1. resizes the image to 1,000 px width and converts it to 8-bit;
2. finds exactly one disk by thresholding and particle analysis, trying several threshold and size presets. Disks under 8 mm and larger disks use different particle-size presets; the first small-disk preset expects 2,500–4,500 px at circularity ≥ 0.5;
3. derives the px/mm scale from the detected disk area and `diskDiam`;
4. records the intensity profile along 72 lines of 40 mm, one every 5°.

A photograph in which no disk, or more than one disk, is found is skipped.

It creates the following layout inside `projectDir`:

```text
imageJ_out/<projectName>/<photo>.txt        # all 72 profiles per photograph
parameter_files/<projectName>/averageLines.csv
figures/<projectName>/
```

In R, the 72 lines are averaged into one profile per photograph (distance 0–40 mm from the disk centre). The profiles are stored as a named list called `projectName`, with one element per photograph. Names are truncated to 30 characters. If `imageJ_out/<projectName>/` already contains files, you are asked whether to overwrite it; answering `y` deletes that folder.

`readInExistingIJ("name")` rebuilds the same list later from an existing `imageJ_out/<projectName>/` folder, using two folder-picker dialogs. It does not create `parameter_files/<name>/`. If you choose a new name, create that folder before running `maxLik()`, which saves its fits there.

### `plotRaw()`: inspect the profiles

```r
plotRaw("newProject", showNum = TRUE, popUp = FALSE)
```

Writes `figures/<projectName>/<projectName>_raw.pdf`, with one panel per photograph. The red dashed line marks `standardLoc`, the point used to align intensities. `showNum = TRUE` prints each photograph's number, which you need for `clearHalo`.

### `maxLik()`: fit the models

```r
maxLik("newProject", clearHalo = 1, RAD = "all", FoG = 20, typical = TRUE, popUp = FALSE)
```

What `maxLik()` does:

- **Fitting window:** from `diskDiam/2 + 1.2` mm to `maxDist − 0.5` mm (default `maxDist = 25`) from the disk centre. Distance is log-transformed for fitting.
- **Standardization (`standType = "one"`, default):** intensities are shifted so that all photographs agree at `standardLoc` (default 2.5 mm, on the white disk). The background next to the disk on the `clearHalo` photograph is used as the zero level. `standType = "indiv"` instead subtracts each photograph's own minimum; it is only available with `typical = TRUE`.
- **`typical = TRUE`:** fits a single logistic (4 starting points) and a double logistic (8 starting points) by maximum likelihood (`find.mle` with subplex). The results are saved as the RDS files `parameter_files/<projectName>/<projectName>_ML` and `_ML2` and assigned as `<projectName>.ML` / `.ML2`.
- **`typical = FALSE`:** fits a double logistic, a decreasing logistic ("confounding" growth) and a paradoxical curve, and keeps the best one. The paradoxical curve is chosen only if its log-likelihood exceeds the others by more than 20. Only `<projectName>.ML2` / `_ML2` is produced, and each fit is tagged `Log`, `NegLog` or `Para`.
- **Figure:** `figures/<projectName>/<projectName>_FoG.pdf` (typical) or `_all.pdf` (atypical), showing data, fit, RAD points and the FoG area. `RAD`, `FoG`, `ymax`, `xplots`, `plotSub`, `plotCompon`, etc. only affect the figure.
- **Runtime:** fitting can take a long time for many photographs; one dot is printed per photograph. `needML = FALSE` redraws the figure from the saved RDS files without refitting.

### `createDataframe()`: resistance and tolerance

```r
createDataframe("newProject", clearHalo = 1, typical = TRUE, removeClear = TRUE)
```

Use the same `clearHalo`, `diskDiam`, `maxDist`, `standardLoc`, `standType` and `typical` as in `maxLik()`.

**`typical = TRUE`** writes `parameter_files/<projectName>/<projectName>_df.csv` and `<projectName>.df`. The columns are:

| Column | Meaning (as implemented) |
| --- | --- |
| `name` | Photograph name. With `nameVector = FALSE`, `line` is replaced by the photograph number. A character vector supplies custom `line` labels. |
| `line` | Text before the first `_` |
| `type` | Name part at position `typePlace` (default 2). Renamed by `typeName`; omitted with `typeVector = FALSE`. |
| `RAD20`, `RAD50`, `RAD80` | Distance (mm, measured from the start of the fitting window) at which the fitted double-logistic curve first reaches 20 %, 50 % and 80 % of maximal growth, so normally RAD20 ≤ RAD50 ≤ RAD80. |
| `FoG20`, `FoG50`, `FoG80` | Area under the fitted curve up to the corresponding RAD, divided by RAD × the curve maximum in that interval. Capped at 1; `NA` when the RAD is 0 or 1. |

**`typical = FALSE`** writes one table per curve type that occurs:

| Curve type | Object | File | Parameters |
| --- | --- | --- | --- |
| Logistic | `<projectName>.df` | `<projectName>_df_log.csv` | `photo.index`, RAD/FoG as above |
| Confounding | `<projectName>_confound.df` | `<projectName>_df_negLog.csv` | `DRAD20`/`DRAD50`/`DRAD80`: radii of disinhibition (`NA` if not reached) |
| Paradoxical | `<projectName>_para.df` | `<projectName>_df_para.csv` | `curve.maxInhib` (minimum of the fitted curve), `observed.maxInhib` (minimum of the data) |

The current `createDataframe()` does **not** produce the `slope` (sensitivity) column that older versions reported.

### Optional helpers

| Function | Purpose | Output |
| --- | --- | --- |
| `saveMLparam(projectName, typical)` | Export fitted parameters and log-likelihoods | `<projectName>_ML.csv` / `_ML2.csv`, `<projectName>_ML.df` / `_ML2.df` |
| `addType(projectName, typePlace = 3, typeName = "type2")` | Add another factor column from the photograph name, inserted before `RAD80` | Updates `<projectName>.df` and `_df.csv` |
| `aggregateData(projectName, varFunc = "se", replicate = c("line", "type"))` | Mean and variability (`"se"`, `"cv"` or any R function name such as `"sd"`) across replicates | `<projectName>.ag`, `<projectName>_ag.csv` |
| `calcMIC(projectName, type = "df", RAD = "20")` | Convert RAD to MIC through a log2(MIC) ~ RAD or RAD² relationship: built-in literature values (`inst/knownMIC-RAD.csv`), a slope and intercept you enter, or a fitted standard curve. Interactive prompts. | Adds `MIC` to `<projectName>.df`, rewrites `_df.csv`; standard-curve PDF and parameters when fitted |
| `oneParamPlot()`, `twoParamPlot()`, `threeParamPlot()` | Plot one parameter, RAD + FoG, or RAD + FoG + slope, from `.df` (`type = "df"`) or `.ag` (`type = "ag"`) | PDFs in `figures/<projectName>/` |
| `readExistingDF(projectName)` | Load a saved `_df.csv` or `_ag.csv` through dialogs | `<projectName>.df` or `.ag` |

Several of these helpers expect the `slope` column that `createDataframe()` no longer produces; see [Known issues](#known-issues-and-limitations).

Figure functions open the finished PDF with the macOS `open` command when `popUp = TRUE`. Use `popUp = FALSE` on other systems.

### 16-disk plates (legacy)

`IJMacro16()` analyses plates carrying 16 disks. It assigns drug names from `drugs` (ordered from top left to bottom right), writes disk coordinates to `disk_coordinates/<projectName>/`, and averages the 180 profile lines per disk, keeping lines between the 0.55 and 0.75 intensity quantiles. Its launcher has not been updated. On macOS it only finds `/Applications/ImageJ.app` or `/Applications/ImageJ/ImageJ.app` (via `JavaApplicationStub`), and its macro does not quit Fiji/ImageJ at the end. The 16-disk options of `maxLik()`/`createDataframe()` (`needMap`, `testInhib`, `addSIR`, `RADcrit`) have been removed. `inst/walkthrough_disk16.R` and `inst/walkthrough_growInhib.R` still use them and will not run as written.

## Known issues and limitations

These were identified by reading the source code of version 1.1.0.9066.

**Disk diffusion workflow**

- **Missing `slope` column.** `createDataframe()` no longer returns `slope`. As a result, `aggregateData()` stops with an undefined-columns error on its output, and `threeParamPlot()` cannot plot slope.
- **`oneParamPlot()`** only works for `RAD*` parameters. Any other `param` triggers an error in `if (grep("RAD", param))`.
- **`saveMLparam(typical = TRUE)`** writes `_ML.csv` and then fails while building `_ML2.csv`: it reads a curve-type element that only atypical fits carry.
- **`calcMIC()`**
  - It reads `knownMIC-RAD.csv` from `.libPaths()` rather than via `system.file()`. On macOS/Linux this fails when more than one library path is set.
  - The option "MIC data for the same strains" references a non-existent `names` column.
  - Check that any built-in or published relationship uses the same RAD definition as your data.
- **Apparent hang in `IJMacro()`.** When a photograph fails disk detection, fewer output files than photographs exist. `IJMacro()` then busy-waits (up to 10¹² iterations) before stopping with a mismatch error. Interrupt R, remove or retake the failing photograph, and rerun.
- **Windows launchers.**
  - `IJMacro()`/`IJMacro16()` test `"ImageJ.exe" %in% imageJLoc`, so a custom `imageJLoc` is effectively ignored on Windows.
  - `AutoCrop()` on Windows ends with an error about the undefined `success` object after the macro has run. Check `outputDir` for the cropped files.
- **Outdated walkthroughs.** `inst/walkthrough.R` and `inst/walkthrough_atypical.R` are identical (both use `typical = FALSE`). `inst/drugCutoffs.csv` is not used by any function.

**PAP workflow and general**

- `dplyr`, `stringr` and `tidyr` are not declared in `DESCRIPTION`, and `%>%` is not imported; see [Installation](#installation).
- On macOS, `/Applications/Fiji/Fiji.app` overrides `imageJLoc` whenever it exists.
- Only lowercase image extensions are recognised, and dots inside file base names shorten the parsed sample identifiers.
- Command-line arguments to Fiji are not quoted, so paths with spaces break the macro call.

## Repository layout

```text
R/
  AutoCrop.R           AutoCrop()                  crop plates (Fiji)
  PAPArea.R            PAPArea()                   six-well feature extraction (Fiji)
  PAPSingle.R          PAPSingle()                 single-plate FLC mapping and normalization
  PAPDual.R            PAPDual()                   paired L/H plates, overlap QC
  IJMacro.R            IJMacro()                   disk profiles (ImageJ/Fiji)
  IJMacro16.R          IJMacro16()                 16-disk plates (legacy)
  readExistingIJ.R     readInExistingIJ()
  plotRaw.R            plotRaw()
  maxLik.R             maxLik() and model/plot helpers
  mle.R                find.mle() and helpers adapted from diversitree
  createDataframe.R    createDataframe() and RAD/FoG helpers
  saveMLParam.R        saveMLparam()
  addType.R, aggregateData.R, calcMIC.R, readExistingDF.R
  oneParamPlot.R, twoParamPlot.R, threeParamPlot.R
  imageJInterface.R    imageJInterface reference class (exported, not used by the workflows)
inst/
  pap.ijm, papROISet.zip                       PAP macro and default ROI template
  auto_crop.ijm, auto_crop_six.ijm             crop macros
  IJ_diskImageR.ijm, IJ_diskImageR16.ijm       disk macros
  knownMIC-RAD.csv                             built-in RAD–MIC relationships for calcMIC()
  drugCutoffs.csv                              unused
  diskImageR_vignette.html                     original disk-diffusion vignette (2016)
  walkthrough*.R                               original example scripts (partly outdated)
man/                                           R help pages (?PAPDual, ?maxLik, ...)
```

The bundled [HTML vignette](inst/diskImageR_vignette.html) and the upstream [PDF vignette](https://www.microstatslab.ca/uploads/2/3/5/6/23564534/diskimager_vignette_v4.pdf) describe the original disk workflow. They predate this fork, so some arguments and outputs differ from the current code.

## Acknowledgements

- Original package by Aleeza Gerstein and contributors: Sonja Friesen, Nazli Tahmasebi, Inbal Hecht, Erik White and Yoav Ram.
- Richard FitzJohn wrote `find.mle()` in [diversitree](https://github.com/richfitz/diversitree), adapted here in `R/mle.R`.
- Inbal Hecht coded portions of `calcMIC()` and improved Windows compatibility of `IJMacro()`.
- The original authors thank Adi Ulman, Noa Blutraich, Gal Benron, Alexander Rosenberg, Yoav Ram, Darren Abbey and Judith Berman for motivation, testing, code review and discussion.

## Citation

For the disk diffusion methods, cite the original publication:

> Gerstein AC, Rosenberg A, Hecht I, Berman J. diskImageR: quantification of resistance and tolerance to antimicrobial drugs using disk diffusion assays. *Microbiology* 2016;162(7):1059–1068. doi:[10.1099/mic.0.000295](https://doi.org/10.1099/mic.0.000295). PMID: [27126388](https://pubmed.ncbi.nlm.nih.gov/27126388/); PMCID: PMC5756480.

and the upstream repository, [acgerstein/diskImageR](https://github.com/acgerstein/diskImageR).

## Contact

This fork is maintained by Joseph Apoc ([@tony27786](https://github.com/tony27786)). For problems specific to it (PAP workflow, AutoCrop, launchers), open an issue at [tony27786/diskImageR](https://github.com/tony27786/diskImageR/issues). For the original method and package, see [acgerstein/diskImageR](https://github.com/acgerstein/diskImageR).

---

README revised for `diskImageR` 1.1.0.9066, September 2026.
