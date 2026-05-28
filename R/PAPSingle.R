#' Process single-plate PAP results into an FLC gradient table
#'
#' @description
#' \code{PAPSingle()} is the single-plate counterpart of \code{PAPDual()},
#' tailored for the Figure 3 (clinical single-clone, batch 02) PAP design:
#' one 6-well plate per sample covering fluconazole = 0, 8, 12, 16, 24, 32
#' ug/mL. The output schema mirrors \code{PAPDual()} as closely as possible.
#'
#' @details
#' Differences vs \code{PAPDual()}:
#' \itemize{
#'   \item No H/L plate distinction. Image names are parsed as-is into
#'   \code{sample_id} (extension and trailing \code{_crop} stripped). A constant
#'   \code{plate = "S"} column is emitted for downstream API consistency.
#'   \item Single-plate FLC mapping (see below).
#'   \item The \code{"highest"} normalization mode is unavailable: the highest
#'   concentration on this plate (32 ug/mL) is biologically informative and
#'   frequently shows growth in HR isolates, so it cannot serve as a
#'   guaranteed-zero reference.
#'   \item No \code{overlap_qc} (no duplicated concentrations within a single
#'   plate). The slot is preserved as \code{NULL} in the return list so
#'   downstream code accessing \code{out$overlap_qc} does not break.
#' }
#'
#' Well-to-FLC mapping (single plate):
#' \itemize{
#'   \item \code{TL = 0},  \code{TM = 8},   \code{TR = 12}
#'   \item \code{BL = 16}, \code{BM = 24},  \code{BR = 32}
#' }
#'
#' \strong{Normalization modes (\code{normalization}).} Both modes add
#' \code{norm_mean}, \code{norm_median}, \code{norm_intden} columns;
#' \code{raw_*} columns are never modified.
#' \itemize{
#'   \item \code{"0"} (default) — per-sample subtraction of the FLC=0 (TL)
#'   well. Because FLC=0 is a growth maximum, \code{norm_*} is typically
#'   negative at FLC > 0 and its magnitude reflects growth deficit relative
#'   to the no-drug control.
#'   \item \code{"000blank"} — per-batch subtraction of a blank-plate
#'   reference, auto-detected from the input folder via \code{blank_pattern}
#'   (default \code{"^000blank"}) or supplied externally via \code{blank_csv}.
#'   \code{blank_mode = "global"} uses the 6-well mean as a single offset;
#'   \code{blank_mode = "per_well"} subtracts each well's own blank value.
#' }
#'
#' @param inputDir Character scalar. Directory containing input PAP images.
#'
#' @param projectDir Character scalar. Directory used to store or read PAPArea
#' results.
#'
#' @param projectName Optional character scalar.
#'
#' @param roiZip Optional character scalar.
#'
#' @param wellOrder Character vector. Defaults to
#' \code{c("TL", "TM", "TR", "BL", "BM", "BR")}.
#'
#' @param imageJLoc Character scalar. Path to the ImageJ/Fiji executable.
#'
#' @param overwrite Logical.
#'
#' @param debug Logical.
#'
#' @param return_mode Character scalar. Either \code{"all"} or \code{"avg"}.
#'
#' @param assign_global Logical.
#'
#' @param run_macro Logical.
#'
#' @param normalization Character scalar. One of \code{"0"} (default) or
#' \code{"000blank"}. See Details.
#'
#' @param blank_pattern Character scalar (regex). Pattern matched against
#' \code{image_base} to auto-detect a blank-plate image in the input folder.
#' Defaults to \code{"^000blank"}. Only used when
#' \code{normalization = "000blank"}.
#'
#' @param blank_mode Character scalar. Either \code{"global"} (default) or
#' \code{"per_well"}. Only used when \code{normalization = "000blank"}.
#'
#' @param blank_csv Optional character scalar. Path to an external blank-plate
#' CSV. If provided and \code{normalization = "000blank"}, overrides any
#' auto-detected in-folder blank.
#'
#' @return
#' If \code{return_mode = "all"}, a named list with three elements:
#' \describe{
#'   \item{raw}{Annotated per-image, per-well results with \code{norm_*} columns.}
#'   \item{overlap_qc}{\code{NULL}; preserved for API consistency with
#'   \code{PAPDual()}.}
#'   \item{avg}{Averaged summary per sample-by-concentration.}
#' }
#'
#' If \code{return_mode = "avg"}, only the averaged summary data frame.
#'
#' @seealso \code{\link{PAPDual}}, \code{\link{PAPArea}}
#'
#' @examples
#' \dontrun{
#' # Default: FLC=0 per-sample normalization
#' res_0 <- PAPSingle(
#'   inputDir    = "path/to/F3_pap_images",
#'   projectDir  = "path/to/F3_project",
#'   projectName = "pap_f3_0",
#'   roiZip      = "path/to/papROISet.zip"
#' )
#'
#' # Compare to per-batch blank normalization without re-running the macro
#' res_blank <- PAPSingle(
#'   projectDir    = "path/to/F3_project",
#'   run_macro     = FALSE,
#'   normalization = "000blank"
#' )
#' }
#'
#' @export

