# Academic profile site

Written in Markdown, built with [Quarto](https://quarto.org) and published with GitHub Pages. Every commit to `main` rebuilds the site automatically.

## Where things live

| To change | Edit |
|---|---|
| Front page | `index.qmd` |
| Publications, PDFs and icons | `publications.yml` (see below) |
| CV | `cv.qmd` |
| Media: press and podcasts | `media.yml` (the "New papers" block is automatic) |
| Teaching and supervision | `teaching.qmd` |
| Clinical tools | `tools.yml`; put downloadable files in `tools/` |
| Blog posts and book reviews | one folder per post in `posts/`; copy `posts/_template` |
| Colours and fonts | `styles.scss` |
| Menu, footer links | `_quarto.yml` |

All files can be edited directly on github.com (pencil icon), or locally in RStudio or Positron with `quarto preview`.

## Publications

`publications.yml` is updated every Monday and Thursday by the workflow "Update publications", which runs `scripts/update_publications.py` and then republishes the site. You can also start it by hand under Actions.

The script searches PubMed by author name, appends new papers and adds open-access PDF links through OpenAlex. Fields you add by hand are never overwritten. Titles listed in `scripts/skip.txt` (one per line) are never imported. Google Scholar is not used, because it blocks requests from GitHub; papers that are not in PubMed are added by hand.

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
