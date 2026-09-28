simulate_hospitals <- function(seed = 1, sd_state = 0.02, sd_hospital = 0.04, sd_residual = 0.08,
                               states = 25, max_hospitals = 60) {
  set.seed(seed)
  conditions <- c("AMI", "CABG", "COPD", "HF", "HIP-KNEE", "PN")
  rows <- list()
  for (s in seq_len(states)) {
    u_s <- rnorm(1, 0, sd_state)
    n_h <- if (s <= 5) sample(3:8, 1) else sample(20:max_hospitals, 1)   # a few small states
    for (h in seq_len(n_h)) {
      u_h <- rnorm(1, 0, sd_hospital)
      owner <- sample(c("Non-profit", "For-profit", "Government"), 1, prob = c(0.6, 0.25, 0.15))
      for (cnd in sample(conditions, sample(2:6, 1))) {
        rows[[length(rows) + 1]] <- data.frame(
          facility_id = sprintf("S%02dH%03d", s, h), state = sprintf("S%02d", s), condition = cnd,
          ownership = owner, y = u_s + u_h + rnorm(1, 0, sd_residual) + ifelse(owner == "For-profit", 0.02, 0))
      }
    }
  }
  d <- do.call(rbind, rows)
  d$err <- exp(d$y); d$discharges <- NA_real_
  transform(d, facility_id = factor(facility_id), state = factor(state),
            condition = factor(condition), ownership = factor(ownership))
}

test_that("variance shares recover the simulated levels", {
  d <- simulate_hospitals(sd_state = 0.03, sd_hospital = 0.05, sd_residual = 0.08)
  shares <- variance_shares(fit_mixed(d, heteroscedastic = FALSE))
  truth <- c(0.03, 0.05, 0.08)^2 / sum(c(0.03, 0.05, 0.08)^2)
  # absolute error in each share under 0.05 (testthat 3's tolerance is relative, so check directly)
  expect_lt(max(abs(unname(shares$share) - truth)), 0.05)
  expect_lt(abs(shares$same_hospital_correlation - (truth[1] + truth[2])), 0.05)
})

test_that("the hospital level is detected when it exists and not when it does not", {
  with_hospital <- level_tests(simulate_hospitals(seed = 2, sd_hospital = 0.04))
  without <- level_tests(simulate_hospitals(seed = 3, sd_hospital = 0, sd_state = 0))
  expect_lt(with_hospital["add_hospital", "p"], 1e-6)
  expect_gt(without["add_hospital", "p"], 0.01)
})

test_that("ownership effect is recovered and reported for every non-reference group", {
  d <- simulate_hospitals(seed = 4)
  effects <- ownership_effects(fit_mixed(d), d)
  expect_setequal(effects$term, c("Government", "Non-profit"))
  # the simulation puts for-profit (the reference) 2% higher, so the others are about -2%
  expect_lt(abs(effects$mixed_pct[effects$term == "Non-profit"] - (-2)), 0.8)
})

test_that("the hold-out takes one condition from each hospital with at least three", {
  d <- simulate_hospitals(seed = 5)
  split <- holdout_split(d, seed = 1)
  per_hospital <- table(d$facility_id)
  expect_equal(nrow(split$test), sum(per_hospital >= 3))
  expect_true(all(table(droplevels(split$test$facility_id)) == 1))
  expect_equal(nrow(split$train) + nrow(split$test), nrow(d))
})

test_that("partial pooling beats both no pooling and complete pooling when hospitals differ", {
  d <- simulate_hospitals(seed = 6, sd_hospital = 0.05, sd_residual = 0.08)
  split <- holdout_split(d, seed = 2)
  rmse <- holdout_summary(holdout_predictions(split$train, split$test))
  expect_lt(rmse[["partial"]], rmse[["complete"]])
  expect_lt(rmse[["partial"]], rmse[["no_pooling"]])
})

test_that("small states are pulled harder toward zero than large ones", {
  d <- simulate_hospitals(seed = 7, sd_state = 0.03)
  states <- state_shrinkage(fit_mixed(d, heteroscedastic = FALSE), d)
  summary <- shrinkage_summary(states, small = 10)
  expect_lt(summary$median_share_kept_small, summary$median_share_kept_large)
  expect_lt(summary$sd_pooled_pct, summary$sd_raw_pct)
})

test_that("dispersion by volume reports each band", {
  d <- data.frame(y = log(c(1, 1.1, 0.9, 1.2, 0.8, 1)), err = c(1, 1.1, 0.9, 1.2, 0.8, 1),
                  discharges = c(50, 60, 150, 160, 500, NA))
  out <- dispersion_by_volume(d, breaks = c(0, 100, 200, Inf))
  expect_equal(out$rows, c(2, 2, 1))
  expect_equal(out$sd_log_err[1], sd(log(c(1, 1.1))))
})

test_that("fit_lme converges, and agrees with the default optimizer wherever that one converges", {
  d <- simulate_hospitals(seed = 7, sd_state = 0.03)
  f <- y ~ condition + ownership
  fitted <- fit_lme(f, random = ~ 1 | state/facility_id, data = d)
  with_optim <- lme(f, random = ~ 1 | state/facility_id, data = d, control = lme_control("optim"))
  expect_lt(abs(as.numeric(logLik(fitted)) - as.numeric(logLik(with_optim))), 0.01)
  # nlminb converges on this case on macOS but not on GitHub's Linux runner:
  # compare only where it does, so the test checks agreement, not the platform
  with_nlminb <- tryCatch(lme(f, random = ~ 1 | state/facility_id, data = d, control = lme_control("nlminb")),
                          error = function(e) NULL)
  if (!is.null(with_nlminb)) {
    expect_lt(abs(as.numeric(logLik(with_nlminb)) - as.numeric(logLik(with_optim))), 0.01)
  }
})