PAPSingle <- function(inputDir = NULL,
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
                      normalization = c("0", "000blank"),
                      blank_pattern = "^000blank",
                      blank_mode = c("global", "per_well"),
                      blank_csv = NULL) {

  return_mode   <- match.arg(return_mode)
  normalization <- match.arg(normalization)
  blank_mode    <- match.arg(blank_mode)

  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Package 'dplyr' is required.")
  if (!requireNamespace("stringr", quietly = TRUE)) stop("Package 'stringr' is required.")
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Package 'tidyr' is required.")

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

  # 2) restore well-related columns
  allowed_wells <- c("TL", "TM", "TR", "BL", "BM", "BR")

  if ("well" %in% colnames(pap_raw)) {
    pap_raw$well <- as.character(pap_raw$well)
    pap_raw$well <- factor(pap_raw$well, levels = allowed_wells, ordered = FALSE)
    pap_raw$pap_step <- factor(as.character(pap_raw$well),
                               levels = wellOrder, ordered = TRUE)
    pap_raw$pap_index <- match(as.character(pap_raw$well), wellOrder)
  } else {
    stop("Input PAP result is missing `well` column.")
  }

  # 3) image -> basename
  pap_annot <- pap_raw %>%
    dplyr::mutate(
      image_raw  = as.character(image),
      image_base = stringr::str_remove(image_raw, "\\.[A-Za-z0-9]+$"),
      image_base = stringr::str_remove(image_base, "_crop$")
    )

  # 3a) auto-detect blank image(s)
  blank_internal <- pap_annot[0, , drop = FALSE]
  if (!is.null(blank_pattern) && !is.na(blank_pattern) && nzchar(blank_pattern)) {
    blank_match <- stringr::str_detect(pap_annot$image_base, blank_pattern)
    if (any(blank_match)) {
      blank_internal <- pap_annot[blank_match, , drop = FALSE]
      pap_annot      <- pap_annot[!blank_match, , drop = FALSE]
      message(sprintf("Detected %d in-folder blank image(s) matching '%s': %s",
                      length(unique(blank_internal$image_base)),
                      blank_pattern,
                      paste(unique(blank_internal$image_base), collapse = ", ")))
    }
  }

  # 3b) assign sample_id and plate for non-blank rows
  pap_annot <- pap_annot %>%
    dplyr::mutate(
      sample_id = image_base,
      plate     = "S"   # constant placeholder for API consistency with PAPDual
    )

  if (any(is.na(pap_annot$sample_id) | pap_annot$sample_id == "")) {
    bad_images <- unique(pap_annot$image_raw[is.na(pap_annot$sample_id) | pap_annot$sample_id == ""])
    stop("Failed to parse sample_id from these image names:\n",
         paste(bad_images, collapse = "\n"))
  }

  # 4) FLC concentration mapping
  pap_single_raw <- pap_annot %>%
    dplyr::mutate(
      well = as.character(well),
      flc = dplyr::case_when(
        well == "TL" ~ 0,
        well == "TM" ~ 8,
        well == "TR" ~ 12,
        well == "BL" ~ 16,
        well == "BM" ~ 24,
        well == "BR" ~ 32,
        TRUE ~ NA_real_
      )
    ) %>%
    dplyr::arrange(sample_id, flc)

  # 5) sanity check: each sample should have all 6 distinct wells
  well_check <- pap_single_raw %>%
    dplyr::distinct(sample_id, well) %>%
    dplyr::count(sample_id, name = "n_wells")
  if (any(well_check$n_wells != 6)) {
    bad_samples <- well_check$sample_id[well_check$n_wells != 6]
    warning("Some samples do not have all 6 wells (expected TL/TM/TR/BL/BM/BR):\n",
            paste(bad_samples, collapse = ", "))
  }

  # 6) ---- Normalization: add norm_* columns; never modify raw_* ----
  if (!is.null(blank_csv) && normalization != "000blank") {
    warning("blank_csv is ignored because normalization != '000blank'.")
  }

  if (normalization == "0") {
    # per-sample FLC=0 (TL) reference
    zero_ref <- pap_single_raw %>%
      dplyr::filter(flc == 0) %>%
      dplyr::group_by(sample_id) %>%
      dplyr::summarise(
        zero_mean   = mean(raw_mean,   na.rm = TRUE),
        zero_median = mean(raw_median, na.rm = TRUE),
        zero_intden = mean(raw_intden, na.rm = TRUE),
        .groups = "drop"
      )

    missing_zero <- setdiff(unique(pap_single_raw$sample_id), zero_ref$sample_id)
    if (length(missing_zero) > 0) {
      warning("normalization='0': no FLC=0 well data for: ",
              paste(missing_zero, collapse = ", "),
              "\nThese samples will have NA in norm_* columns.")
    }

    pap_single_raw <- pap_single_raw %>%
      dplyr::left_join(zero_ref, by = "sample_id") %>%
      dplyr::mutate(
        norm_mean   = raw_mean   - zero_mean,
        norm_median = raw_median - zero_median,
        norm_intden = raw_intden - zero_intden
      ) %>%
      dplyr::select(-zero_mean, -zero_median, -zero_intden)

    message("Normalization applied: '0' (per-sample FLC=0 TL well). ",
            "Note: norm_* will be negative at FLC > 0; magnitude reflects growth deficit vs no-drug control.")

  } else if (normalization == "000blank") {
    blank_df <- NULL
    blank_source <- NA_character_

    if (!is.null(blank_csv)) {
      if (!file.exists(blank_csv)) stop("blank_csv file not found: ", blank_csv)
      blank_df <- read.csv(blank_csv, stringsAsFactors = FALSE, check.names = FALSE)
      blank_needed <- c("well", "raw_mean", "raw_median", "raw_intden")
      blank_missing <- setdiff(blank_needed, colnames(blank_df))
      if (length(blank_missing) > 0) {
        stop("Blank CSV is missing columns: ", paste(blank_missing, collapse = ", "))
      }
      blank_source <- paste0("external CSV (", blank_csv, ")")
    } else if (nrow(blank_internal) > 0) {
      blank_df <- blank_internal
      blank_source <- paste0("in-folder: ",
                             paste(unique(blank_internal$image_base), collapse = ", "))
    } else {
      stop("normalization = '000blank' requested but no in-folder blank ",
           "(pattern '", blank_pattern, "') and no blank_csv provided.")
    }

    # diagnostic: 6-well variation
    blank_per_well <- blank_df %>%
      dplyr::group_by(well) %>%
      dplyr::summarise(b_mean = mean(raw_mean, na.rm = TRUE), .groups = "drop")
    bw_mean <- mean(blank_per_well$b_mean, na.rm = TRUE)
    bw_sd   <- stats::sd(blank_per_well$b_mean, na.rm = TRUE)
    bw_cv   <- if (!is.na(bw_mean) && bw_mean != 0) bw_sd / abs(bw_mean) else NA_real_

    message(sprintf("Blank source: %s", blank_source))
    message(sprintf("Blank 6-well grayscale: mean=%.2f, SD=%.2f, CV=%.1f%%",
                    bw_mean, bw_sd, ifelse(is.na(bw_cv), NA_real_, bw_cv * 100)))
    if (!is.na(bw_cv) && bw_cv > 0.05) {
      message("  Note: blank 6-well CV > 5% - consider blank_mode = 'per_well'.")
    }

    if (blank_mode == "global") {
      g_mean   <- mean(blank_df$raw_mean,   na.rm = TRUE)
      g_median <- mean(blank_df$raw_median, na.rm = TRUE)
      g_intden <- mean(blank_df$raw_intden, na.rm = TRUE)

      pap_single_raw <- pap_single_raw %>%
        dplyr::mutate(
          norm_mean   = raw_mean   - g_mean,
          norm_median = raw_median - g_median,
          norm_intden = raw_intden - g_intden
        )

      message(sprintf("Normalization applied: '000blank' / global (per-batch 6-well mean = %.2f).",
                      g_mean))

    } else if (blank_mode == "per_well") {
      blank_ref_pw <- blank_df %>%
        dplyr::group_by(well) %>%
        dplyr::summarise(
          z_mean   = mean(raw_mean,   na.rm = TRUE),
          z_median = mean(raw_median, na.rm = TRUE),
          z_intden = mean(raw_intden, na.rm = TRUE),
          .groups = "drop"
        )

      pap_single_raw <- pap_single_raw %>%
        dplyr::left_join(blank_ref_pw, by = "well") %>%
        dplyr::mutate(
          norm_mean   = raw_mean   - z_mean,
          norm_median = raw_median - z_median,
          norm_intden = raw_intden - z_intden
        ) %>%
        dplyr::select(-z_mean, -z_median, -z_intden)

      message("Normalization applied: '000blank' / per_well (per-batch, per-well-position).")
    }
  }

  # 7) averaging across replicate images per (sample_id, flc)
  avg_cols <- c("roi_area", "raw_mean", "raw_median", "raw_intden",
                "mean_gray", "median_gray", "sd_gray",
                "min_gray", "max_gray", "intden_gray", "cv_gray",
                "dark_frac_40", "dark_frac_60", "dark_frac_80",
                "norm_mean", "norm_median", "norm_intden")
  avg_cols <- intersect(avg_cols, colnames(pap_single_raw))

  pap_single_avg <- pap_single_raw %>%
    dplyr::group_by(sample_id, flc) %>%
    dplyr::summarise(
      dplyr::across(dplyr::all_of(avg_cols), ~ mean(.x, na.rm = TRUE)),
      n_plate = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::arrange(sample_id, flc)

  out <- list(
    raw        = pap_single_raw,
    overlap_qc = NULL,   # not applicable for single-plate; preserved for API consistency
    avg        = pap_single_avg
  )

  if (!is.null(projectName) && assign_global) {
    assign(projectName, out, envir = .GlobalEnv)
    message("PAPSingle completed. Result assigned to `", projectName, "`.")
  } else {
    message("PAPSingle completed.")
  }

  if (return_mode == "avg") {
    return(pap_single_avg)
  } else {
    return(out)
  }
}
