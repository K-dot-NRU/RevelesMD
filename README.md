# Academic profile site

Built with [Quarto](https://quarto.org) and published with GitHub Pages. Every commit to `main` rebuilds the site automatically.

## Where things live

| To change | Edit |
|---|---|
| Front page | `index.qmd` |
| Publications, PDFs and icons | `publications.yml` (see below) |
| CV | `cv.qmd` |
| Media: press and podcasts | `media.yml` (the "New papers" block is automatic) |
| Teaching and supervision | `teaching.qmd` |
| Blog posts and book reviews | one folder per post in `posts/`; copy `posts/_template` |
| Colours and fonts | `styles.scss` |
| Menu, footer links | `_quarto.yml` |

All files can be edited directly on github.com (pencil icon), or locally in RStudio or Positron with `quarto preview`.

## Publications

`publications.yml` is refreshed every Monday and Thursday by the workflow "Update publications from Google Scholar", which runs `R/update_publications.R` and then republishes the site. You can also start it by hand under Actions, or run the script locally with `source("R/update_publications.R")`.

The script reads the Scholar profile, refreshes citation counts, appends new papers and fills in DOIs and open-access PDF links through OpenAlex. It also searches PubMed by author name on every run, so new papers arrive even when Scholar refuses requests from GitHub's servers. Fields you add by hand are never overwritten. Titles listed in `R/scholar_skip.txt` (one per line) are never imported.

Per paper you can add:

| Field | Shows |
|---|---|
| `pdf` | PDF link. A URL, or a file placed in `pdfs/`, e.g. `pdfs/jensen2026.pdf` |
| `open_data` | Open data icon, linked to the URL |
| `open_code` | Open code icon, linked to the URL |
| `preregistration` | Preregistered icon, linked to the URL (or `true` without a link) |
| `preclinical` | Preclinical icon; the text (e.g. `mouse`) appears on hover |
| `hide: true` | Keeps the paper off the site |

## First-time setup on GitHub

1. Create a new public repository, ideally named `YOUR-USERNAME.github.io`.
2. Upload the contents of this folder (including the hidden `.github` folder) to the `main` branch.
3. In the repository: Settings, Pages, set Source to "GitHub Actions".
4. Wait for the "Publish site" workflow under Actions to finish. The site is then live at `https://YOUR-USERNAME.github.io`.
5. Add that address as `site-url` in `_quarto.yml`.
