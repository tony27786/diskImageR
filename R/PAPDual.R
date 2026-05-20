#' Process dual-plate PAP results and merge into a unified FLC gradient table
#'
#' @description
#' \code{PAPDual()} is a wrapper around \code{PAPArea()} for processing
#' PAP experiments performed on paired low- and high-concentration fluconazole
#' plates. It supports running the ImageJ/Fiji macro through \code{PAPArea()},
#' or directly reading an existing \code{pap_feature_results.csv} file from
#' \code{projectDir}. The function parses sample identifiers and plate type
#' (\code{H} or \code{L}) from image names, maps wells to predefined fluconazole
#' concentrations, performs overlap quality control for duplicated concentrations,
#' and returns both raw and averaged PAP summaries.
#'
#' @details
#' The function assumes image file names follow a pattern such as
#' \code{104H}, \code{104L}, or \code{104H_crop}, where:
#' \itemize{
#'   \item the leading numeric portion is treated as the sample identifier;
#'   \item the trailing \code{H} or \code{L} indicates the plate type;
#'   \item an optional \code{_crop} suffix is ignored during parsing.
#' }
#'
#' Fluconazole concentrations are assigned according to the well position:
#'
#' \strong{Low plate (\code{L})}
#' \itemize{
#'   \item \code{TL = 0}
#'   \item \code{TM = 0.5}
#'   \item \code{TR = 1}
#'   \item \code{BL = 2}
#'   \item \code{BM = 4}
#'   \item \code{BR = 8}
#' }
#'
#' \strong{High plate (\code{H})}
#' \itemize{
#'   \item \code{TL = 0}
#'   \item \code{TM = 8}
#'   \item \code{TR = 16}
#'   \item \code{BL = 32}
#'   \item \code{BM = 64}
#'   \item \code{BR = 128}
#' }
#'
#' When \code{normalize = TRUE} (default), the H-plate BR well (128 ug/mL) is
#' used as a per-sample internal zero reference. This well consistently shows
#' no growth and controls for per-sample variation in agar opacity, inoculum
#' density, and photography conditions. Normalized columns (\code{norm_mean},
#' \code{norm_median}, \code{norm_intden}) are computed by subtracting the
#' 128-well baseline from the corresponding raw values.
#'
#' Optionally, a blank plate CSV (\code{blank_csv}) can be provided for
#' additional per-well-position correction of illumination artifacts.
#'
#' The function generates three outputs:
#' \itemize{
#'   \item \code{raw}: annotated per-image, per-well PAP results with parsed
#'   sample ID, plate type, mapped FLC concentration, and normalization columns;
#'   \item \code{overlap_qc}: comparison of duplicated concentrations shared
#'   between plates (0 and 8 ug/mL);
#'   \item \code{avg}: merged sample-by-concentration table obtained by averaging
#'   duplicate concentrations across plates.
#' }
#'
#' @param inputDir Character scalar. Directory containing input PAP images.
#' Passed to \code{PAPArea()} when \code{run_macro = TRUE}. Can be \code{NULL}
#' if an existing CSV file is used.
#'
#' @param projectDir Character scalar. Directory used to store or read PAPArea
#' results.
#'
#' @param projectName Optional character scalar. Name of the object to create in
#' the global environment when \code{assign_global = TRUE}.
#'
#' @param roiZip Optional character scalar. Path to the ROI zip file used by
#' \code{PAPArea()}.
#'
#' @param wellOrder Character vector specifying the expected order of wells for
#' PAP step assignment. Defaults to
#' \code{c("TL", "TM", "TR", "BL", "BM", "BR")}.
#'
#' @param imageJLoc Character scalar. Path to the ImageJ/Fiji executable.
#' Passed to \code{PAPArea()}. Defaults to \code{NA}.
#'
#' @param overwrite Logical. Whether existing outputs should be overwritten when
#' running \code{PAPArea()}.
#'
#' @param debug Logical. Whether to print additional debugging information.
#'
#' @param return_mode Character scalar. Either \code{"all"} or \code{"avg"}.
#'
#' @param assign_global Logical. Whether to assign the returned object into the
#' global environment when \code{projectName} is not \code{NULL}.
#'
#' @param run_macro Logical. If \code{TRUE}, run \code{PAPArea()} first. If
#' \code{FALSE}, skip macro execution and directly read an existing CSV.
#'
#' @param normalize Logical. If \code{TRUE} (default), perform 128-well
#' normalization using the H-plate BR well as per-sample internal zero.
#'
#' @param blank_csv Optional character scalar. Path to a blank-plate
#' \code{pap_feature_results.csv} for per-well-position illumination correction.
#' If \code{NULL} (default), blank correction is skipped.
#'
#' @return
#' If \code{return_mode = "all"}, a named list with three elements:
#' \describe{
#'   \item{raw}{Annotated per-image, per-well results with normalization columns.}
#'   \item{overlap_qc}{Comparison of duplicated concentrations (0 and 8 ug/mL)
#'   between H and L plates.}
#'   \item{avg}{Averaged summary per sample-by-concentration.}
#' }
#'
#' If \code{return_mode = "avg"}, only the averaged summary data frame is
#' returned.
#'
#' @seealso \code{\link{PAPArea}}
#'
#' @examples
#' \dontrun{
#' # Run macro + 128-well normalization
#' res <- PAPDual(
#'   inputDir    = "path/to/images",
#'   projectDir  = "path/to/project",
#'   projectName = "pap_dual_res",
#'   roiZip      = "path/to/papROISet.zip",
#'   return_mode = "all"
#' )
#'
#' # Read existing CSV, skip normalization
#' avg_res <- PAPDual(
#'   projectDir  = "path/to/project",
#'   run_macro   = FALSE,
#'   normalize   = FALSE,
#'   return_mode = "avg"
#' )
#' }
#'
#' @export

