# ggplot2 figures for the README and results document.

ink <- "#1f2937"
accent <- "#0e6a70"
muted <- "#9ca3af"
warn <- "#b45309"

base_theme <- function() {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(colour = ink, size = 11),
                   plot.title.position = "plot", panel.grid.minor = ggplot2::element_blank(),
                   legend.position = "bottom")
}

pct_axis <- function(x) paste0(round(100 * x), "%")

plot_variance_shares <- function(shares) {
  frame <- data.frame(level = factor(c("State", "Hospital (within state)", "This condition at this hospital"),
                                     levels = c("State", "Hospital (within state)", "This condition at this hospital")),
                      share = as.numeric(shares$share))
  ggplot2::ggplot(frame, ggplot2::aes(level, share, fill = level)) +
    ggplot2::geom_col(width = 0.6, show.legend = FALSE) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f%%", 100 * share)), vjust = -0.4, colour = ink, size = 3.6) +
    ggplot2::scale_fill_manual(values = c(muted, accent, "#d1d5db")) +
    ggplot2::scale_y_continuous(labels = pct_axis, limits = c(0, 1)) +
    ggplot2::labs(x = NULL, y = "Share of variance in log excess readmission ratio",
                  title = "Where the variation in readmission ratios lives") +
    base_theme()
}

plot_holdout <- function(predictions) {
  long <- do.call(rbind, lapply(c("complete", "no_pooling", "partial"), function(m) {
    err <- (predictions$y - predictions[[m]])^2
    agg <- tapply(err, predictions$training_conditions, function(e) sqrt(mean(e)))
    data.frame(method = m, training_conditions = as.integer(names(agg)), rmse = as.numeric(agg))
  }))
  long$method <- factor(long$method, levels = c("complete", "no_pooling", "partial"),
                        labels = c("Ignore the hospital (complete pooling)",
                                   "Hospital's own average (no pooling)",
                                   "Mixed model (partial pooling)"))
  ggplot2::ggplot(long, ggplot2::aes(training_conditions, rmse, colour = method)) +
    ggplot2::geom_line(linewidth = 0.9) + ggplot2::geom_point(size = 2) +
    ggplot2::scale_colour_manual(values = c(muted, warn, accent), name = NULL) +
    ggplot2::guides(colour = ggplot2::guide_legend(ncol = 1)) +
    ggplot2::labs(x = "Other conditions the hospital reports (what the prediction can learn from)",
                  y = "Held-out error (RMSE, log ratio)",
                  title = "Predicting a hospital's unseen condition: shrinkage wins at every level") +
    base_theme()
}

plot_state_shrinkage <- function(states) {
  frame <- states
  frame$state <- factor(frame$state, levels = frame$state[order(frame$pooled_pct)])
  ggplot2::ggplot(frame, ggplot2::aes(y = state)) +
    ggplot2::geom_vline(xintercept = 0, colour = muted, linetype = "dashed") +
    ggplot2::geom_segment(ggplot2::aes(x = raw_pct, xend = pooled_pct, yend = state), colour = muted) +
    ggplot2::geom_point(ggplot2::aes(x = raw_pct), colour = muted, size = 1.6) +
    ggplot2::geom_point(ggplot2::aes(x = pooled_pct, size = hospitals), colour = accent) +
    ggplot2::scale_size_area(max_size = 3.5, name = "Hospitals") +
    ggplot2::labs(x = "State effect on excess readmission ratio (%): grey = raw mean, teal = mixed model",
                  y = NULL, title = "Small states are pulled hardest toward the national level") +
    base_theme() + ggplot2::theme(axis.text.y = ggplot2::element_text(size = 6.5))
}

plot_dispersion <- function(dispersion) {
  dispersion$discharges <- factor(dispersion$discharges, levels = dispersion$discharges)
  ggplot2::ggplot(dispersion, ggplot2::aes(discharges, sd_log_err)) +
    ggplot2::geom_col(fill = accent, width = 0.6) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("n = %s", format(rows, big.mark = ","))), vjust = -0.4,
                       colour = ink, size = 3.2) +
    ggplot2::labs(x = "Discharges behind the ratio", y = "SD of log excess readmission ratio",
                  title = "Smaller hospitals' ratios are LESS spread out: CMS has already shrunk them") +
    base_theme()
}
