#' Run Fiji/ImageJ PAP area quantification macro on a folder of images
#'
#' @description
#' \code{PAPArea} runs a Fiji/ImageJ macro stored in the package
#' to quantify PAP positive area percentage for 6-well plate images
#' using one common threshold per image.
#'
#' @param inputDir Path to the input image folder.
#' @param projectDir Path to the output folder where result files will be saved.
#' @param roiZip Path to the ROI zip file. If \code{NULL}, the function will try
#' to use the default ROI template \code{papROISet.zip} stored in the installed package.
#' @param imageJLoc Absolute path to Fiji/ImageJ app folder. If \code{NA},
#' the function will try common default locations on macOS.
#' @param debug Logical. Whether to print debug messages.
#'
#' @return
#' Invisibly returns the normalized output directory path.
#'
#' @export
PAPArea <- function(inputDir,
                    projectDir,
                    roiZip = NULL,
                    imageJLoc = NA,
                    debug = FALSE) {
  
  # check input directory
  if (missing(inputDir) || is.na(inputDir) || !dir.exists(inputDir)) {
    stop("`inputDir` does not exist.")
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
    message("DEBUG: script: ", script)
    message("DEBUG: IJarguments: ", IJarguments)
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
    # Prefer Fiji if present
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
  
  # optional file existence check
  csv_file <- file.path(projectDir, "pap_area_results.csv")
  
  if (success && file.exists(csv_file)) {
    message("PAPArea completed successfully. Results written to: ", projectDir)
  } else if (success && !file.exists(csv_file)) {
    message("PAPArea finished without command error, but `pap_area_results.csv` was not found in: ", projectDir)
  } else {
    message("PAPArea finished with errors (exit status: ", exit_status,
            "). Please check the Fiji/ImageJ output above.")
  }
  
  invisible(projectDir)
}