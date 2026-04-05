#' Process dual-plate PAPArea results and merge into a unified FLC gradient table
#'
#' @description
#' \code{PAPDual()} is a wrapper around \code{PAPArea()} for processing
#' PAP experiments performed on paired low- and high-concentration fluconazole
#' plates. It supports running the ImageJ/Fiji macro through \code{PAPArea()},
#' or directly reading an existing \code{pap_area_results.csv} file from
#' \code{projectDir}. The function parses sample identifiers and plate type
#' (\code{H} or \code{L}) from image names, maps wells to predefined fluconazole
#' concentrations, performs overlap quality control for duplicated concentrations,
#' and returns both raw and averaged PAP area summaries.
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
#' The function generates three outputs:
#' \itemize{
#'   \item \code{raw}: annotated per-image, per-well PAP results with parsed
#'   sample ID, plate type, and mapped fluconazole concentration;
#'   \item \code{overlap_qc}: comparison of duplicated concentrations shared
#'   between plates (0 and 8 \eqn{\mu g/mL});
#'   \item \code{avg}: merged sample-by-concentration table obtained by averaging
#'   duplicate concentrations across plates.
#' }
#'
#' If \code{projectName} is provided and \code{assign_global = TRUE}, the result
#' is also assigned into the global environment under the specified object name.
#'
#' @param inputDir Character scalar. Directory containing input PAP images.
#' Passed to \code{PAPArea()} when \code{run_macro = TRUE}. Can be \code{NULL}
#' if an existing \code{pap_area_results.csv} file is used.
#'
#' @param projectDir Character scalar. Directory used to store or read PAPArea
#' results, including \code{pap_area_results.csv}.
#'
#' @param projectName Optional character scalar. Name of the object to create in
#' the global environment when \code{assign_global = TRUE}. If \code{NULL}, no
#' object is assigned automatically.
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
#' @param debug Logical. Whether to print additional debugging information during
#' macro execution.
#'
#' @param return_mode Character scalar. Either \code{"all"} or \code{"avg"}.
#' If \code{"all"}, the function returns a list containing raw results, overlap
#' QC, and averaged results. If \code{"avg"}, only the averaged PAP table is
#' returned.
#'
#' @param assign_global Logical. Whether to assign the returned object into the
#' global environment when \code{projectName} is not \code{NULL}.
#'
#' @param run_macro Logical. If \code{TRUE}, run \code{PAPArea()} first. If
#' \code{FALSE}, skip macro execution and directly read an existing
#' \code{pap_area_results.csv} file from \code{projectDir}.
#'
#' @return
#' If \code{return_mode = "all"}, a named list with three elements:
#' \describe{
#'   \item{raw}{A data frame containing annotated PAP results for each image and
#'   well, including parsed sample ID, plate type, well identity, PAP order,
#'   and mapped fluconazole concentration.}
#'   \item{overlap_qc}{A data frame for duplicated concentrations shared between
#'   H and L plates (0 and 8), containing plate-specific values and their
#'   difference.}
#'   \item{avg}{A data frame summarising mean \code{percent_area},
#'   \code{roi_area}, and \code{pos_area} for each sample-by-concentration
#'   combination.}
#' }
#'
#' If \code{return_mode = "avg"}, only the averaged summary data frame is
#' returned.
#'
#' @seealso
#' \code{\link{PAPArea}}
#'
#' @examples
#' \dontrun{
#' # Run macro, process paired H/L plates, and return full output
#' res <- PAPDual(
#'   inputDir = "path/to/images",
#'   projectDir = "path/to/project",
#'   projectName = "pap_dual_res",
#'   roiZip = "path/to/papROISet.zip",
#'   imageJLoc = "/Applications/Fiji.app/ImageJ-linux64",
#'   return_mode = "all"
#' )
#'
#' # Read existing pap_area_results.csv only
#' avg_res <- PAPDual(
#'   inputDir = NULL,
#'   projectDir = "path/to/project",
#'   run_macro = FALSE,
#'   return_mode = "avg",
#'   assign_global = FALSE
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
                    run_macro = TRUE) {
  
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
  
  csv_file <- file.path(projectDir, "pap_area_results.csv")
  
  # 1) get PAPArea result
  if (run_macro) {
    pap_raw <- PAPArea(
      inputDir = inputDir,
      projectDir = projectDir,
      projectName = NULL,
      roiZip = roiZip,
      wellOrder = wellOrder,
      imageJLoc = imageJLoc,
      overwrite = overwrite,
      debug = debug
    )
    
    # If has no return, check the csv output
    if (is.null(pap_raw)) {
      if (!file.exists(csv_file)) {
        stop("PAPArea returned NULL and no pap_area_results.csv was found in projectDir.")
      }
      pap_raw <- read.csv(csv_file, stringsAsFactors = FALSE, check.names = FALSE)
    }
    
  } else {
    if (!file.exists(csv_file)) {
      stop("`run_macro = FALSE`, but no pap_area_results.csv was found in projectDir:\n", csv_file)
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
      image_raw = as.character(image),
      image_base = stringr::str_remove(image_raw, "\\.[A-Za-z0-9]+$"),
      image_base = stringr::str_remove(image_base, "_crop$"),
      sample_id = stringr::str_extract(image_base, "^[0-9]+"),
      plate = stringr::str_extract(image_base, "[HL]$")
    )
  
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
  
  # 6) overlap QC
  overlap_qc <- pap_dual_raw %>%
    dplyr::filter(flc %in% c(0, 8)) %>%
    dplyr::select(sample_id, plate, flc, percent_area) %>%
    tidyr::pivot_wider(
      names_from = plate,
      values_from = percent_area,
      names_prefix = "plate_"
    ) %>%
    dplyr::mutate(
      diff = plate_H - plate_L,
      abs_diff = abs(diff)
    ) %>%
    dplyr::arrange(sample_id, flc)
  
  # 7) combine duplicated concentrations
  pap_dual_avg <- pap_dual_raw %>%
    dplyr::group_by(sample_id, flc) %>%
    dplyr::summarise(
      percent_area = mean(percent_area, na.rm = TRUE),
      roi_area = mean(roi_area, na.rm = TRUE),
      pos_area = mean(pos_area, na.rm = TRUE),
      n_plate = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::arrange(sample_id, flc)
  
  out <- list(
    raw = pap_dual_raw,
    overlap_qc = overlap_qc,
    avg = pap_dual_avg
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
