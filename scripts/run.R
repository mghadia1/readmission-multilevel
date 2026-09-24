#!/usr/bin/env Rscript
# Usage:
#   Rscript scripts/run.R download            # fetch + checksum the two CMS files
#   Rscript scripts/run.R analyze [out_dir]   # everything else -> outputs/

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0 || !args[1] %in% c("download", "analyze")) {
  stop("usage: Rscript scripts/run.R download | analyze [out_dir]")
}
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

if (args[1] == "download") {
  cat(download_cms(), sep = "\n")
  quit(save = "no")
}

out <- if (length(args) >= 2) args[2] else "outputs"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
data <- load_ratios()

# ---- 1. where the variation lives ---------------------------------------------
homoscedastic <- fit_mixed(data, heteroscedastic = FALSE)
shares <- variance_shares(homoscedastic)
tests <- level_tests(data)

# ---- 2. the model used for everything else ---------------------------------------
model <- fit_mixed(data)
aic <- c(one_residual_variance = AIC(homoscedastic), variance_per_condition = AIC(model))
per_condition <- condition_shares(model)
ownership <- ownership_effects(model, data)
states <- state_shrinkage(homoscedastic, data)
shrinkage <- shrinkage_summary(states)
dispersion <- dispersion_by_volume(data)

# ---- 3. held-out prediction, repeated over five random hold-outs --------------------
runs <- lapply(1:5, function(seed) {
  split <- holdout_split(data, seed)
  holdout_predictions(split$train, split$test)
})
holdout <- do.call(rbind, lapply(seq_along(runs), function(i) c(seed = i, holdout_summary(runs[[i]]))))
holdout <- as.data.frame(holdout)

# ---- outputs ----------------------------------------------------------------------
write.csv(data.frame(level = names(shares$share), variance = shares$variance, share = shares$share),
          file.path(out, "variance_shares.csv"), row.names = FALSE)
write.csv(per_condition, file.path(out, "condition_shares.csv"), row.names = FALSE)
write.csv(ownership, file.path(out, "ownership_effects.csv"), row.names = FALSE)
write.csv(states, file.path(out, "state_shrinkage.csv"), row.names = FALSE)
write.csv(dispersion, file.path(out, "dispersion_by_volume.csv"), row.names = FALSE)
write.csv(holdout, file.path(out, "holdout_rmse.csv"), row.names = FALSE)
write.csv(runs[[1]], file.path(out, "holdout_predictions_seed1.csv"), row.names = FALSE)

save_plot <- function(p, name, w = 7, h = 4) ggplot2::ggsave(file.path(out, name), p, width = w, height = h, dpi = 150, bg = "white")
save_plot(plot_variance_shares(shares), "variance_shares.png", h = 3.8)
save_plot(plot_holdout(do.call(rbind, runs)), "holdout_by_conditions.png", h = 4.4)
save_plot(plot_state_shrinkage(states), "state_shrinkage.png", w = 7, h = 8)
save_plot(plot_dispersion(dispersion), "dispersion_by_volume.png", h = 3.8)

summary <- list(
  rows = nrow(data), hospitals = nlevels(data$facility_id), states = nlevels(data$state),
  rows_per_condition = as.list(table(data$condition)),
  variance_shares = as.list(shares$share),
  same_hospital_correlation = shares$same_hospital_correlation,
  same_state_correlation = shares$same_state_correlation,
  level_tests = as.data.frame(tests),
  aic = as.list(aic), condition_shares = per_condition,
  ownership_effects = ownership,
  holdout_rmse = holdout,
  holdout_mean = as.list(colMeans(holdout[, c("complete", "no_pooling", "partial")])),
  dispersion_by_volume = dispersion,
  state_shrinkage = shrinkage
)
jsonlite::write_json(summary, file.path(out, "summary.json"), auto_unbox = TRUE, digits = 6, pretty = TRUE)
cat(jsonlite::toJSON(summary[c("rows", "hospitals", "variance_shares", "same_hospital_correlation", "aic", "holdout_mean")],
                     auto_unbox = TRUE, pretty = TRUE, digits = 5), "\n")
