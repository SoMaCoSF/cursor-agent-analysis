# Imgur Upload and Gallery Management Script
library(httr)
library(jsonlite)
library(dotenv)

# Load environment variables
load_dot_env()

#' Upload SVG to Imgur
#' @param file_path Path to the SVG file
#' @param title Title for the image
#' @param description Description for the image
#' @return Imgur response including URL
upload_to_imgur <- function(file_path, title = NULL, description = NULL) {
    # Read the SVG file
    img_data <- readBin(file_path, "raw", file.info(file_path)$size)

    # Prepare the request
    url <- "https://api.imgur.com/3/image"
    headers <- add_headers(
        Authorization = paste("Client-ID", Sys.getenv("IMGUR_CLIENT_ID"))
    )

    # Build the body
    body <- list(
        image = base64enc::base64encode(img_data),
        type = "base64",
        name = basename(file_path),
        title = title,
        description = description
    )

    # Make the request
    response <- POST(
        url,
        headers,
        body = body,
        encode = "json"
    )

    # Parse response
    result <- fromJSON(rawToChar(response$content))

    if (response$status_code == 200) {
        log_progress(sprintf(
            "Successfully uploaded %s to Imgur: %s",
            basename(file_path),
            result$data$link
        ))
        return(result$data)
    } else {
        log_progress(sprintf(
            "Failed to upload %s: %s",
            basename(file_path),
            result$data$error
        ))
        return(NULL)
    }
}

#' Create or get Imgur album
#' @param title Album title
#' @param description Album description
#' @return Album ID
create_or_get_album <- function(title = "YOLOREN.AI Diagrams",
                                description = "Visualization gallery for YOLOREN.AI analysis") {
    # Check if we have an album ID
    album_id <- Sys.getenv("IMGUR_ALBUM_ID")
    if (nchar(album_id) > 0) {
        return(album_id)
    }

    # Create new album
    url <- "https://api.imgur.com/3/album"
    headers <- add_headers(
        Authorization = paste("Client-ID", Sys.getenv("IMGUR_CLIENT_ID"))
    )

    body <- list(
        title = title,
        description = description,
        privacy = "hidden"
    )

    response <- POST(
        url,
        headers,
        body = body,
        encode = "json"
    )

    result <- fromJSON(rawToChar(response$content))

    if (response$status_code == 200) {
        album_id <- result$data$id
        # Update .env with new album ID
        env_lines <- readLines(".env")
        env_lines[grep("IMGUR_ALBUM_ID=", env_lines)] <- paste0("IMGUR_ALBUM_ID=", album_id)
        writeLines(env_lines, ".env")
        return(album_id)
    } else {
        stop("Failed to create album")
    }
}

#' Upload all SVGs in directory to Imgur
#' @param dir_path Directory containing SVG files
#' @return List of uploaded image data
upload_all_svgs <- function(dir_path = ".") {
    # Get album ID
    album_id <- create_or_get_album()

    # Find all SVG files
    svg_files <- list.files(dir_path, pattern = "\\.svg$", full.names = TRUE)

    # Upload each file
    results <- list()
    for (file in svg_files) {
        title <- tools::file_path_sans_ext(basename(file))
        description <- sprintf("Generated diagram for YOLOREN.AI analysis - %s", title)

        result <- upload_to_imgur(file, title, description)
        if (!is.null(result)) {
            results[[basename(file)]] <- result
        }
    }

    # Create markdown gallery
    create_gallery_markdown(results)

    return(results)
}

#' Create markdown gallery
#' @param results List of upload results
#' @return NULL
create_gallery_markdown <- function(results) {
    output <- c(
        "# YOLOREN.AI Visualization Gallery\n",
        "Generated diagrams and visualizations for system analysis.\n\n"
    )

    for (name in names(results)) {
        result <- results[[name]]
        output <- c(
            output,
            sprintf("## %s\n", tools::file_path_sans_ext(name)),
            sprintf("![%s](%s)\n\n", result$title, result$link)
        )
    }

    writeLines(output, "gallery.md")
    log_progress("Created gallery markdown file")
}
