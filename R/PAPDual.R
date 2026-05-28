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
#' applies one of three normalization modes, and returns both raw and averaged
#' PAP summaries.
#'
#' @details
#' Image file names should follow a pattern such as \code{104H}, \code{104L},
#' or \code{104H_crop}, where:
#' \itemize{
#'   \item the leading portion is the sample identifier;
#'   \item the trailing \code{H} or \code{L} indicates the plate type;
#'   \item an optional \code{_crop} suffix is ignored during parsing.
#' }
#'
#' Fluconazole concentrations are assigned according to the well position:
#'
#' \strong{Low plate (\code{L})}
#' \itemize{
#'   \item \code{TL = 0},  \code{TM = 0.5}, \code{TR = 1}
#'   \item \code{BL = 2},  \code{BM = 4},   \code{BR = 8}
#' }
#'
#' \strong{High plate (\code{H})}
#' \itemize{
#'   \item \code{TL = 0},  \code{TM = 8},   \code{TR = 16}
#'   \item \code{BL = 32}, \code{BM = 64},  \code{BR = 128}
#' }
#'
#' \strong{Normalization modes (\code{normalization}).} All three modes add
#' \code{norm_mean}, \code{norm_median}, \code{norm_intden} columns; \code{raw_*}
#' columns are never modified, so the same dataset can be re-normalized by
#' rerunning with a different \code{normalization} value.
#' \itemize{
#'   \item \code{"highest"} (default) — per-sample subtraction of the H-plate
#'   BR well (128 ug/mL). This well consistently shows no growth and serves as
#'   a per-plate agar baseline. \code{norm_*} is typically positive.
#'   \item \code{"0"} — per-sample subtraction of the FLC=0 reference, computed
#'   as the average of the L-plate TL and H-plate TL wells (both = 0 ug/mL).
#'   Because FLC=0 is a growth maximum rather than a zero, \code{norm_*} is
#'   typically negative at FLC > 0 and its magnitude reflects growth deficit
#'   relative to the no-drug control.
#'   \item \code{"000blank"} — per-batch subtraction of a blank-plate reference,
#'   auto-detected from the input folder via \code{blank_pattern} (default
#'   \code{"^000blank"}) or supplied externally via \code{blank_csv}.
#'   \code{blank_mode = "global"} uses the 6-well mean (single offset for all
#'   wells); \code{blank_mode = "per_well"} subtracts each well's own value
#'   (captures spatial illumination differences).
#' }
#'
#' @param inputDir Character scalar. Directory containing input PAP images.
#' Passed to \code{PAPArea()} when \code{run_macro = TRUE}. Can be \code{NULL}
#' if an existing CSV file is used.
#'
#' @param projectDir Character scalar. Directory used to store or read PAPArea
#' results.
#'
#' @param projectName Optional character scalar. Name of the object to create
#' in the global environment when \code{assign_global = TRUE}.
#'
#' @param roiZip Optional character scalar. Path to the ROI zip file used by
#' \code{PAPArea()}.
#'
#' @param wellOrder Character vector specifying the expected order of wells.
#' Defaults to \code{c("TL", "TM", "TR", "BL", "BM", "BR")}.
#'
#' @param imageJLoc Character scalar. Path to the ImageJ/Fiji executable.
#'
#' @param overwrite Logical. Whether existing outputs should be overwritten.
#'
#' @param debug Logical. Whether to print additional debugging information.
#'
#' @param return_mode Character scalar. Either \code{"all"} or \code{"avg"}.
#'
#' @param assign_global Logical. Whether to assign the returned object into
#' the global environment when \code{projectName} is not \code{NULL}.
#'
#' @param run_macro Logical. If \code{TRUE}, run \code{PAPArea()} first.
#'
#' @param normalization Character scalar. One of \code{"highest"} (default),
#' \code{"0"}, or \code{"000blank"}. See Details.
#'
#' @param blank_pattern Character scalar (regex). Pattern matched against
#' \code{image_base} to auto-detect a blank-plate image in the input folder.
#' Defaults to \code{"^000blank"}. Only used when
#' \code{normalization = "000blank"}.
#'
#' @param blank_mode Character scalar. Either \code{"global"} (default; 6-well
#' mean of the blank as a single offset) or \code{"per_well"} (per-position
#' offset). Only used when \code{normalization = "000blank"}.
#'
#' @param blank_csv Optional character scalar. Path to an external blank-plate
#' \code{pap_feature_results.csv}. If provided and
#' \code{normalization = "000blank"}, overrides any auto-detected in-folder
#' blank.
#'
#' @return
#' If \code{return_mode = "all"}, a named list with three elements:
#' \describe{
#'   \item{raw}{Annotated per-image, per-well results with \code{norm_*} columns.}
#'   \item{overlap_qc}{Comparison of duplicated concentrations (0 and 8 ug/mL)
#'   between H and L plates, using \code{norm_mean}.}
#'   \item{avg}{Averaged summary per sample-by-concentration.}
#' }
#'
#' If \code{return_mode = "avg"}, only the averaged summary data frame.
#'
#' @seealso \code{\link{PAPSingle}}, \code{\link{PAPArea}}
#'
#' @examples
#' \dontrun{
#' # Default: highest-well (128 ug/mL) per-sample normalization
#' res <- PAPDual(
#'   inputDir    = "path/to/images",
#'   projectDir  = "path/to/project",
#'   projectName = "pap_dual_res",
#'   roiZip      = "path/to/papROISet.zip"
#' )
#'
#' # Compare alternatives without re-running the macro
#' res_0     <- PAPDual(projectDir = "path/to/project", run_macro = FALSE,
#'                      normalization = "0")
#' res_blank <- PAPDual(projectDir = "path/to/project", run_macro = FALSE,
#'                      normalization = "000blank")
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
                    normalization = c("highest", "0", "000blank"),
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

  # 3a) auto-detect blank image(s) BEFORE H/L parsing, so the blank isn't
  # treated as a malformed sample
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

  # 3b) parse H/L and sample_id for remaining (sample) images
  pap_annot <- pap_annot %>%
    dplyr::mutate(
      plate     = stringr::str_extract(image_base, "[HL]$"),
      sample_id = stringr::str_remove(image_base, "[HL]$")
    )

  not_plate <- is.na(pap_annot$plate) | !pap_annot$plate %in% c("H", "L")
  if (any(not_plate)) {
    warning(
      "Ignoring images that don't match H/L suffix or the blank pattern: ",
      paste(unique(pap_annot$image_raw[not_plate]), collapse = ", ")
    )
    pap_annot <- pap_annot[!not_plate, , drop = FALSE]
  }

  if (any(is.na(pap_annot$sample_id) | pap_annot$sample_id == "")) {
    bad_images <- unique(pap_annot$image_raw[is.na(pap_annot$sample_id) | pap_annot$sample_id == ""])
    stop(
      "Failed to parse sample_id from these image names:\n",
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

  # 6) ---- Normalization: add norm_* columns; never modify raw_* ----
  if (!is.null(blank_csv) && normalization != "000blank") {
    warning("blank_csv is ignored because normalization != '000blank'.")
  }

  if (normalization == "highest") {
    # per-sample H-plate BR (128 ug/mL)
    zero_ref <- pap_dual_raw %>%
      dplyr::filter(plate == "H", well == "BR") %>%
      dplyr::select(sample_id,
                    zero_mean   = raw_mean,
                    zero_median = raw_median,
                    zero_intden = raw_intden)

    missing_zero <- setdiff(unique(pap_dual_raw$sample_id), zero_ref$sample_id)
    if (length(missing_zero) > 0) {
      warning("normalization='highest': no H-plate BR (128 ug/mL) data for: ",
              paste(missing_zero, collapse = ", "),
              "\nThese samples will have NA in norm_* columns.")
    }

    pap_dual_raw <- pap_dual_raw %>%
      dplyr::left_join(zero_ref, by = "sample_id") %>%
      dplyr::mutate(
        norm_mean   = raw_mean   - zero_mean,
        norm_median = raw_median - zero_median,
        norm_intden = raw_intden - zero_intden
      ) %>%
      dplyr::select(-zero_mean, -zero_median, -zero_intden)

    message("Normalization applied: 'highest' (per-sample H-plate BR = 128 ug/mL).")

  } else if (normalization == "0") {
    # per-sample FLC=0 reference (average of L-plate TL and H-plate TL)
    zero_ref <- pap_dual_raw %>%
      dplyr::filter(flc == 0) %>%
      dplyr::group_by(sample_id) %>%
      dplyr::summarise(
        zero_mean   = mean(raw_mean,   na.rm = TRUE),
        zero_median = mean(raw_median, na.rm = TRUE),
        zero_intden = mean(raw_intden, na.rm = TRUE),
        .groups = "drop"
      )

    missing_zero <- setdiff(unique(pap_dual_raw$sample_id), zero_ref$sample_id)
    if (length(missing_zero) > 0) {
      warning("normalization='0': no FLC=0 well data for: ",
              paste(missing_zero, collapse = ", "),
              "\nThese samples will have NA in norm_* columns.")
    }

    pap_dual_raw <- pap_dual_raw %>%
      dplyr::left_join(zero_ref, by = "sample_id") %>%
      dplyr::mutate(
        norm_mean   = raw_mean   - zero_mean,
        norm_median = raw_median - zero_median,
        norm_intden = raw_intden - zero_intden
      ) %>%
      dplyr::select(-zero_mean, -zero_median, -zero_intden)

    message("Normalization applied: '0' (per-sample FLC=0 average across H and L plates). ",
            "Note: norm_* will be negative at FLC > 0; magnitude reflects growth deficit vs no-drug control.")

  } else if (normalization == "000blank") {
    # per-batch blank reference
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

    # diagnostic: 6-well variation of the blank
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

      pap_dual_raw <- pap_dual_raw %>%
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

      pap_dual_raw <- pap_dual_raw %>%
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

  # 7) overlap QC on duplicated concentrations (0 and 8 ug/mL) using norm_mean
  overlap_qc <- pap_dual_raw %>%
    dplyr::filter(flc %in% c(0, 8)) %>%
    dplyr::select(sample_id, plate, flc, norm_mean) %>%
    tidyr::pivot_wider(
      names_from   = plate,
      values_from  = norm_mean,
      names_prefix = "plate_"
    ) %>%
    dplyr::mutate(
      diff     = plate_H - plate_L,
      abs_diff = abs(diff)
    ) %>%
    dplyr::arrange(sample_id, flc)

  # 8) averaging across plates / replicates per (sample_id, flc)
  avg_cols <- c("roi_area", "raw_mean", "raw_median", "raw_intden",
                "mean_gray", "median_gray", "sd_gray",
                "min_gray", "max_gray", "intden_gray", "cv_gray",
                "dark_frac_40", "dark_frac_60", "dark_frac_80",
                "norm_mean", "norm_median", "norm_intden")
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
