# Mixed-effects models of log excess readmission ratios.
#
# Structure: condition rows nested in hospitals nested in states.
#   y_ijk = condition effect + ownership effect + u_state + u_hospital + e_ijk
# A random intercept per state and per hospital says "hospitals in one state
# share something, and a hospital's conditions share something" without
# spending a parameter on each of 2,818 hospitals.

library(nlme)

lme_control <- function(opt = "nlminb") lmeControl(maxIter = 200, msMaxIter = 200, niterEM = 100, opt = opt)

# Fit with nlme's default optimizer (nlminb); if it reports non-convergence,
# refit with optim. On GitHub's Linux runner nlminb failed on one simulated
# test case that converges on macOS; on macOS both optimizers reach the same
# log-likelihood for that case, so the fallback changes how the optimum is
# found, not which model is fit. A second failure is still an error.
fit_lme <- function(...) {
  tryCatch(lme(..., control = lme_control("nlminb")),
           error = function(e) {
             if (!grepl("convergence", conditionMessage(e))) stop(e)
             lme(..., control = lme_control("optim"))
           })
}

fit_mixed <- function(data, formula = y ~ condition + ownership, heteroscedastic = TRUE, method = "REML") {
  # varIdent lets each condition have its own residual spread: hip/knee ratios
  # vary far more than COPD ratios, and one shared variance would misweight them.
  weights <- if (heteroscedastic) varIdent(form = ~ 1 | condition) else NULL
  fit_lme(formula, random = ~ 1 | state/facility_id, data = data, weights = weights, method = method)
}

# Shares of variance at each level, from a homoscedastic fit (one residual
# variance, so the three shares add up to 1).
variance_shares <- function(model) {
  vc <- VarCorr(model)
  v <- c(state = as.numeric(vc[2, "Variance"]), hospital = as.numeric(vc[4, "Variance"]),
         residual = as.numeric(vc[5, "Variance"]))
  shares <- v / sum(v)
  list(variance = v, share = shares,
       # correlation between two conditions at the same hospital
       same_hospital_correlation = unname(shares["state"] + shares["hospital"]),
       # correlation between two hospitals in the same state
       same_state_correlation = unname(shares["state"]))
}

# Per-condition version from the heteroscedastic fit: the share of that
# condition's variance that belongs to the hospital and state levels.
condition_shares <- function(model) {
  vc <- VarCorr(model)
  state_v <- as.numeric(vc[2, "Variance"]); hosp_v <- as.numeric(vc[4, "Variance"])
  ratios <- coef(model$modelStruct$varStruct, unconstrained = FALSE, allCoef = TRUE)
  resid_v <- model$sigma^2 * ratios^2
  data.frame(condition = names(ratios), residual_sd_ratio = unname(ratios),
             hospital_and_state_share = unname((state_v + hosp_v) / (state_v + hosp_v + resid_v)))
}

# Likelihood-ratio tests: does each level of the hierarchy earn its place?
# (Testing a variance at zero is on the boundary of the parameter space, so
# these p-values are conservative - roughly twice the true value.)
level_tests <- function(data) {
  flat <- gls(y ~ condition + ownership, data = data, method = "ML")
  hosp <- fit_lme(y ~ condition + ownership, random = ~ 1 | facility_id, data = data, method = "ML")
  both <- fit_lme(y ~ condition + ownership, random = ~ 1 | state/facility_id, data = data, method = "ML")
  lr <- function(a, b) {
    stat <- 2 * (as.numeric(logLik(b)) - as.numeric(logLik(a)))
    c(lr = stat, p = pchisq(stat, df = 1, lower.tail = FALSE))
  }
  rbind(add_hospital = lr(flat, hosp), add_state = lr(hosp, both))
}

# Ownership effects from the mixed model and from ordinary least squares on
# the same rows. OLS treats a hospital's six condition rows as six independent
# observations; the mixed model does not.
ownership_effects <- function(model, data) {
  mixed <- summary(model)$tTable
  ols <- summary(lm(y ~ condition + ownership, data = data))$coefficients
  terms <- grep("^ownership", rownames(mixed), value = TRUE)
  data.frame(term = sub("^ownership", "", terms),
             mixed_pct = 100 * expm1(mixed[terms, "Value"]), mixed_se = mixed[terms, "Std.Error"],
             mixed_p = mixed[terms, "p-value"],
             ols_pct = 100 * expm1(ols[terms, "Estimate"]), ols_se = ols[terms, "Std. Error"],
             row.names = NULL)
}

# ---- does partial pooling predict better? -------------------------------------

