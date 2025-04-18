# This is very much a work in progress. Eventually this will be extracted into a
# package or maybe GitHub workflow commands.

# Set these variables ----------------------------------------------------------

# src_folder_name <- "american_idol"
# target_date <- "2024-09-10"

# Run these scripts ------------------------------------------------------------

## Sources and targets ---------------------------------------------------------

src_dir <- here::here("data", "curated", src_folder_name)
target_year <- lubridate::year(target_date)
target_week <- lubridate::week(target_date)
target_dir <- here::here("data", target_year, target_date)
fs::dir_create(target_dir)

## metadata --------------------------------------------------------------------

source(here::here("static", "templates", "metadata.R"), local = TRUE)

metadata <- read_metadata(fs::path(src_dir, "meta.yaml"))

dataset_files <- fs::dir_ls(src_dir, glob = "*.csv") |> unname()
dataset_filenames <- basename(dataset_files)

title <- metadata$title %||% stop("missing data")
data_title <- metadata$data_source$title %||% stop("missing data")
data_link <- metadata$data_source$url %||% stop("missing data")
article_title <- metadata$article$title %||% stop("missing data")
article_link <- metadata$article$url %||% stop("missing data")
credit <- metadata$credit$post
credit_github <- metadata$credit$github
if (length(credit_github)) {
  # Normalize in case they gave full path vs just handle or included @.
  credit_handle <- sub("github.com", "", credit_github) |> 
    sub("https://", "", x = _) |> 
    gsub("/", "", x = _) |> 
    sub("@", "", x = _)
  credit_github <- glue::glue("https://github.com/{credit_handle}")
  if (length(credit)) {
    credit <- glue::glue("[{credit}]({credit_github})")
  } else {
    credit <- glue::glue("@credit_handle")
  }
} 

## Copy files ------------------------------------------------------------------

fs::file_copy(fs::path(src_dir, "meta.yaml"), target_dir)

metadata$images |> 
  purrr::walk(
    \(image) {
      original_img_path <- fs::path(src_dir, image$file)
      original_img_size <- fs::file_size(original_img_path)
      if (original_img_size >= fs::fs_bytes("1MB")) {
        # Round down to make sure we're *under* 1MB. This isn't actually
        # guaranteed to work because image size isn't directly proportional to
        # file size, but it seems to err on the side of making things smaller
        # than they need to be.
        ratio <- floor(
          as.integer(fs::fs_bytes("1MB"))/as.integer(original_img_size)*100
        )
        magick::image_read(original_img_path) |> 
          magick::image_resize(
            magick::geometry_size_percent(ratio)
          ) |> 
          magick::image_write(fs::path(target_dir, image$file))
      } else {
        fs::file_copy(original_img_path, target_dir)
      }
    }
  )

fs::file_copy(dataset_files, target_dir)

## Create readme ---------------------------------------------------------------

source(here::here("static", "templates", "readme.R"), local = TRUE)

title_line <- glue::glue("# {title}")
intro <- read_piece(fs::path(src_dir, "intro.md"))
credit_line <- glue::glue("Thank you to {credit} for curating this week's dataset.")
if (length(credit_line)) {
  intro <- paste(intro, credit_line, sep = "\n\n")
}

the_data_template <- read_piece(here::here("static", "templates", "the_data.md"))
how_to_participate <- read_piece(here::here("static", "templates", "how_to_participate.md"))

data_dictionaries <- purrr::map(
  dataset_filenames,
  \(dataset_filename) {
    dictionary_filename <- fs::path_ext_set(dataset_filename, "md")
    dictionary <- fs::path(src_dir, dictionary_filename) |> 
      read_piece()
    dictionary_md <- glue::glue(
      "# `{dataset_filename}`",
      dictionary,
      .sep = "\n\n"
    )
  }
) |> 
  glue::glue_collapse(sep = "\n\n") |> unclass()

data_dictionary <- glue::glue(
  "### Data Dictionary",
  data_dictionaries,
  .sep = "\n\n"
)
cleaning_script <- paste(
  "### Cleaning Script\n",
  "```r",
  read_piece(fs::path(src_dir, "cleaning.R")),
  "```",
  sep = "\n"
)

the_data <- whisker::whisker.render(
  the_data_template,
  list(
    date = target_date,
    year = target_year,
    week = target_week,
    datasets = purrr::map(
      dataset_filenames,
      \(dataset_file) {
        list(
          dataset_name = fs::path_ext_remove(dataset_file),
          dataset_file = dataset_file
        )
      }
    )
  )
)

if (!stringr::str_ends(cleaning_script, "\n")) {
  cleaning_script <- paste0(cleaning_script, "\n")
}

paste(
  title_line,
  intro,
  the_data,
  how_to_participate,
  data_dictionary,
  cleaning_script,
  sep = "\n\n"
) |> 
  cat(file = fs::path(target_dir, "readme.md"))

## Update the YEAR readme ------------------------------------------------------

this_row_year <- glue::glue(
  "| {target_week}",
  "`{target_date}`",
  "[{title}]({target_date}/readme.md)",
  "[{data_title}]({data_link})",
  "[{article_title}]({article_link})",
  "",
  .sep = " | "
) |> unclass()
this_row_main <- glue::glue(
  "| {target_week}",
  "`{target_date}`",
  "[{title}](data/{target_year}/{target_date}/readme.md)",
  "[{data_title}]({data_link})",
  "[{article_title}]({article_link})",
  "",
  .sep = " | "
) |> unclass()

cat(
  this_row_year,
  "\n",
  file = here::here("data", target_year, "readme.md"),
  append = TRUE
)

main_readme <- readLines(here::here("README.md"))
dataset_lines <- stringr::str_which(
  main_readme,
  "^\\| "
)
dataset_lines_start <- dataset_lines[[1]]
dataset_lines_end <- dataset_lines[[length(dataset_lines)]]
main_readme_start <- main_readme[1:(dataset_lines_start - 1)]
main_readme_end <- main_readme[(dataset_lines_end + 1):length(main_readme)]
main_readme_datasets <- c(
  main_readme[dataset_lines], this_row_main
)
cat(
  main_readme_start,
  main_readme_datasets,
  main_readme_end,
  sep = "\n",
  file = here::here("README.md")
)

## Add information about these datasets to the tt_data_type.csv file -----------

tt_data_types_file <- here::here("static", "tt_data_type.csv")

these_types <- tibble::tibble(
  Week = target_week,
  Date = lubridate::ymd(target_date),
  year = target_year,
  data_files = dataset_filenames,
  data_type = "csv",
  delim = ","
)

tt_data_types <- dplyr::bind_rows(
  these_types,
  readr::read_csv(
    tt_data_types_file,
    col_types = "iDiccc"
  )
)

readr::write_csv(tt_data_types, tt_data_types_file)

# Delete the used directory ----------------------------------------------------
 
fs::dir_delete(src_dir)
