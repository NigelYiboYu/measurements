library ('boot')
library ('parallel')
library ('tidyverse')

options (boot.parallel = 'multicore')
options (boot.ncpus = detectCores ())

DATA_PATH <- '.'

REPLICATES <- 33333
CONFIDENCE <- 0.99

OUTLIER_LIMIT <- 0.05
OUTLIER_SLACK <- 0.1

PLOT_ROWS <- 4
PLOT_WIDTH <- 300
PLOT_HEIGHT <- 300

STRIPE_WIDTH <- 600
STRIPE_HEIGHT <- 180

VM_BASELINE <- 'OpenJDK'


# Incrementally load data.
# This is O(n^2) as it should be :-)

master <- tibble ()

vm_dirs <- list.files (DATA_PATH, '^[[:alnum:][:punct:]]+$', include.dirs = TRUE, full.names = TRUE)
for (vm_dir in vm_dirs) {
    vm_name <- basename (vm_dir)

    data_files <- list.files (vm_dir, '^[[:alnum:][:punct:]]+\\.csv\\.xz$', full.names = TRUE)
    for (data_file in data_files) {
        data_name <- basename (data_file)
        data_split <- strsplit (data_name, '\\.csv\\.xz') [[1]]
        benchmark_name <- data_split [1]

        data_read <- suppressMessages (read_csv (data_file, col_types = cols (.default = col_double ())))
        descriptor <- tibble (benchmark = benchmark_name, vm = vm_name)
        master <- bind_rows (master, crossing (descriptor, data_read))
    }
}


# One time post processing.

# We really want time in seconds.
# TODO Eventually the harness should dump nanosecond CSV files.
master <- master %>% mutate (time = time / 1000)

# We want baseline virtual machine to the left.
# TODO Eventually this should be read from platform metadata.
master <- master %>% mutate (vm = factor (
    vm,
    ordered = TRUE, 
    levels = c ('OpenJDK', 'OpenJ9', 'GraalVM-CE', 'GraalVM'),
    labels = c ('OpenJDK', 'OpenJ9', 'GraalVM CE', 'GraalVM')))


# Annotate data with cold vs warm information.
#
# Right now we use a trivial filter, everything
# in the first half of ten minute execution
# is cold.

BENCHMARK_EXEC_TIME <- 600
WARM_CUTOFF_TIME <- BENCHMARK_EXEC_TIME * 0.5

master <- master %>% group_by (benchmark, vm, run) %>% mutate (total = cumsum (time))
master <- master %>% mutate (warm = (total >= WARM_CUTOFF_TIME))
master <- master %>% ungroup ()


# Helper function for averaging over runs.
get_run_means <- function (data) {
    return (data %>% group_by (run) %>% summarize (avg = mean (time)) %>% pull (avg))
}


# Simple violin plots: Single plot per benchmark

do_flag_outliers <- function (data) {
    limits <- quantile (data, c (OUTLIER_LIMIT, 1 - OUTLIER_LIMIT))
    range <- limits [2] - limits [1]
    limit_lo <- limits [1] - range * OUTLIER_SLACK
    limit_hi <- limits [2] + range * OUTLIER_SLACK
    return (data < limit_lo | data > limit_hi)
}

do_plot_violin <- function (data) {
    # Mild outlier filtering is required to prevent excess scale compression.
    # It would be better to achieve the same with fixed scale
    # but apparently faceting does not support it.
    # Outliers are picked per run to avoid
    # excluding entire run.
    data <- data %>% group_by (benchmark, run, vm) %>% filter (!do_flag_outliers (time)) %>% ungroup ()
    ggplot (data) + 
        geom_violin (aes (x = vm, y = time, fill = vm), scale = 'width', width = 1) + 
        geom_boxplot (aes (x = vm, y = time), width = 0.2) + 
        facet_wrap (vars (benchmark), nrow = PLOT_ROWS, scales = 'free_y') +
        theme (legend.position = 'none', axis.text.x = element_text (angle = 90, vjust = 0.5, hjust = 1)) +
        labs (x = NULL, y = 'Single repetition time [s]') +
        scale_fill_brewer (palette = 'Blues', type = 'qual')
}


# Simple bar plots: Single plot per benchmark

# Compute arithmetic mean with confidence intervals.
# We use standard bootstrap computation for confidence intervals.

