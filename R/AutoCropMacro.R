#' Run Fiji/ImageJ auto-crop macro on a folder of images
#'
#' @description
#' \code{AutoCropMacro} runs a Fiji/ImageJ macro stored in the package
#' to automatically crop plate images from a black background.
#'
#' @param photoDir Path to the input image folder.
#' @param outputDir Path to the output folder where cropped images will be saved.
#' @param imageJLoc Absolute path to Fiji/ImageJ app folder. If \code{NA},
#' the function will try common default locations on macOS.
#' @param macroName Name of the macro file inside the installed package.
#' Defaults to \code{"auto_crop.ijm"}.
#' @param debug Logical. Whether to print debug messages.
#'
#' @return
#' Invisibly returns the normalized output directory path.
#'
#' @export

AutoCropMacro <- function(photoDir,
                          outputDir,
                          imageJLoc = NA,
                          macroName = "auto_crop.ijm",
                          debug = FALSE) {
  
  # check input directory
  if (missing(photoDir) || is.na(photoDir) || !dir.exists(photoDir)) {
    stop("`photoDir` does not exist.")
  }
  
  # normalize paths
  photoDir  <- normalizePath(photoDir, winslash = "/", mustWork = TRUE)
  
  if (!dir.exists(outputDir)) {
    dir.create(outputDir, recursive = TRUE, showWarnings = FALSE)
  }
  outputDir <- normalizePath(outputDir, winslash = "/", mustWork = FALSE)
  
  # ensure trailing slash for macro-side compatibility
  if (substr(photoDir, nchar(photoDir), nchar(photoDir)) != "/") {
    photoDir <- paste0(photoDir, "/")
  }
  if (substr(outputDir, nchar(outputDir), nchar(outputDir)) != "/") {
    outputDir <- paste0(outputDir, "/")
  }
  
  # locate macro inside installed package
  # If your macro is stored elsewhere in the package, adjust this line.
  script <- system.file(macroName, package = "diskImageR")
  
  if (script == "") {
    stop("Could not find macro file in package: ", macroName,
         ". Please check where `auto_crop.ijm` is installed.")
  }
  
  IJarguments <- paste(photoDir, outputDir, sep = "*")
  
  if (debug) {
    message("DEBUG: photoDir: ", photoDir)
    message("DEBUG: outputDir: ", outputDir)
    message("DEBUG: script: ", script)
    message("DEBUG: IJarguments: ", IJarguments)
  }
  
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
    if (!is.na(imageJLoc) && "ImageJ.exe" %in% dir(imageJLoc)) {
      cmd <- file.path(imageJLoc, "ImageJ.exe")
      knownIJLoc <- TRUE
    }
    
    if (!knownIJLoc) {
      stop("ImageJ is not in expected location. Please specify `imageJLoc`.")
    }
    
    args <- paste("-macro", shQuote(script), shQuote(IJarguments))
    shell(paste(cmd, args), wait = TRUE, intern = TRUE)
    
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
    
    binary_path <- NA
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
      stderr = TRUE
    )
    
    if (debug) {
      cat("===== Fiji/ImageJ stdout/stderr =====\n")
      cat(paste(res, collapse = "\n"), "\n")
      cat("=====================================\n")
    }
  }
  
  invisible(outputDir)
}