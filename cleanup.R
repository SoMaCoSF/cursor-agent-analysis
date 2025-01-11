# Cleanup and Recovery Script

library(rmarkdown)
library(knitr)
library(xml2)
library(stringr)
library(dotenv)

# Source optimization and Imgur functions
source("optimize_svg.R")
source("imgur_uploader.R")

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

    # Step 2: Upload optimized SVGs to Imgur
    log_progress("Uploading SVGs to Imgur...")
    imgur_results <- upload_all_svgs()

    # Step 3: Update R Markdown to use Imgur links
    log_progress("Updating R Markdown with Imgur links...")
    update_rmd_with_imgur_links(imgur_results)

    # Step 4: Render R Markdown with optimizations
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

    # Step 5: Check output size
    output_file <- "agentic_context_analysis.html"
    if (file.exists(output_file)) {
        size <- check_file_size(output_file)
        log_progress(sprintf("Final HTML size: %.2f MB", size))
    }

    log_progress("Cleanup process completed")
}

# Function to update R Markdown with Imgur links
update_rmd_with_imgur_links <- function(imgur_results) {
    rmd_content <- readLines("agentic_context_analysis.Rmd")

    # Replace local SVG references with Imgur links
    for (name in names(imgur_results)) {
        result <- imgur_results[[name]]
        base_name <- tools::file_path_sans_ext(name)
        # Replace both markdown and HTML style references
        rmd_content <- gsub(
            sprintf("!\\[.*?\\]\\(%s\\)", name),
            sprintf("![%s](%s)", result$title, result$link),
            rmd_content
        )
        rmd_content <- gsub(
            sprintf('<img src="%s".*?>', name),
            sprintf('<img src="%s" alt="%s">', result$link, result$title),
            rmd_content
        )
    }

    writeLines(rmd_content, "agentic_context_analysis.Rmd")
    log_progress("Updated R Markdown with Imgur links")
}

# Run cleanup
cleanup_and_recover()
