# Keep publications.yml in step with Google Scholar
#
# Runs every week on GitHub (workflow "Update publications from Google Scholar")
# and can be run by hand from the top folder of the repository:
#   source("R/update_publications.R")
# Needs: install.packages(c("tidyverse", "scholar", "yaml", "jsonlite"))
#
# What it does
#   1. Reads the Google Scholar profile, refreshes citation counts and
#      appends papers that are not yet in publications.yml.
#      Scholar often refuses requests from GitHub's servers; the script
#      then carries on without it.
#   2. Searches PubMed for new papers by author name (always).
#   3. Looks up each paper in OpenAlex to fill in a missing DOI, journal,
#      full author list and a link to a legal open-access PDF.
# Entries are never removed, and fields already filled in by hand (pdf,
# open_data, open_code, preregistration, preclinical, hide ...) are never
# overwritten. Titles listed in R/scholar_skip.txt (one per line) are
# never imported.

library(tidyverse)
library(scholar)
library(yaml)
library(jsonlite)

scholar_id <- "iDfs_P4AAAAJ"
pubmed_query <- "Jensen KHR[Author] OR Reveles Jensen KH[Author] OR Reveles Jensen K[Author]"
pubs_file  <- "publications.yml"
skip_file  <- "R/scholar_skip.txt"

# Helpers -----------------------------------------------------------------

make_key <- function(x) {
  x |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]", "")
}

# Position of the closest existing title, or NA when nothing is close.
closest <- function(key, keys, tolerance = 0.15) {
  if (length(keys) == 0 || is.na(key) || key == "") return(NA_integer_)
  d <- as.vector(adist(key, keys)) / pmax(nchar(key), nchar(keys))
  if (min(d) <= tolerance) which.min(d) else NA_integer_
}

is_blank <- function(x) is.null(x) || length(x) == 0 || all(is.na(x)) || identical(x, "")

get_json <- function(url) {
  tryCatch(
    fromJSON(url, simplifyVector = FALSE),
    error = \(e) NULL
  )
}

openalex <- function(path) get_json(str_c("https://api.openalex.org/", path))

work_fields <- "id,doi,title,type,publication_date,publication_year,primary_location,best_oa_location,open_access,authorships"

# Turn one OpenAlex work into the fields used in publications.yml.
from_openalex <- function(w) {
  authors <- w$authorships |>
    map_chr(\(a) a$author$display_name %||% NA_character_) |>
    discard(is.na)
  list(
    title   = w$title,
    author  = str_c(authors, collapse = ", "),
    journal = w$primary_location$source$display_name,
    year    = w$publication_year,
    date    = w$publication_date,
    doi     = w$doi |> str_remove("^https?://doi.org/"),
    pdf     = w$best_oa_location$pdf_url,
    oa_url  = if (isTRUE(w$open_access$is_oa)) w$open_access$oa_url else NULL
  )
}

# Copy fields from `new` into `entry` only where `entry` has nothing yet.
fill_missing <- function(entry, new, fields) {
  for (f in fields) {
    if (is_blank(entry[[f]]) && !is_blank(new[[f]])) entry[[f]] <- new[[f]]
  }
  entry
}

# Read what we have -------------------------------------------------------

pubs      <- read_yaml(pubs_file)
skip_keys <- if (file.exists(skip_file)) make_key(read_lines(skip_file)) else character()
keys      <- \() map_chr(pubs, \(p) make_key(p$title))
this_year <- as.integer(format(Sys.Date(), "%Y"))
n_new     <- 0

# 1. Google Scholar -------------------------------------------------------

scholar_raw <- tryCatch(
  get_publications(scholar_id, flush = TRUE),
  error = \(e) {
    message("Google Scholar error: ", conditionMessage(e))
    NULL
  }
)
scholar_ok <- is.data.frame(scholar_raw) && nrow(scholar_raw) > 0

if (scholar_ok) {
  scholar_pubs <- scholar_raw |>
    as_tibble() |>
    mutate(across(where(is.factor), as.character)) |>
    filter(!is.na(year), !is.na(title), title != "") |>
    mutate(key = make_key(title)) |>
    distinct(key, .keep_all = TRUE) |>
    filter(!key %in% skip_keys)

  for (i in seq_len(nrow(scholar_pubs))) {
    s <- scholar_pubs[i, ]
    j <- closest(s$key, keys())
    if (!is.na(j)) {
      pubs[[j]]$citations     <- as.integer(s$cites)
      pubs[[j]]$scholar_pubid <- s$pubid
    } else {
      pubs[[length(pubs) + 1]] <- list(
        title         = s$title,
        author        = s$author,
        journal       = s$journal,
        year          = as.integer(s$year),
        # Scholar only gives the year; a paper from this year goes to the top
        date          = if (as.integer(s$year) >= this_year) as.character(Sys.Date()) else str_c(s$year, "-12-31"),
        citations     = as.integer(s$cites),
        scholar_pubid = s$pubid,
        url           = str_c(
          "https://scholar.google.com/citations?view_op=view_citation&user=", scholar_id,
          "&citation_for_view=", scholar_id, ":", s$pubid
        ),
        source        = "scholar"
      )
      n_new <- n_new + 1
      message("New from Google Scholar: ", s$title)
    }
  }
} else {
  message("::warning::Google Scholar did not answer this time; citation counts were not refreshed.")
}