PAPDual <- function(inputDir = NULL,
                    projectDir,
                    projectName = NULL,
                    roiZip = NULL,
                    wellOrder = c("TL", "TM", "TR", "BL", "BM", "BR"),
                    imageJLoc = NA,
                    overwrite = FALSE,
                    debug = FALSE,
                    return_mode = c("all", "avg"),
                    assign_global = TRUE,
                    run_macro = TRUE,
                    normalize = TRUE,
                    blank_csv = NULL) {
  
  return_mode <- match.arg(return_mode)
  
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required.")
  }
  if (!requireNamespace("stringr", quietly = TRUE)) {
    stop("Package 'stringr' is required.")
  }
  if (!requireNamespace("tidyr", quietly = TRUE)) {
    stop("Package 'tidyr' is required.")
  }
  
  # ---- [CHANGED] CSV filename ----
  csv_file <- file.path(projectDir, "pap_feature_results.csv")
  
  # 1) get PAPArea result
  if (run_macro) {
    pap_raw <- PAPArea(
      inputDir    = inputDir,
      projectDir  = projectDir,
      projectName = NULL,
      roiZip      = roiZip,
      wellOrder   = wellOrder,
      imageJLoc   = imageJLoc,
      overwrite   = overwrite,
      debug       = debug
    )
    
    if (is.null(pap_raw)) {
      if (!file.exists(csv_file)) {
        stop("PAPArea returned NULL and no pap_feature_results.csv was found in projectDir.")
      }
      pap_raw <- read.csv(csv_file, stringsAsFactors = FALSE, check.names = FALSE)
    }
    
  } else {
    if (!file.exists(csv_file)) {
      stop("`run_macro = FALSE`, but no pap_feature_results.csv was found in projectDir:\n", csv_file)
    }
    pap_raw <- read.csv(csv_file, stringsAsFactors = FALSE, check.names = FALSE)
  }
  
  # 2) restore well-related columns if directly reading csv
  allowed_wells <- c("TL", "TM", "TR", "BL", "BM", "BR")
  
  if ("well" %in% colnames(pap_raw)) {
    pap_raw$well <- as.character(pap_raw$well)
    pap_raw$well <- factor(pap_raw$well, levels = allowed_wells, ordered = FALSE)
    pap_raw$pap_step <- factor(as.character(pap_raw$well),
                               levels = wellOrder,
                               ordered = TRUE)
    pap_raw$pap_index <- match(as.character(pap_raw$well), wellOrder)
  } else {
    stop("Input PAP result is missing `well` column.")
  }
  
  # 3) image -> basename / sample_id / plate
  pap_annot <- pap_raw %>%
    dplyr::mutate(
      image_raw  = as.character(image),
      image_base = stringr::str_remove(image_raw, "\\.[A-Za-z0-9]+$"),
      image_base = stringr::str_remove(image_base, "_crop$"),
      plate      = stringr::str_extract(image_base, "[HL]$"),
      sample_id  = stringr::str_remove(image_base, "[HL]$")
    )
  # drop non-H/L images (e.g. blank reference plates) before validation
  not_plate <- is.na(pap_annot$plate) | !pap_annot$plate %in% c("H", "L")
  if (any(not_plate)) {
    message("Ignoring non-H/L images (not sample plates): ",
            paste(unique(pap_annot$image_raw[not_plate]), collapse = ", "))
    pap_annot <- pap_annot[!not_plate, , drop = FALSE]
  }
  
  # check file names
  if (any(is.na(pap_annot$sample_id) | pap_annot$sample_id == "")) {
    bad_images <- unique(pap_annot$image_raw[is.na(pap_annot$sample_id) | pap_annot$sample_id == ""])
    stop(
      "Failed to parse sample_id from these image names:\n",
      paste(bad_images, collapse = "\n"),
      "\nExpected names like '104H', '104L', '104H_crop'."
    )
  }
  
  if (any(is.na(pap_annot$plate) | !pap_annot$plate %in% c("H", "L"))) {
    bad_images <- unique(pap_annot$image_raw[is.na(pap_annot$plate) | !pap_annot$plate %in% c("H", "L")])
    stop(
      "Failed to parse plate type (H/L) from these image names:\n",
      paste(bad_images, collapse = "\n"),
      "\nExpected names like '104H', '104L', '104H_crop'."
    )
  }
  
  # 4) FLC concentration mapping
  pap_dual_raw <- pap_annot %>%
    dplyr::mutate(
      well = as.character(well),
      flc = dplyr::case_when(
        plate == "L" & well == "TL" ~ 0,
        plate == "L" & well == "TM" ~ 0.5,
        plate == "L" & well == "TR" ~ 1,
        plate == "L" & well == "BL" ~ 2,
        plate == "L" & well == "BM" ~ 4,
        plate == "L" & well == "BR" ~ 8,
        
        plate == "H" & well == "TL" ~ 0,
        plate == "H" & well == "TM" ~ 8,
        plate == "H" & well == "TR" ~ 16,
        plate == "H" & well == "BL" ~ 32,
        plate == "H" & well == "BM" ~ 64,
        plate == "H" & well == "BR" ~ 128,
        
        TRUE ~ NA_real_
      )
    ) %>%
    dplyr::arrange(sample_id, plate, flc)
  
  # 5) check H/L completeness
  plate_check <- pap_dual_raw %>%
    dplyr::distinct(sample_id, plate) %>%
    dplyr::count(sample_id, name = "n_plate")
  
  if (any(plate_check$n_plate != 2)) {
    bad_samples <- plate_check$sample_id[plate_check$n_plate != 2]
    warning(
      "Some samples do not have both H and L plates:\n",
      paste(bad_samples, collapse = ", ")
    )
  }
  
  # ---- [NEW] Optional blank-plate correction ----
  if (!is.null(blank_csv)) {
    if (!file.exists(blank_csv)) {
      stop("blank_csv file not found: ", blank_csv)
    }
    blank_df <- read.csv(blank_csv, stringsAsFactors = FALSE, check.names = FALSE)
    
    blank_needed <- c("well", "raw_mean", "raw_median", "raw_intden")
    blank_missing <- setdiff(blank_needed, colnames(blank_df))
    if (length(blank_missing) > 0) {
      stop("Blank CSV is missing columns: ", paste(blank_missing, collapse = ", "))
    }
    
    # average across blank images per well position
    blank_ref <- blank_df %>%
      dplyr::group_by(well) %>%
      dplyr::summarise(
        blank_mean   = mean(raw_mean,   na.rm = TRUE),
        blank_median = mean(raw_median, na.rm = TRUE),
        blank_intden = mean(raw_intden, na.rm = TRUE),
        .groups = "drop"
      )
    
    pap_dual_raw <- pap_dual_raw %>%
      dplyr::left_join(blank_ref, by = "well") %>%
      dplyr::mutate(
        raw_mean   = raw_mean   - blank_mean,
        raw_median = raw_median - blank_median,
        raw_intden = raw_intden - blank_intden
      ) %>%
      dplyr::select(-blank_mean, -blank_median, -blank_intden)
    
    message("Blank-plate correction applied from: ", blank_csv)
  }
  
  # ---- [NEW] 128-well normalization ----
  if (normalize) {
    # H-plate BR well (flc = 128) as per-sample internal zero
    zero_ref <- pap_dual_raw %>%
      dplyr::filter(plate == "H", well == "BR") %>%
      dplyr::select(
        sample_id,
        zero_mean   = raw_mean,
        zero_median = raw_median,
        zero_intden = raw_intden
      )
    
    missing_zero <- setdiff(
      unique(pap_dual_raw$sample_id),
      zero_ref$sample_id
    )
    if (length(missing_zero) > 0) {
      warning(
        "128-well normalization: no H-plate BR data for samples:\n",
        paste(missing_zero, collapse = ", "),
        "\nThese samples will have NA in norm_* columns."
      )
    }
    
    pap_dual_raw <- pap_dual_raw %>%
      dplyr::left_join(zero_ref, by = "sample_id") %>%
      dplyr::mutate(
        norm_mean   = raw_mean   - zero_mean,
        norm_median = raw_median - zero_median,
        norm_intden = raw_intden - zero_intden
      ) %>%
      dplyr::select(-zero_mean, -zero_median, -zero_intden)
    
    message("128-well normalization applied (H-plate BR as zero reference).")
  }
  
  # ---- [CHANGED] overlap QC: raw_mean replaces percent_area ----
  # Use norm_mean if normalization was applied, otherwise raw_mean
  qc_metric <- if (normalize && "norm_mean" %in% colnames(pap_dual_raw)) {
    "norm_mean"
  } else {
    "raw_mean"
  }
  
  overlap_qc <- pap_dual_raw %>%
    dplyr::filter(flc %in% c(0, 8)) %>%
    dplyr::select(sample_id, plate, flc, dplyr::all_of(qc_metric)) %>%
    tidyr::pivot_wider(
      names_from  = plate,
      values_from = dplyr::all_of(qc_metric),
      names_prefix = "plate_"
    ) %>%
    dplyr::mutate(
      diff     = plate_H - plate_L,
      abs_diff = abs(diff)
    ) %>%
    dplyr::arrange(sample_id, flc)
  
  # ---- [CHANGED] averaging: new column set ----
  # Build summarise expressions dynamically based on available columns
  avg_cols <- c("roi_area", "raw_mean", "raw_median", "raw_intden",
                "mean_gray", "median_gray", "sd_gray",
                "min_gray", "max_gray", "intden_gray", "cv_gray",
                "dark_frac_40", "dark_frac_60", "dark_frac_80")
  
  # Add norm columns if they exist
  if (normalize && "norm_mean" %in% colnames(pap_dual_raw)) {
    avg_cols <- c(avg_cols, "norm_mean", "norm_median", "norm_intden")
  }
  
  # Only average columns that actually exist in the data
  avg_cols <- intersect(avg_cols, colnames(pap_dual_raw))
  
  pap_dual_avg <- pap_dual_raw %>%
    dplyr::group_by(sample_id, flc) %>%
    dplyr::summarise(
      dplyr::across(dplyr::all_of(avg_cols), ~ mean(.x, na.rm = TRUE)),
      n_plate = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::arrange(sample_id, flc)
  
  out <- list(
    raw        = pap_dual_raw,
    overlap_qc = overlap_qc,
    avg        = pap_dual_avg
  )
  
  if (!is.null(projectName) && assign_global) {
    assign(projectName, out, envir = .GlobalEnv)
    message("PAPDual completed. Result assigned to `", projectName, "`.")
  } else {
    message("PAPDual completed.")
  }
  
  if (return_mode == "avg") {
    return(pap_dual_avg)
  } else {
    return(out)
  }
}