test_that("CMS rows are parsed: suppressed values dropped, conditions and owners named", {
  hrrp <- data.frame(
    `Facility ID` = c("010001", "010001", "010002", "010003"),
    `Measure Name` = c("READM-30-HF-HRRP", "READM-30-HIP-KNEE-HRRP", "READM-30-PN-HRRP", "READM-30-AMI-HRRP"),
    `Excess Readmission Ratio` = c("1.0500", "N/A", "0.9000", "1.2000"),
    `Number of Discharges` = c("250", "N/A", "Too Few to Report", "90"),
    check.names = FALSE)
  hospitals <- data.frame(
    `Facility ID` = c("010001", "010002"), State = c("AZ", "CA"),
    `Hospital Type` = "Acute Care Hospitals",
    `Hospital Ownership` = c("Voluntary non-profit - Private", "Proprietary"),
    check.names = FALSE)
  d <- build_ratios(hrrp, hospitals)
  expect_equal(nrow(d), 2)                                   # N/A ratio dropped; 010003 has no hospital row
  expect_equal(as.character(d$condition), c("HF", "PN"))
  expect_equal(as.character(d$ownership), c("Non-profit", "For-profit"))
  expect_equal(d$y, log(c(1.05, 0.90)))
  expect_true(is.na(d$discharges[2]))                        # "Too Few to Report" becomes NA, row kept
})

test_that("ownership groups cover every CMS label", {
  expect_equal(ownership_group(c("Voluntary non-profit - Church", "Proprietary", "Physician",
                                 "Government - Local", "Tribal")),
               c("Non-profit", "For-profit", "Physician-owned", "Government", "Government"))
})

test_that("a tampered file fails the checksum", {
  path <- tempfile(fileext = ".csv")
  writeLines("tampered", path)
  expect_error(verify_file(path, cms_files$hrrp_fy2026.csv$sha256), "checksum mismatch")
})
