# Cleanup and Recovery Script

library(rmarkdown)
library(knitr)
library(xml2)
library(stringr)

# Source optimization functions
source("optimize_svg.R")

# Function to check file size
check_file_size <- function(file_path) {
    size_mb <- file.size(file_path) / 1024 / 1024
    cat(sprintf("File size: %.2f MB\n", size_mb))
    return(size_mb)
}

# Function to log progress
log_progress <- function(message) {
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    log_entry <- sprintf("[%s] %s\n", timestamp, message)
    cat(log_entry)
    write(log_entry, "recovery_log.md", append = TRUE)
}

# Main cleanup function
cleanup_and_recover <- function() {
    log_progress("Starting cleanup and recovery process")

    # Step 1: Optimize existing SVG files
    log_progress("Optimizing SVG files...")
    optimize_svg_files(".")

    # Step 2: Render R Markdown with optimizations
    log_progress("Rendering R Markdown document...")
    tryCatch(
        {
            render("agentic_context_analysis.Rmd",
                output_format = "html_document",
                quiet = TRUE
            )
            log_progress("Successfully rendered document")
        },
        error = function(e) {
            log_progress(sprintf("Error rendering document: %s", e$message))
        }
    )

    # Step 3: Check output size
    output_file <- "agentic_context_analysis.html"
    if (file.exists(output_file)) {
        size <- check_file_size(output_file)
        log_progress(sprintf("Final HTML size: %.2f MB", size))
    }

    log_progress("Cleanup process completed")
}

# Run cleanup
cleanup_and_recover()
