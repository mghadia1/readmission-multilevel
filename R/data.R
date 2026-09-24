# Download, verify, and join the two CMS Provider Data files.
#
# Same snapshot and SHA-256 pins as the Python hospital-quality-analytics
# project, so both analyses describe the same data.

cms_base <- "https://data.cms.gov/provider-data/sites/default/files/resources"
cms_files <- list(
  hospital_general_information.csv = list(
    url = file.path(cms_base, "893c372430d9d71a1c52737d01239d47_1785189955/Hospital_General_Information.csv"),
    sha256 = "f874f09fef895a1ccf5bb7392dcbb2be05c9860339261b093fe00f0c1b013480"),
  hrrp_fy2026.csv = list(
    url = file.path(cms_base, "a171bc36c488d3e0dc33ec63abb469a6_1770163617/FY_2026_Hospital_Readmissions_Reduction_Program_Hospital.csv"),
    sha256 = "7e7915dd2751a1e59ac46dbc9194fb781e820962a04d47c31344ea2bb30c91f6")
)

verify_file <- function(path, expected) {
  actual <- digest::digest(file = path, algo = "sha256")
  if (!identical(actual, expected)) stop(sprintf("checksum mismatch for %s: %s", basename(path), actual))
  invisible(path)
}

download_cms <- function(destination = "data/raw") {
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  for (name in names(cms_files)) {
    path <- file.path(destination, name)
    if (!file.exists(path)) utils::download.file(cms_files[[name]]$url, path, mode = "wb", quiet = TRUE)
    verify_file(path, cms_files[[name]]$sha256)
  }
  file.path(destination, names(cms_files))
}

# CMS writes "N/A" and "Too Few to Report" into numeric columns; read every
# column as text and convert once, so a suppressed value becomes NA.
as_number <- function(x) suppressWarnings(as.numeric(x))

ownership_group <- function(ownership) {
  dplyr::case_when(
    startsWith(ownership, "Voluntary non-profit") ~ "Non-profit",
    ownership == "Proprietary" ~ "For-profit",
    ownership == "Physician" ~ "Physician-owned",
    TRUE ~ "Government"
  )
}

# One row per hospital x condition with a reportable excess readmission ratio.
# y = log(ERR): ratios are multiplicative, and on the log scale 0.9 and 1.11
# sit the same distance from 1.
build_ratios <- function(hrrp, hospitals) {
  hrrp |>
    dplyr::transmute(
      facility_id = `Facility ID`,
      condition = sub("^READM-30-(.*)-HRRP$", "\\1", `Measure Name`),
      err = as_number(`Excess Readmission Ratio`),
      discharges = as_number(`Number of Discharges`)
    ) |>
    dplyr::filter(!is.na(err), err > 0) |>
    dplyr::inner_join(
      hospitals |> dplyr::transmute(facility_id = `Facility ID`, state = State,
                                    hospital_type = `Hospital Type`,
                                    ownership = ownership_group(`Hospital Ownership`)),
      by = "facility_id"
    ) |>
    dplyr::mutate(y = log(err), condition = factor(condition), state = factor(state),
                  facility_id = factor(facility_id), ownership = factor(ownership))
}

load_ratios <- function(raw = "data/raw") {
  for (name in names(cms_files)) verify_file(file.path(raw, name), cms_files[[name]]$sha256)
  read <- function(name) utils::read.csv(file.path(raw, name), check.names = FALSE, colClasses = "character")
  build_ratios(read("hrrp_fy2026.csv"), read("hospital_general_information.csv"))
}