# Hold out one randomly chosen condition from every hospital with >= 3
# reported conditions (so at least 2 remain to learn from).
holdout_split <- function(data, seed) {
  set.seed(seed)
  rows <- split(seq_len(nrow(data)), data$facility_id)
  eligible <- rows[lengths(rows) >= 3]
  test <- vapply(eligible, function(i) i[sample.int(length(i), 1)], integer(1))
  list(train = data[-test, ], test = data[test, ])
}

# Three ways to predict a hospital's held-out condition:
#   complete pooling - ignore the hospital: condition + ownership averages
#   no pooling       - add the hospital's own mean residual on its other conditions
#   partial pooling  - the mixed model's prediction, which shrinks that mean
#                      toward its state and the national level by how much
#                      evidence it rests on
holdout_predictions <- function(train, test) {
  fixed <- lm(y ~ condition + ownership, data = train)
  complete <- unname(predict(fixed, test))
  residual <- train$y - predict(fixed, train)
  own_mean <- tapply(residual, droplevels(train$facility_id), mean)
  no_pooling <- complete + unname(own_mean[as.character(test$facility_id)])
  partial <- unname(predict(fit_mixed(train), test, level = 2))
  training_conditions <- as.integer(table(droplevels(train$facility_id))[as.character(test$facility_id)])
  data.frame(facility_id = test$facility_id, condition = test$condition, y = test$y,
             training_conditions = training_conditions,
             complete = complete, no_pooling = no_pooling, partial = partial)
}

holdout_summary <- function(predictions) {
  rmse <- function(p) sqrt(mean((predictions$y - p)^2))
  c(complete = rmse(predictions$complete), no_pooling = rmse(predictions$no_pooling),
    partial = rmse(predictions$partial), hospitals = nrow(predictions))
}

# ---- states: raw means vs partial-pooled estimates -------------------------------

# Like-for-like comparison on the homoscedastic model: the "raw" state effect
# is the plain average of its hospitals' mean residuals (from the model's own
# fixed effects); the pooled one is the state's random effect. The first
# version compared an unweighted row mean against the weighted, adjusted model
# and produced "shrink factors" above 1 - not a shrinkage comparison at all.
# A ratio pooled/raw is also unstable when raw is near 0, so the pull is
# measured as a difference.
state_shrinkage <- function(model, data) {
  fe <- fixef(model)
  X <- model.matrix(~ condition + ownership, data)
  residual <- data$y - drop(X %*% fe[colnames(X)])
  hospital_mean <- tapply(residual, data$facility_id, mean)
  hospital_state <- tapply(as.character(data$state), data$facility_id, `[`, 1)
  raw <- tapply(hospital_mean, hospital_state[names(hospital_mean)], mean)
  re <- ranef(model, level = 1)
  pooled <- setNames(re[, 1], rownames(re))[names(raw)]
  hospitals <- as.integer(table(hospital_state)[names(raw)])
  out <- data.frame(state = names(raw), hospitals = hospitals,
                    raw_pct = 100 * expm1(as.numeric(raw)), pooled_pct = 100 * expm1(as.numeric(pooled)))
  out$pull_pct_points <- abs(out$raw_pct - out$pooled_pct)
  out$moved_toward_zero <- abs(out$pooled_pct) < abs(out$raw_pct)
  out[order(out$pooled_pct), ]
}

shrinkage_summary <- function(states, small = 15) {
  is_small <- states$hospitals < small
  keep <- abs(states$pooled_pct) / abs(states$raw_pct)
  list(states_moved_toward_zero = mean(states$moved_toward_zero),
       small_state_threshold = small, small_states = sum(is_small),
       median_share_kept_small = median(keep[is_small]),
       median_share_kept_large = median(keep[!is_small]),
       spearman_size_vs_pull = cor(states$hospitals, states$pull_pct_points, method = "spearman"),
       sd_raw_pct = sd(states$raw_pct), sd_pooled_pct = sd(states$pooled_pct))
}

# ---- is CMS's own model visible in the data? ----------------------------------------

# If ERRs were raw rates, small hospitals would be the NOISIEST. CMS computes
# them from its own hierarchical model, which pulls small hospitals toward 1 -
# so small hospitals should instead be the LEAST dispersed.
dispersion_by_volume <- function(data, breaks = c(0, 100, 200, 400, Inf)) {
  known <- data[!is.na(data$discharges), ]
  band <- cut(known$discharges, breaks, dig.lab = 5)
  data.frame(discharges = levels(band), rows = as.integer(table(band)),
             sd_log_err = as.numeric(tapply(known$y, band, sd)),
             p05_err = as.numeric(tapply(known$err, band, quantile, 0.05)),
             p95_err = as.numeric(tapply(known$err, band, quantile, 0.95)))
}
