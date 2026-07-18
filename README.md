## Disclaimer

This repository is a fork of [acgerstein/diskImageR](https://github.com/acgerstein/diskImageR) and contains fixes for multiple known issues. This fork is community-maintained and is **not** an official upstream release. Please cite the original repository if you use this work.

**Documentation notice:** Due to time constraints, this README was written with the assistance of generative AI. A detailed, manually reviewed and corrected version will be provided later.

# diskImageR

`diskImageR` is an R package for image-based analysis of antimicrobial-response assays. This fork currently supports two related workflows:

1. the original disk diffusion workflow, including typical, confounding, and paradoxical growth analysis; and
2. a six-well PAP workflow for Fiji/ImageJ feature extraction, fluconazole (FLC) concentration mapping, normalization, and quality control.

The current PAP layer produces grayscale/texture gradients and normalized summary tables. It does not automatically calculate a classic PAP area under the curve (AUC) or assign a heteroresistance category.

This README reflects package version **1.1.0.9066**. The PAP implementation in the package source and function help pages should be treated as the reference until the planned manual review of this README is complete.

## What has been updated

The current PAP workflow is substantially different from the earlier area-threshold implementation.

| Area | Current behavior |
| --- | --- |
| PAP macro output | The output file is now `pap_feature_results.csv`; the older `pap_area_results.csv` format is no longer read by the PAP wrappers. |
| Feature extraction | `PAPArea()` records pre-CLAHE absolute grayscale features and post-CLAHE intensity, variability, and dark-pixel features for each of six wells. |
| Quality control | The Fiji macro writes one ROI overlay image per input image to `projectDir/qc/`. The old binary-mask output directory is no longer produced. |
| Single-plate processing | `PAPSingle()` maps a six-well plate to FLC concentrations `0, 8, 12, 16, 24, 32` µg/mL and supports no-drug or blank-plate normalization. |
| Dual-plate processing | `PAPDual()` combines paired low- and high-concentration plates, maps a unified `0–128` µg/mL gradient, and reports overlap QC at `0` and `8` µg/mL. |
| Normalization | Raw measurements are preserved. New `norm_mean`, `norm_median`, and `norm_intden` columns are added using the selected reference. |
| Blank plates | A blank can be detected in the image batch with a filename pattern (default: `^000blank`) or supplied as an external feature CSV. Global and per-well subtraction are available. |
| Batch reliability | The PAP macro uses unique temporary image names during batch processing to avoid alternating-image/window conflicts. |
| Six-well preparation | `AutoCrop(..., plate = "six")` uses the six-well crop macro, including tilt detection and automatic rotation before cropping. |

### Migration note

The previous PAP fields `pos_area` and `percent_area` have been replaced by grayscale features. Existing projects that contain only `pap_area_results.csv` must be reprocessed with the current `PAPArea()`/Fiji macro before they can be used with `PAPSingle()` or `PAPDual()`.

For `PAPDual()`, the older logical `normalize` argument has been replaced by the character-valued `normalization` argument documented below. The `wellOrder` argument controls `pap_step`/`pap_index` ordering only; it does not change the fixed FLC mappings used by `PAPSingle()` or `PAPDual()`.

## Installation

Install the current fork from GitHub:

```r
install.packages(c("devtools", "dplyr", "stringr", "tidyr"))
devtools::install_github("tony27786/diskImageR")
```

Then load the package. The current `PAPSingle()` and `PAPDual()` implementations use the pipe supplied by `dplyr`, so attach `dplyr` before using either wrapper.

```r
library(dplyr)
library(diskImageR)
```

The package declares R `>= 3.0.3`. PAP processing also checks for `dplyr`, `stringr`, and `tidyr` at runtime.

## Required external software

Fiji/ImageJ is required for image processing. **Fiji is recommended for the PAP workflow** because the bundled `pap.ijm` macro calls the CLAHE command (`Enhance Local Contrast`).

If Fiji/ImageJ is installed in a standard macOS location, the package will try to locate it automatically. Otherwise, pass the application directory explicitly, for example:

```r
imageJLoc <- "/Applications/Fiji.app"
```

On Windows, `imageJLoc` should be the directory containing `ImageJ.exe`. The current automatic launcher code is primarily set up for macOS and Windows.

## PAP workflow

### 1. Prepare the images

The bundled PAP ROI template contains exactly six ROIs in this spatial order:

| Index | Well | Position |
| ---: | :---: | --- |
| 1 | `TL` | top left |
| 2 | `TM` | top middle |
| 3 | `TR` | top right |
| 4 | `BL` | bottom left |
| 5 | `BM` | bottom middle |
| 6 | `BR` | bottom right |

Keep plate placement, image scale, and cropping consistent with the ROI template. The macro accepts lowercase `.jpg`, `.jpeg`, `.png`, `.tif`, and `.tiff` extensions. Uppercase extensions are not currently detected.

The default `papROISet.zip` is bundled with the package. Only pass `roiZip` when using a deliberately customized six-ROI template.

Optional six-well auto-cropping:

```r
raw_dir     <- "/path/to/raw_images"
cropped_dir <- "/path/to/cropped_images"

AutoCrop(
  photoDir  = raw_dir,
  outputDir = cropped_dir,
  plate     = "six",
  imageJLoc = "/Applications/Fiji.app"
)
```

The six-well crop macro saves PNG files with an `_crop` suffix. Both PAP wrappers remove that suffix when constructing sample identifiers.

### 2. Extract PAP features with `PAPArea()`

Use `PAPArea()` when you need the per-image, per-well measurements without a fixed FLC mapping:

```r
pap_features <- PAPArea(
  inputDir   = cropped_dir,
  projectDir = "/path/to/pap_feature_output",
  imageJLoc  = "/Applications/Fiji.app"
)

head(pap_features)
```

`PAPArea()` creates:

- `pap_feature_results.csv`, containing six rows per successfully processed image; and
- `qc/`, containing `<image>_qc.png` ROI overlays.

The returned data frame contains:

- identifiers: `image`, `well`, `pap_step`, `pap_index`;
- ROI size: `roi_area`;
- pre-CLAHE absolute features: `raw_mean`, `raw_median`, `raw_intden`;
- post-CLAHE features: `mean_gray`, `median_gray`, `sd_gray`, `min_gray`, `max_gray`, `intden_gray`, `cv_gray`; and
- post-CLAHE dark-pixel percentages: `dark_frac_40`, `dark_frac_60`, `dark_frac_80`.

`PAPArea()` does not normalize the measurements or assign FLC concentrations. Use `PAPSingle()` or `PAPDual()` for those steps.

### 3A. Single-plate PAP with `PAPSingle()`

Use `PAPSingle()` for the fixed single-plate design below:

| Well | `TL` | `TM` | `TR` | `BL` | `BM` | `BR` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLC (µg/mL) | 0 | 8 | 12 | 16 | 24 | 32 |

Image names become `sample_id` values after the extension and an optional trailing `_crop` are removed. For example, `isolate_01_crop.png` becomes `isolate_01`. No `H`/`L` suffix is required.

The parsed basename is used exactly as the sample identifier. Files such as `isolate_01_rep1.png` and `isolate_01_rep2.png` therefore remain different samples unless they are renamed or combined separately.

Run feature extraction and single-plate processing together:

```r
single_out <- "/path/to/single_pap_output"

single_res <- PAPSingle(
  inputDir      = "/path/to/single_plate_images",
  projectDir    = single_out,
  imageJLoc     = "/Applications/Fiji.app",
  normalization = "0",
  return_mode   = "all",
  assign_global = FALSE
)

head(single_res$raw)
head(single_res$avg)
```

The default `normalization = "0"` subtracts each sample's `TL` (`0` µg/mL) value. The normalized values at higher concentrations will therefore commonly be negative; their magnitude represents the change from the no-drug control.

The single-plate design intentionally does **not** offer `normalization = "highest"`, because the `BR` well (`32` µg/mL) may still contain biologically meaningful growth.

### 3B. Dual-plate PAP with `PAPDual()`

For each sample, provide one low plate and one high plate. The image basename must end in uppercase `L` or `H` before an optional `_crop` suffix:

- `104L.png` and `104H.png`; or
- `104L_crop.png` and `104H_crop.png`.

Both pairs produce `sample_id = "104"`.

The part before the final plate suffix does not have to be numeric. Each sample should have one unique `L` image and one unique `H` image. A missing plate first produces a warning and may then lead to incomplete or failed overlap QC; duplicate plate images are not a supported substitute for an explicit replicate-analysis step.

The fixed FLC mapping is:

| Plate | `TL` | `TM` | `TR` | `BL` | `BM` | `BR` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Low (`L`) | 0 | 0.5 | 1 | 2 | 4 | 8 |
| High (`H`) | 0 | 8 | 16 | 32 | 64 | 128 |

Run feature extraction and dual-plate processing together:

```r
dual_out <- "/path/to/dual_pap_output"

dual_res <- PAPDual(
  inputDir      = "/path/to/dual_plate_images",
  projectDir    = dual_out,
  imageJLoc     = "/Applications/Fiji.app",
  normalization = "highest",
  return_mode   = "all",
  assign_global = FALSE
)

head(dual_res$raw)
dual_res$overlap_qc
head(dual_res$avg)
```

The default `normalization = "highest"` subtracts the high-plate `BR` well (`128` µg/mL) separately for each sample. This mode assumes that well is a valid no-growth/agar baseline for the experiment; verify that assumption before interpreting the normalized values.

`overlap_qc` compares `norm_mean` between the low and high plates at the duplicated `0` and `8` µg/mL concentrations. It reports `plate_H`, `plate_L`, `diff = plate_H - plate_L`, and `abs_diff`. Large `abs_diff` values should prompt inspection of the corresponding QC images and plate measurements.

### 4. Compare normalization methods without rerunning Fiji

After `pap_feature_results.csv` has been generated, set `run_macro = FALSE` to reuse it:

```r
dual_zero <- PAPDual(
  projectDir    = dual_out,
  run_macro     = FALSE,
  normalization = "0",
  assign_global = FALSE
)

dual_avg_only <- PAPDual(
  projectDir    = dual_out,
  run_macro     = FALSE,
  normalization = "highest",
  return_mode   = "avg",
  assign_global = FALSE
)
```

Available normalization modes are:

| Mode | `PAPSingle()` | `PAPDual()` | Reference calculation |
| --- | :---: | :---: | --- |
| `"0"` | default | available | Single: sample `TL`; dual: mean of the sample's `L-TL` and `H-TL` wells. |
| `"highest"` | not available | default | The sample's `H-BR` well (`128` µg/mL). |
| `"000blank"`, `blank_mode = "global"` | available | available | One offset per feature, calculated across all six blank wells. |
| `"000blank"`, `blank_mode = "per_well"` | available | available | A separate offset for each spatial well position. |

All modes leave `raw_mean`, `raw_median`, and `raw_intden` unchanged and add the corresponding `norm_*` columns. Post-CLAHE features are retained but are not used to calculate `norm_*`. The wrappers perform reference subtraction only; interpret the sign of a normalized grayscale difference after confirming the lighting and grayscale polarity of the imaging setup.

#### In-folder blank

Include an image such as `000blank.png` in the input batch and request blank normalization:

```r
single_blank <- PAPSingle(
  projectDir    = single_out,
  run_macro     = FALSE,
  normalization = "000blank",
  blank_mode    = "per_well",
  assign_global = FALSE
)
```

The default `blank_pattern = "^000blank"` is a regular expression matched against the image basename. Matching images are used as blank references and excluded from sample results.

#### External blank CSV

Alternatively, provide a feature CSV containing the blank-plate rows:

```r
dual_blank <- PAPDual(
  projectDir    = dual_out,
  run_macro     = FALSE,
  normalization = "000blank",
  blank_mode    = "global",
  blank_csv     = "/path/to/blank/pap_feature_results.csv",
  assign_global = FALSE
)
```

An external blank CSV takes precedence over an in-folder blank. It must contain `well`, `raw_mean`, `raw_median`, and `raw_intden`. The wrappers report the blank's six-well grayscale mean, standard deviation, and coefficient of variation; when the CV exceeds 5%, they suggest considering `blank_mode = "per_well"`.

### 5. Understand and save the returned objects

With `return_mode = "all"`, both wrappers return a list with a common structure:

| Element | `PAPSingle()` | `PAPDual()` |
| --- | --- | --- |
| `raw` | Per-well measurements with `sample_id`, `plate = "S"`, FLC, and `norm_*`. | Per-well measurements with `sample_id`, `plate = "H"/"L"`, FLC, and `norm_*`. |
| `overlap_qc` | `NULL` because the single plate has no duplicated concentrations. | H-versus-L comparison at `0` and `8` µg/mL. |
| `avg` | Sample-by-FLC mean table. | Sample-by-FLC mean table; duplicated `0` and `8` µg/mL values are averaged across plates. |

In `avg`, the current `n_plate` column is the number of input rows contributing to each sample-by-FLC group. For a complete dual-plate pair it is normally `2` at the duplicated `0` and `8` µg/mL concentrations and `1` elsewhere; it should not be interpreted as a robust distinct-plate count when duplicate inputs are present.

The processed `raw`, `overlap_qc`, and `avg` objects are returned to R but are not automatically written as separate CSV files. Save them explicitly if needed:

```r
write.csv(dual_res$avg,
          file.path(dual_out, "pap_dual_avg.csv"),
          row.names = FALSE)

write.csv(dual_res$overlap_qc,
          file.path(dual_out, "pap_dual_overlap_qc.csv"),
          row.names = FALSE)
```

A minimal visualization for the first sample is:

```r
one_sample <- subset(
  single_res$avg,
  sample_id == single_res$avg$sample_id[1]
)

plot(
  one_sample$flc,
  one_sample$norm_mean,
  type = "b",
  xlab = "FLC (µg/mL)",
  ylab = "Normalized mean grayscale"
)
```

If `projectName` is supplied and `assign_global = TRUE`, `PAPSingle()` or `PAPDual()` also places the full result list in the global environment under that name. Capturing the return value with `assign_global = FALSE`, as in the examples above, keeps the data flow explicit. `PAPArea()` similarly assigns its data frame globally only when `projectName` is supplied.

## PAP troubleshooting and quality checks

- **Existing output:** `PAPArea()` stops if `pap_feature_results.csv` or `qc/` already exists. Set `overwrite = TRUE` only when you intend to remove those previous PAP outputs and rerun the macro.
- **Reusing output:** `run_macro = FALSE` requires a file named exactly `pap_feature_results.csv` in `projectDir`.
- **ROI count:** the Fiji macro expects exactly six ROIs. An image is skipped if the loaded ROI zip does not contain six entries.
- **QC overlays:** inspect every file in `qc/` before analyzing results. A shifted ROI template invalidates all features from the affected image.
- **Image names:** dual-plate sample images without a final uppercase `H` or `L` are ignored with a warning. Blank images should match `blank_pattern`.
- **Fiji launcher:** if automatic discovery fails, set `imageJLoc` to the Fiji/ImageJ application directory and use `debug = TRUE` to print the selected paths and process output.
- **Fiji closes after the macro:** the bundled PAP macro calls `Quit` when the batch finishes, so the Fiji process started for the analysis will close automatically.
- **Missing pipe or packages:** install `dplyr`, `stringr`, and `tidyr`, and run `library(dplyr)` before the PAP wrappers.
- **Normalization choice:** inspect raw measurements and experimental controls before choosing a baseline. The available methods encode different biological assumptions and are not interchangeable by default.
- **Current Windows `AutoCrop()` limitation:** the Windows macro can write cropped files but the R wrapper may subsequently fail while checking its completion status. Verify the output directory if this occurs.

For full argument documentation, use:

```r
?AutoCrop
?PAPArea
?PAPSingle
?PAPDual
```

## Original disk diffusion workflow

The original workflow analyzes radial pixel-intensity profiles around diffusion disks. For typical assays it estimates resistance using RAD20/RAD50/RAD80, tolerance using FoG20/FoG50/FoG80, and sensitivity from the fitted curve. With `typical = FALSE`, the package can also classify and analyze confounding and paradoxical response patterns.

### Main functions

| Stage | Function | Purpose |
| --- | --- | --- |
| Optional preparation | `AutoCrop()` | Crop a standard or six-well plate from a dark background. |
| ImageJ extraction | `IJMacro()` | Analyze a standard single-disk photograph. |
| Multi-disk extraction | `IJMacro16()` | Analyze plates containing 16 diffusion disks. |
| Reload extraction | `readInExistingIJ()` | Load an existing ImageJ analysis into R. |
| Raw-data QC | `plotRaw()` | Plot the average radial intensity profiles. |
| Curve fitting | `maxLik()` | Fit the response models. |
| Optional model export | `saveMLparam()` | Save fitted maximum-likelihood parameters. |
| Parameter table | `createDataframe()` | Calculate and save response parameters. |
| Replicate summary | `aggregateData()` | Aggregate replicate photographs. |
| MIC conversion | `calcMIC()` | Convert supported RAD measurements to MIC estimates. |
| Plotting | `oneParamPlot()`, `twoParamPlot()`, `threeParamPlot()` | Plot one, two, or three response parameters. |

### Minimal traditional example

```r
library(diskImageR)

IJMacro(
  "newProject",
  projectDir = "/path/to/project",
  photoDir   = "/path/to/photographs"
)

plotRaw("newProject")

maxLik(
  "newProject",
  clearHalo = 1,
  RAD        = "all",
  FoG        = 20,
  typical    = TRUE
)

createDataframe(
  "newProject",
  clearHalo = 1,
  typical   = TRUE
)

# Optional
saveMLparam("newProject", typical = TRUE)
aggregateData("newProject")
calcMIC("newProject")
```

For atypical response analysis, pass `typical = FALSE` consistently to `maxLik()`, `saveMLparam()`, and `createDataframe()`.

Photograph quality and consistency remain critical. Use fixed camera settings, minimize shadows, keep the plate geometry consistent, and inspect the raw-profile plots before fitting models. The standard disk workflow also expects paths without spaces or special characters.

## Vignette and additional help

The repository includes a [bundled HTML vignette](inst/diskImageR_vignette.html) for the original disk diffusion workflow. An upstream PDF vignette is also available [here](https://www.microstatslab.ca/uploads/2/3/5/6/23564534/diskimager_vignette_v4.pdf).

The PDF vignette predates the PAP feature workflow documented above. For PAP-specific arguments and return values, use the current R help pages and source-linked documentation.

## Acknowledgements

- Richard FitzJohn contributed the maximum-likelihood function `find.mle()` from [diversitree](https://github.com/richfitz/diversitree).
- Inbal Hecht coded portions of `calcMIC()` and contributed a patch that improved `IJMacro()` compatibility with Windows.
- Sincere thanks to Adi Ulman, Noa Blutraich, Gal Benron, Alexander Rosenberg, Yoav Ram, Darren Abbey, and Judith Berman for the motivation, testing, code review, and discussions that supported the original package.

## Questions, comments, and feedback

For issues specific to this fork, please use the [GitHub issue tracker](https://github.com/tony27786/diskImageR/issues). For the original package and scientific workflow, see [acgerstein/diskImageR](https://github.com/acgerstein/diskImageR).

## Updated

README synchronized with `diskImageR` **1.1.0.9066** in July 2026.