do_mean_interval <- function (data, key) {
    # Key not used but supplied by dplyr::group_map.

    # We work on run means for speed.
    runs <- get_run_means (data)

    # Standard bootstrap computation.    
    mean_boot <- boot (runs, function (d, i) mean (d [i]), R = REPLICATES)

    # The computations can fail so fall back to something if they do.
    mean_ci <- tryCatch (boot.ci (mean_boot, type = 'bca', conf = CONFIDENCE), error = function (e) NA)
    if (!any (is.na (mean_ci))) return (data.frame (avg = mean_boot $ t0, lo = mean_ci $ bca [1,4], hi = mean_ci $ bca [1,5]))
    mean_ci <- tryCatch (boot.ci (mean_boot, type = 'basic', conf = CONFIDENCE), error = function (e) NA)
    if (!any (is.na (mean_ci))) return (data.frame (avg = mean_boot $ t0, lo = mean_ci $ basic [1,4], hi = mean_ci $ basic [1,5]))
    return (data.frame (avg = mean_boot $ t0, lo = NA, hi = NA))
}

do_plot_mean <- function (data) {
    summary <- data %>%
        group_by (benchmark, vm) %>%
        group_map (do_mean_interval)
    ggplot (summary) +
        geom_col (aes (x = vm, y = avg, fill = vm), color = 'black') +
        geom_errorbar (aes (x = vm, ymin = lo, ymax = hi), width = 0.5) +
        facet_wrap (vars (benchmark), nrow = PLOT_ROWS, scales = 'free_y') +
        theme (legend.position = 'none', axis.text.x = element_text (angle = 90, vjust = 0.5, hjust = 1)) +
        labs (x = NULL, y = 'Mean single repetition time [s]') +
        scale_fill_brewer (palette = 'Blues', type = 'qual')
}


# Simple ratio plots: Single plot per benchmark

# Compute ratio with confidence intervals.
# We use stratified bootstrap computation for confidence intervals.

do_ratio_interval <- function (data, key, orig) {

    # We work on run means for speed.
    runs <- get_run_means (data)

    # Get the baseline from the original data.
    base <- get_run_means (orig %>% filter (benchmark == key $ benchmark, vm == VM_BASELINE))

    # Helper function for stratified bootstrap.
    meanify <- function (data, index) {
        data_top <- data $ value [index [data $ strata]]
        data_bot <- data $ value [index [!data $ strata]]
        return (mean (data_top) / mean (data_bot))
    }

    # Stratified bootstrap computation.
    means_tibble <- bind_rows (tibble (value = runs, strata = FALSE), tibble (value = base, strata = TRUE))
    ratio_boot <- boot (means_tibble, meanify, R = REPLICATES, strata = means_tibble $ strata)

    # The computations can fail so fall back to something if they do.
    ratio_ci <- tryCatch (boot.ci (ratio_boot, type = 'bca', conf = CONFIDENCE), error = function (e) NA)
    if (!any (is.na (ratio_ci))) return (data.frame (avg = ratio_boot $ t0, lo = ratio_ci $ bca [1,4], hi = ratio_ci $ bca [1,5]))
    ratio_ci <- tryCatch (boot.ci (ratio_boot, type = 'basic', conf = CONFIDENCE), error = function (e) NA)
    if (!any (is.na (ratio_ci))) return (data.frame (avg = ratio_boot $ t0, lo = ratio_ci $ basic [1,4], hi = ratio_ci $ basic [1,5]))
    return (data.frame (avg = ratio_boot $ t0, lo = NA, hi = NA))
}

do_plot_ratio <- function (data) {
    summary <- data %>%
        group_by (benchmark, vm) %>%
        group_map (do_ratio_interval, data)
    ggplot (summary, aes (x = vm, y = avg * 100, ymin = lo * 100, ymax = hi * 100, fill = vm)) +
        geom_col () +
        geom_errorbar (width = 0.5) +
        facet_wrap (vars (benchmark), nrow = 1, scales = 'free_y', strip.position = 'bottom') +
        labs (x = NULL, y = 'Average speed up to OpenJDK baseline [%]', fill = 'JVM implementation') +
        theme (
            text = element_text (family = 'Serif'),
            legend.position = 'bottom',
            axis.text.x = element_blank (),
            axis.ticks.x = element_blank (),
            axis.title.y = element_text (size = 14),
            strip.text.x = element_text (angle = 90, vjust = 0.5, hjust = 1, size = 14),
            strip.background = element_blank (),
            legend.text = element_text (size = 14),
            legend.title = element_text (size = 14)) +
        scale_fill_manual (
            breaks = c ('OpenJDK', 'OpenJ9', 'GraalVM CE', 'GraalVM'),
            values = c ('#ecd5a0', '#60aa52', '#a73607', '#6e8ab1'))
}


# Prepare plots for web.

data <- master %>% filter (warm)

ggsave ('stripe.png', do_plot_ratio (data), width = STRIPE_WIDTH, height = STRIPE_HEIGHT, unit = 'mm')
ggsave ('overview-mean.png', do_plot_mean (data), width = PLOT_WIDTH, height = PLOT_HEIGHT, unit = 'mm')
ggsave ('overview-violin.png', do_plot_violin (data), width = PLOT_WIDTH, height = PLOT_HEIGHT, unit = 'mm')
