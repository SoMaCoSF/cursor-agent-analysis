# SVG Optimization Script for R Markdown outputs

library(xml2)
library(stringr)

optimize_svg <- function(svg_content) {
    # Parse SVG content
    svg_doc <- read_xml(svg_content)

    # Remove unnecessary attributes
    xml_attr(svg_doc, "xmlns:xlink") <- NULL

    # Optimize paths
    paths <- xml_find_all(svg_doc, "//path")
    for (path in paths) {
        d <- xml_attr(path, "d")
        if (!is.na(d)) {
            # Round decimal points to 2 places
            d <- str_replace_all(d, "\\d+\\.\\d+", function(x) {
                round(as.numeric(x), 2)
            })
            xml_attr(path, "d") <- d
        }
    }

    # Remove empty groups
    empty_groups <- xml_find_all(svg_doc, "//g[not(*)]")
    xml_remove(empty_groups)

    # Optimize style attributes
    style_elements <- xml_find_all(svg_doc, "//*[@style]")
    for (elem in style_elements) {
        style <- xml_attr(elem, "style")
        # Remove unnecessary spaces and semicolons
        style <- str_replace_all(style, "\\s*;\\s*", ";")
        style <- str_replace_all(style, ";$", "")
        xml_attr(elem, "style") <- style
    }

    # Convert back to string
    as.character(svg_doc)
}

# Function to process all SVG files in a directory
optimize_svg_files <- function(dir_path) {
    svg_files <- list.files(dir_path, pattern = "\\.svg$", full.names = TRUE)
    for (file in svg_files) {
        tryCatch(
            {
                content <- read_xml(file)
                optimized <- optimize_svg(content)
                write(optimized, file)
                cat(sprintf("Optimized: %s\n", basename(file)))
            },
            error = function(e) {
                cat(sprintf("Error processing %s: %s\n", basename(file), e$message))
            }
        )
    }
}
