#' Run Fiji/ImageJ PAP area quantification macro on a folder of images
#'
#' @description
#' \code{PAPArea} runs a Fiji/ImageJ macro stored in the package
#' to quantify PAP positive area percentage for 6-well plate images
#' using one common threshold per image, then reads the output CSV back into R.
#'
#' @param inputDir Path to the input image folder.
#' @param projectDir Path to the output folder where result files will be saved.
#' @param projectName Optional character string. If provided, the resulting data
#' frame will also be assigned into the global environment using this name.
#' @param roiZip Path to the ROI zip file. If \code{NULL}, the function will try
#' to use the default ROI template \code{papROISet.zip} stored in the installed package.
#' @param wellOrder Character vector of length 6 defining the true PAP gradient
#' order from the lowest to the highest antibiotic concentration. The values must
#' be a permutation of \code{c("TL", "TM", "TR", "BL", "BM", "BR")}. The default is
#' \code{c("TL", "TM", "TR", "BL", "BM", "BR")}.
#' @param imageJLoc Absolute path to Fiji/ImageJ app folder. If \code{NA},
#' the function will try common default locations on macOS.
#' @param overwrite Logical. Whether to overwrite existing PAP output files
#' in \code{projectDir}. Default is \code{FALSE}.
#' @param debug Logical. Whether to print debug messages.
#'
#' @return
#' A data frame containing PAP area quantification results.
#' In addition to the raw \code{well} column from Fiji output, the returned data
#' frame contains:
#' \itemize{
#'   \item \code{pap_step}: ordered factor representing PAP gradient order
#'   \item \code{pap_index}: integer index from 1 to 6 for PAP gradient order
#' }
#'
#' @export
PAPArea <- function(inputDir,
                    projectDir,
                    projectName = NULL,
                    roiZip = NULL,
                    wellOrder = c("TL", "TM", "TR", "BL", "BM", "BR"),
                    imageJLoc = NA,
                    overwrite = FALSE,
                    debug = FALSE) {
  
  # check input directory
  if (missing(inputDir) || is.na(inputDir) || !dir.exists(inputDir)) {
    stop("`inputDir` does not exist.")
  }
  
  if (missing(projectDir) || is.na(projectDir)) {
    stop("`projectDir` must be provided.")
  }
  
  if (!is.logical(overwrite) || length(overwrite) != 1 || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.")
  }
  
  if (!is.null(projectName)) {
    if (length(projectName) != 1 || is.na(projectName) || !nzchar(projectName)) {
      stop("`projectName` must be a non-empty character string.")
    }
  }
  
  allowed_wells <- c("TL", "TM", "TR", "BL", "BM", "BR")
  if (!is.character(wellOrder) || length(wellOrder) != 6 ||
      any(is.na(wellOrder)) || any(!nzchar(wellOrder))) {
    stop("`wellOrder` must be a character vector of length 6 with no empty values.")
  }
  if (length(unique(wellOrder)) != 6) {
    stop("`wellOrder` must contain 6 unique values.")
  }
  if (!setequal(wellOrder, allowed_wells)) {
    stop("`wellOrder` must be a permutation of c(\"TL\", \"TM\", \"TR\", \"BL\", \"BM\", \"BR\").")
  }
  
  # normalize paths
  inputDir <- normalizePath(inputDir, winslash = "/", mustWork = TRUE)
  
  if (!dir.exists(projectDir)) {
    dir.create(projectDir, recursive = TRUE, showWarnings = FALSE)
  }
  projectDir <- normalizePath(projectDir, winslash = "/", mustWork = FALSE)
  
  # locate default ROI template if not provided
  if (is.null(roiZip)) {
    roiZip <- system.file("papROISet.zip", package = "diskImageR")
    if (roiZip == "") {
      stop("Could not find default ROI template `papROISet.zip` in installed package. Please re-install the package.")
    }
  } else {
    if (length(roiZip) != 1 || is.na(roiZip) || !file.exists(roiZip)) {
      stop("`roiZip` does not exist.")
    }
    roiZip <- normalizePath(roiZip, winslash = "/", mustWork = TRUE)
  }
  
  # ensure trailing slash for macro-side compatibility
  if (substr(inputDir, nchar(inputDir), nchar(inputDir)) != "/") {
    inputDir <- paste0(inputDir, "/")
  }
  if (substr(projectDir, nchar(projectDir), nchar(projectDir)) != "/") {
    projectDir <- paste0(projectDir, "/")
  }
  
  # existing output check
  csv_file <- file.path(projectDir, "pap_area_results.csv")
  qc_dir <- file.path(projectDir, "qc")
  mask_dir <- file.path(projectDir, "mask")
  
  existing_outputs <- c(
    csv_file[file.exists(csv_file)],
    qc_dir[dir.exists(qc_dir)],
    mask_dir[dir.exists(mask_dir)]
  )
  
  if (length(existing_outputs) > 0) {
    if (!overwrite) {
      stop(
        "Existing PAP output was found in `projectDir`. ",
        "Set `overwrite = TRUE` to remove old results before running again.\n",
        "Existing paths:\n",
        paste(existing_outputs, collapse = "\n")
      )
    } else {
      if (file.exists(csv_file)) file.remove(csv_file)
      if (dir.exists(qc_dir)) unlink(qc_dir, recursive = TRUE, force = TRUE)
      if (dir.exists(mask_dir)) unlink(mask_dir, recursive = TRUE, force = TRUE)
    }
  }
  
  # locate macro inside installed package
  macro_file <- "pap.ijm"
  script <- system.file(macro_file, package = "diskImageR")
  
  if (script == "") {
    stop("Could not find macro file in package: ", macro_file,
         ". Please re-install the package.")
  }
  
  IJarguments <- paste(inputDir, projectDir, roiZip, sep = "*")
  
  if (debug) {
    message("DEBUG: inputDir: ", inputDir)
    message("DEBUG: projectDir: ", projectDir)
    message("DEBUG: roiZip: ", roiZip)
    message("DEBUG: wellOrder (low -> high): ", paste(wellOrder, collapse = ", "))
    message("DEBUG: script: ", script)
    message("DEBUG: IJarguments: ", IJarguments)
    message("DEBUG: overwrite: ", overwrite)
  }
  
  success <- FALSE
  exit_status <- NA_integer_
  
  if (.Platform$OS.type == "windows") {
    knownIJLoc <- FALSE
    
    if ("ImageJ.exe" %in% dir("C:\\progra~1\\ImageJ\\")) {
      cmd <- "C:\\progra~1\\ImageJ\\ImageJ.exe"
      knownIJLoc <- TRUE
    }
    if ("ImageJ.exe" %in% dir("C:\\Program Files (x86)\\ImageJ\\")) {
      cmd <- '"C:\\Program Files (x86)\\ImageJ\\ImageJ.exe"'
      knownIJLoc <- TRUE
    }
    if (!is.na(imageJLoc) && dir.exists(imageJLoc) &&
        "ImageJ.exe" %in% dir(imageJLoc)) {
      cmd <- file.path(imageJLoc, "ImageJ.exe")
      knownIJLoc <- TRUE
    }
    
    if (!knownIJLoc) {
      stop("ImageJ is not in expected location. Please specify `imageJLoc`.")
    }
    
    args <- paste("-macro", shQuote(script), shQuote(IJarguments))
    res <- shell(paste(cmd, args), wait = TRUE, intern = TRUE)
    
    exit_status <- attr(res, "status")
    if (is.null(exit_status)) exit_status <- 0L
    success <- identical(exit_status, 0L)
    
    if (debug && length(res) > 0) {
      cat("===== Fiji/ImageJ stdout/stderr =====\n")
      cat(paste(res, collapse = "\n"), "\n")
      cat("=====================================\n")
    }
    
  } else {
    fiji_app <- "/Applications/Fiji/Fiji.app"
    if (dir.exists(fiji_app)) {
      app_path <- fiji_app
    } else if (!is.na(imageJLoc) && dir.exists(imageJLoc)) {
      app_path <- normalizePath(imageJLoc, winslash = "/", mustWork = FALSE)
    } else {
      possible_locs <- c(
        "/Applications/Fiji.app",
        "/Applications/ImageJ.app",
        "/Applications/ImageJ/ImageJ.app"
      )
      app_path <- possible_locs[dir.exists(possible_locs)][1]
    }
    
    if (is.na(app_path) || !dir.exists(app_path)) {
      stop("Could not find Fiji/ImageJ application. Please specify `imageJLoc`.")
    }
    
    if (!grepl("\\.app$", app_path) && dir.exists(file.path(app_path, "Fiji.app"))) {
      app_path <- file.path(app_path, "Fiji.app")
    }
    
    macos_dir <- file.path(app_path, "Contents", "MacOS")
    
    candidates <- c(
      "fiji-macos-arm64",
      "fiji-macos",
      "fiji-macos-x64",
      "jaunch-macos-arm64",
      "jaunch-macos",
      "jaunch-macos-x64",
      "ImageJ-macosx",
      "ImageJ",
      "JavaApplicationStub",
      "ImageJ-linux"
    )
    
    binary_path <- NA_character_
    if (debug) message("Searching for ImageJ/Fiji executable in: ", macos_dir)
    
    for (exe in candidates) {
      full_path <- file.path(macos_dir, exe)
      if (debug) message("Checking candidate executable: ", exe)
      if (file.exists(full_path)) {
        binary_path <- full_path
        if (debug) message("Selected executable: ", exe)
        break
      }
    }
    
    if (is.na(binary_path)) {
      stop("Found app at ", app_path, " but no runnable launcher in ", macos_dir)
    }
    
    if (debug) message("Executing Fiji/ImageJ at: ", binary_path)
    
    res <- system2(
      binary_path,
      args = c("-macro", script, IJarguments),
      stdout = TRUE,
      stderr = TRUE,
      wait = TRUE
    )
    
    exit_status <- attr(res, "status")
    if (is.null(exit_status)) exit_status <- 0L
    success <- identical(exit_status, 0L)
    
    if (debug) {
      cat("===== Fiji/ImageJ stdout/stderr =====\n")
      cat(paste(res, collapse = "\n"), "\n")
      cat("=====================================\n")
    }
  }
  
  if (!success) {
    stop("PAPArea finished with errors (exit status: ", exit_status,
         "). Please check the Fiji/ImageJ output above.")
  }
  
  if (!file.exists(csv_file)) {
    stop("PAPArea finished without command error, but `pap_area_results.csv` was not found in: ",
         projectDir)
  }
  
  pap_df <- read.csv(csv_file, stringsAsFactors = FALSE, check.names = FALSE)
  
  expected_cols <- c("image", "well", "roi_area", "pos_area", "percent_area")
  missing_cols <- setdiff(expected_cols, colnames(pap_df))
  if (length(missing_cols) > 0) {
    warning("Output CSV is missing expected columns: ",
            paste(missing_cols, collapse = ", "))
  }
  
  if ("well" %in% colnames(pap_df)) {
    unknown_wells <- setdiff(unique(pap_df$well), allowed_wells)
    if (length(unknown_wells) > 0) {
      warning("Unexpected values found in Fiji output `well`: ",
              paste(unknown_wells, collapse = ", "))
    }
    
    # keep raw spatial well position from Fiji output
    pap_df$well <- factor(pap_df$well, levels = allowed_wells, ordered = FALSE)
    
    # PAP gradient order (low concentration -> high concentration)
    pap_df$pap_step <- factor(as.character(pap_df$well),
                              levels = wellOrder,
                              ordered = TRUE)
    
    # numeric PAP order index for downstream plotting / AUC
    pap_df$pap_index <- match(as.character(pap_df$well), wellOrder)
  }
  
  if (!is.null(projectName)) {
    assign(projectName, pap_df, envir = .GlobalEnv)
    message("PAPArea completed successfully. Result assigned to `", projectName,
            "` and written to: ", projectDir)
  } else {
    message("PAPArea completed successfully. Results written to: ", projectDir)
  }
  
}