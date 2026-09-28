# How it works

```
2 CMS CSVs (SHA-256) ─▶ build_ratios: one row per hospital × condition, y = log(ERR)
      ─▶ nlme::lme  y ~ condition + ownership, random = ~1 | state/hospital
             ├─ homoscedastic fit ─▶ variance shares, likelihood-ratio tests, state shrinkage
             └─ varIdent(~1 | condition) fit ─▶ per-condition shares, ownership, prediction
      ─▶ 5 random hold-outs: complete vs no vs partial pooling
      ─▶ ggplot2 figures, CSVs, summary.json
```

## Layout

| Path | Contents |
|---|---|
| `R/data.R` | download, checksum, CMS parsing (suppressed values → NA), ownership groups |
| `R/models.R` | mixed models, variance shares, likelihood-ratio tests, ownership vs OLS, hold-out prediction, state shrinkage, dispersion by volume |
| `R/plots.R` | ggplot2 figures |
| `scripts/run.R` | `download` and `analyze` commands |
| `tests/testthat/` | 11 tests |
| `renv.lock` | exact package versions |

## The ideas, in one line each

- **Random intercept:** each hospital (and state) gets its own shift, drawn from a shared distribution, so 2,818 hospitals cost one variance parameter, not 2,818 free parameters.
- **Nested random effects** (`state/hospital`): hospitals sit inside states. A hospital's shift is measured relative to its state's.
- **Variance shares / ICC:** the share of the total variance at each level. The state plus hospital share is the expected correlation between two conditions at one hospital.
- **Partial pooling (shrinkage):** a hospital's estimate is a weighted blend of its own data and its group's average. The weight on its own data grows with how much data it has and how consistent that data is.
- **Complete vs no pooling:** the two extremes. Complete pooling ignores the hospital; no pooling trusts its own average fully.
- **`varIdent`:** a separate residual SD per condition, because the residual SD for hip/knee is about 4× that of COPD.
- **REML vs ML:** REML for estimating variances; ML to compare models whose random-effect structures differ with a likelihood-ratio test.

## Choices I would defend

| Choice | Why |
|---|---|
| Log of the ratio | Ratios are multiplicative. Symmetric around 0 on the log scale |
| `nlme`, not `lme4` | `nlme` ships with R (no compile with Homebrew's source-built packages), supports nested effects, and supports per-group residual variances (`varIdent`), which this data needs |
| Test prediction on held-out conditions | Showing that the model fits is weaker than showing it predicts data it never saw. Five repeats show the result isn't one lucky split |
| Compare against both pooling extremes | "Better than ignoring the hospital" alone would not show that shrinkage is the reason. Beating the hospital's own average does |
| Report OLS alongside the mixed model | It shows what clustering changes. Here it changed the effect size, not the standard error, which was not what I expected |
| Look at dispersion by volume | It checks whether the input is raw data or a model output. It's a model output, and that limits the conclusions |

## Mistakes caught along the way

1. **Default iteration limit.** The heteroscedastic model hit `nlme`'s default limit and failed to converge. The limits are raised in `lme_control()`.
2. **State shrinkage compared unlike things, twice.** First unweighted rows against a weighted, adjusted estimate; then a ratio that explodes near zero. Both are described in `results.md` §6.
3. **A convergence failure only on Linux.** On GitHub's CI runner, `nlme`'s default optimizer failed to converge on one simulated test case that passes on macOS. `fit_lme()` now retries with `optim` only when the default reports non-convergence. A test confirms both optimizers reach the same log-likelihood on that case, so the fallback changes how the optimum is found, not which model is fit.
4. **Test tolerances that tested nothing.** testthat 3 ignores `scale =`, so `tolerance` was *relative*: the ownership check would have accepted anything from −4.4% to +0.4%. The tests now assert absolute errors.

## Tests (11)

- **CMS parsing:** "N/A" ratios are dropped; "Too Few to Report" discharges become NA but the row is kept; condition names are extracted; ownership labels are grouped; checksum rejection.
- **On simulated hospitals with known variances:**
  - the variance shares are recovered within 0.05;
  - the hospital level is detected when present and not when absent;
  - a 2% ownership effect is recovered within 0.8 points;
  - the hold-out takes exactly one condition per eligible hospital;
  - partial pooling beats both no pooling and complete pooling;
  - small states are pulled harder than large ones.
- **Dispersion-by-volume arithmetic**, and the fallback optimizer reaching the same fit as the default.

## Things to be able to explain

- What does "13.4% of the variance is at the hospital level" mean for a patient choosing a hospital?
- Why does a hospital's own average predict *worse* than ignoring the hospital?
- What does partial pooling do, and why does its advantage shrink as a hospital reports more conditions?
- Why does the heteroscedastic model matter? What does hip/knee's 4% tell you?
- Why are small hospitals' ratios *less* spread out, and what does that mean for using ERR to find bad hospitals?
- Why did OLS change the ownership effect size but not the standard error?