# 2. PubMed ---------------------------------------------------------------

eutils <- "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
found  <- get_json(str_c(
  eutils, "esearch.fcgi?db=pubmed&retmode=json&retmax=200&term=",
  URLencode(pubmed_query, reserved = TRUE)
))
pmids     <- unlist(found$esearchresult$idlist) %||% character()
known     <- map_chr(pubs, \(p) as.character(p$pmid %||% ""))
new_pmids <- setdiff(pmids, known)

if (length(new_pmids) > 0) {
  summaries <- get_json(str_c(
    eutils, "esummary.fcgi?db=pubmed&retmode=json&id=", str_c(new_pmids, collapse = ",")
  ))$result

  for (id in new_pmids) {
    r <- summaries[[id]]
    if (is_blank(r$title)) next
    title <- r$title |> str_remove("\\.$")
    key   <- make_key(title)
    doi   <- r$articleids |>
      keep(\(a) identical(a$idtype, "doi")) |>
      map_chr("value") |>
      first()
    if (key %in% skip_keys) next

    dois <- map_chr(pubs, \(p) str_to_lower(p$doi %||% ""))
    j <- if (!is.na(doi) && str_to_lower(doi) %in% dois) match(str_to_lower(doi), dois) else closest(key, keys())

    if (!is.na(j)) {
      # Already listed (for example found on Scholar first): add the PubMed details
      pubs[[j]]$pmid <- id
      if (!is.na(doi) && is_blank(pubs[[j]]$doi)) {
        pubs[[j]]$doi <- doi
        pubs[[j]]$url <- str_c("https://doi.org/", doi)
      }
      next
    }

    pubs[[length(pubs) + 1]] <- compact(list(
      title   = title,
      author  = r$authors |> map_chr("name") |> str_c(collapse = ", "),
      journal = r$fulljournalname,
      year    = as.integer(str_sub(r$sortpubdate, 1, 4)),
      date    = r$sortpubdate |> str_sub(1, 10) |> str_replace_all("/", "-"),
      pmid    = id,
      doi     = if (is.na(doi)) NULL else doi,
      url     = if (is.na(doi)) str_c("https://pubmed.ncbi.nlm.nih.gov/", id, "/") else str_c("https://doi.org/", doi),
      source  = "pubmed"
    ))
    n_new <- n_new + 1
    message("New from PubMed: ", title)
  }
}

# 3. Fill in DOI, journal, authors and open-access PDF from OpenAlex ------

for (j in seq_along(pubs)) {
  p <- pubs[[j]]
  if (!is_blank(p$doi) && (!is_blank(p$pdf) || !is_blank(p$oa_url))) next

  w <- NULL
  if (!is_blank(p$doi)) {
    w <- openalex(str_c("works/doi:", p$doi, "?select=", work_fields))
  } else {
    res <- openalex(str_c(
      "works?search=", URLencode(p$title, reserved = TRUE),
      "&per-page=1&select=", work_fields
    ))
    hit <- if (length(res$results) > 0) res$results[[1]] else NULL
    if (!is.null(hit) && !is.na(closest(make_key(hit$title %||% ""), make_key(p$title), tolerance = 0.05))) w <- hit
  }
  if (is.null(w) || is_blank(w$title)) next

  new <- from_openalex(w)
  had_doi <- !is_blank(p$doi)
  p <- fill_missing(p, new, c("doi", "pdf", "oa_url"))
  if (!had_doi && !is_blank(p$doi)) {
    # A Scholar entry we could now identify: prefer the fuller record
    for (f in c("author", "journal", "date")) if (!is_blank(new[[f]])) p[[f]] <- new[[f]]
    p$url <- str_c("https://doi.org/", p$doi)
  }
  if (!is_blank(p$pdf)) p$oa_url <- NULL
  pubs[[j]] <- p
  Sys.sleep(0.2)
}

# Write -------------------------------------------------------------------

pubs <- pubs[order(map_chr(pubs, \(p) as.character(p$date %||% "1900-01-01")), decreasing = TRUE)]

header <- read_lines(pubs_file) |> keep(\(l) str_starts(l, "#"))
body   <- as.yaml(pubs, handlers = list(logical = verbatim_logical), line.sep = "\n")
write_lines(c(header, body), pubs_file)

message(
  "Done. Google Scholar ", if (scholar_ok) "answered" else "did not answer",
  "; ", n_new, " new paper(s); ", length(pubs), " in total."
)
