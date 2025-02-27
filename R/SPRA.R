#' Generate Model Data from Expression Data and Filtered Gene Sets
#'
#' This function processes expression data and filtered gene sets to generate latent variables and group vectors.
#' The expression data is processed using a set of filtered gene sets to generate a latent variable matrix and a group vector.
#'
#' @param exprSet_file A string specifying the file path of the expression dataset file (TPM.txt).
#'                     The dataset should be a tab-delimited file with samples as rows and genes as columns.
#' @param geneSet A list of filtered gene sets. Each element in the list is a vector of gene names or indices 
#'                           representing a specific gene group.
#' 
#' @return A list containing:
#' \item{X.latent}{A matrix of latent variables created by expanding the expression data according to the gene sets.}
#' \item{grp.vec}{A vector indicating the group membership of each latent variable.}
#' 
#' @examples
#' # Load the filtered gene sets and expression dataset
#' geneSet <- readRDS("filtered_gene_sets.rds")
#' exprSet_file <- "TPM.txt"
#' 
#' # Generate the model data
#' model_data <- generate_model_data(exprSet_file, geneSet)
#' X.latent <- model_data$X.latent
#' grp.vec <- model_data$grp.vec
#'
#' @export
generate_model_data <- function(exprSet_file, geneSet) {
  library(Matrix)
  # Read expression dataset
  exprSet <- read.table(exprSet_file, sep = "\t", header = TRUE, row.names = 1)
  exprSet <- as.matrix(exprSet)
  # Transpose the expression matrix
  X <- t(exprSet)
  # Check and fix column names
  if (length(colnames(X)) != ncol(X)) {
    if (!is.null(colnames(X))) {
      colnames(X) <- colnames(X)[1:ncol(X)]
    } else {
      colnames(X) <- paste0("V", 1:ncol(X))
    }
  }
  # Function to create incidence matrix
  incidenceMatrix <- function(X, group) {
    n <- nrow(X)
    p <- ncol(X)
    # Ensure 'group' is a list
    if (!is.list(group)) {
      stop("Argument 'group' must be a list of integer indices or character names of variables!")
    }
    J <- length(group)
    grp.mat <- Matrix(0, nrow = J, ncol = p, sparse = TRUE, 
                      dimnames = list(as.character(rep(NA, J)), as.character(rep(NA, p))))
    # Assign column names to grp.mat if necessary
    if (is.null(colnames(X))) {
      colnames(X) <- paste("V", 1:ncol(X), sep = "")
    }
    if (is.null(names(group))) {
      names(group) <- paste("grp", 1:J, sep = "")
    }
    # Fill the incidence matrix based on numeric or character group names
    if (is.numeric(group[[1]])) {
      for (i in 1:J) {
        ind <- group[[i]]
        grp.mat[i, ind] <- 1
        colnames(grp.mat)[ind] <- colnames(X)[ind]
      }
    } else {
      for (i in 1:J) {
        grp.i <- as.character(group[[i]])
        ind <- colnames(X) %in% grp.i
        grp.mat[i, ] <- 1 * ind
        colnames(grp.mat)[ind] <- colnames(X)[ind]
      }
    }
    rownames(grp.mat) <- as.character(names(group))
    
    if (all(grp.mat == 0)) {
      stop("The names of variables in X don't match with names in group!")
    }
    return(grp.mat)
  }
  # Function to expand expression matrix according to groupings
  expandX <- function(X, group) {
    incidence.mat <- incidenceMatrix(X, group)
    incidence.mat <- as(incidence.mat, "CsparseMatrix")
    over.mat <- incidence.mat %*% t(incidence.mat)
    grp.vec <- rep(1:nrow(over.mat), times = diag(over.mat))
    X.latent <- NULL
    names <- NULL
    for (i in 1:nrow(incidence.mat)) {
      idx <- incidence.mat[i, ] == 1
      X.latent <- cbind(X.latent, X[, idx, drop = FALSE])
      names <- c(names, colnames(incidence.mat)[idx])
    }
    colnames(X.latent) <- paste("grp", grp.vec, "_", names, sep = "")
    return(as.matrix(X.latent))
  }
  # Generate the latent variable matrix and group vector
  X.latent <- expandX(X, geneSet)
  incid.mat <- incidenceMatrix(X, geneSet)
  incid.mat <- as(incid.mat, "CsparseMatrix")
  over.mat <- incid.mat %*% t(incid.mat)
  grp.vec <- rep(1:nrow(over.mat), times = diag(over.mat))
  # Return the results as a list
  return(list(X.latent = X.latent, grp.vec = grp.vec))
}

#' Perform SGR analysis with cross-validation and plots
#'
#' This function performs the SGR (Sparse Group Regularization) analysis with a given latent feature matrix,
#' response vector, and group vector. It includes cross-validation for tuning the model and produces
#' plots for cross-validation errors and coefficients. The results are saved as PDF files in the specified
#' plot directory.
#'
#' @param model_data A list containing the latent variable matrix (X.latent) and the group vector (grp.vec) generated by the 
#'                   `generate_model_data` function.
#' @param X.latent A matrix of latent variables generated by the `generate_model_data` function.
#' @param sample_info_file A string representing the file path to the sample information file. The file should contain
#'                         at least one column named "Type" for the response variable.
#' @param grp.vec A vector of group indices generated from the `generate_model_data` function.
#' @param alpha The elastic net mixing parameter (alpha between 0 and 1).
#' @param plot_dir A string representing the directory where the plots will be saved. Default is "plots".
#'
#' @return A list containing the following components:
#' \item{fit}{The fitted SGR model object.}
#' \item{coefficients_df}{A data frame of coefficients for the optimal lambda.}
#' \item{SGR_pos}{A character vector of feature names with positive coefficients.}
#' \item{SGR_neg}{A character vector of feature names with negative coefficients.}
#' \item{pos_coefficients}{A data frame of positive coefficients for the selected features.}
#' \item{neg_coefficients}{A data frame of negative coefficients for the selected features.}
#' \item{cv_result}{The cross-validation result object containing errors and lambda selection.}
#'
#' @examples
#' # Example usage:
#' model_data <- generate_model_data(exprSet_file, geneSet)
#' X.latent <- model_data$X.latent
#' grp.vec <- model_data$grp.vec
#' sample_info_file <- "phenotype.txt"
#' result <- sgr_analysis_with_plots(X.latent, sample_info_file, 
#'                                    grp.vec, alpha = 0.95, 
#'                                    plot_dir = "my_plots")
#'
#' @export
sgr_analysis_with_plots <- function(X.latent, sample_info_file, grp.vec, alpha, lambda_min = 0.008, tolerance = 1e-6, nfolds = 10, seed = 123456, plot_dir = "plots") {
  library(ggplot2)
  library(asgl)  
  sample_info <- read.table(sample_info_file, header = TRUE, sep = "\t")
  y <- sample_info$Type 
  set.seed(seed)
  fit <- asgl(X.latent, y, grp.vec, family = "binomial", alpha = alpha, standardize = FALSE, lambda_min = lambda_min)
  cv_asgl <- function(x, y, index, family = c("gaussian", "binomial"), offset = NULL, 
                    alpha = 0.95, lambda = NULL, lambda_min = 0.1, nlambda = 20, 
                    maxit = 1000, thresh = 0.001, gamma = 0.8, step = 1, standardize = FALSE, 
                    grp_weights = NULL, ind_weights = NULL, nfolds = 5) {
  
  if (!is.matrix(x)) {
    stop("the argument 'x' must be a matrix.", call. = FALSE)
  }
  dimx <- dim(x)
  if (is.null(dimx) || dimx[2] < 2) {
    stop("the argument 'x' must be a matrix with 2 or more columns.", call. = FALSE)
  }
  nobs <- dimx[1]
  nvar <- dimx[2]
  if (!is.vector(y)) {
    stop("the argument 'y' must be a vector.", call. = FALSE)
  }
  leny <- length(y)
  if (leny != nobs) {
    stop(paste("the length of 'y' (", leny, ") is not equal to the number of ", 
               "rows of 'x' (", nobs, ").", sep = ""), call. = FALSE)
  }
  if (!is.vector(index)) {
    stop("the argument 'index' must be a vector.", call. = FALSE)
  }
  leni <- length(index)
  if (leni != nvar) {
    stop(paste("the length of 'index' (", leni, ") is not equal to the number ", 
               "of columns of 'x' (", nvar, ").", sep = ""), call. = FALSE)
  }
  if (is.null(offset)) {
    offset <- rep.int(0, leny)
  }
  if (!is.vector(offset)) {
    stop("the argument 'offset' must be a vector.", call. = FALSE)
  }
  leno <- length(offset)
  if (leno != nobs) {
    stop(paste("the length of 'offset' (", leno, ") is not equal to the ", 
               "number of rows of 'x' (", nobs, ").", sep = ""), call. = FALSE)
  }
  lenui <- length(unique(index))
  if (is.null(grp_weights)) {
    grp_weights <- rep.int(1, lenui)
  }
  if (!is.vector(grp_weights)) {
    stop("the argument 'grp_weights' must be a vector.", call. = FALSE)
  }
  if (is.null(ind_weights)) {
    ind_weights <- rep.int(1, nvar)
  }
  if (!is.vector(ind_weights)) {
    stop("the argument 'ind_weights' must be a vector.", call. = FALSE)
  }
  lengw <- length(grp_weights)
  if (lengw != lenui) {
    stop(paste("the length of 'grp_weights' (", lengw, ") is not equal to the ", 
               "number of unique elements of 'index' (", lenui, 
               ").", sep = ""), call. = FALSE)
  }
  leniw <- length(ind_weights)
  if (leniw != nvar) {
    stop(paste("the length of 'ind_weights' (", leniw, ") is not equal to the ", 
               "number of columns of 'x' (", nvar, ").", sep = ""), call. = FALSE)
  }
  family <- match.arg(family)
  if (alpha < 0 || alpha > 1) {
    stop("the argument 'alpha' must be between 0 and 1.")
  }
  if (is.null(lambda)) {
    lambda <- get_lambda_sequence(x, y, index, family, lambda_min, 
                                  nlambda, alpha, grp_weights, ind_weights)
  } else {
    nlambda <- length(lambda)
  }
  foldid <- sample(rep(1:nfolds, length = nobs))
  cv_errors <- matrix(NA, nrow = nlambda, ncol = nfolds) 
  for (i in 1:nfolds) {
    train <- (foldid != i)
    test <- (foldid == i)   
    fit <- asgl(x[train, ], y[train], index, family = family, offset = offset[train], 
                alpha = alpha, lambda = lambda, lambda_min = lambda_min, nlambda = nlambda, 
                maxit = maxit, thresh = thresh, gamma = gamma, step = step, 
                standardize = standardize, grp_weights = grp_weights, ind_weights = ind_weights)   
    for (j in 1:nlambda) {
      beta <- fit$beta[, j]
      intercept <- fit$intercept[j]
      y_pred <- x[test, ] %*% beta + intercept + offset[test]   
      if (family == "gaussian") {
        cv_errors[j, i] <- mean((y[test] - y_pred)^2)
      } else if (family == "binomial") {
        prob <- 1 / (1 + exp(-y_pred))
        cv_errors[j, i] <- -mean(y[test] * log(prob) + (1 - y[test]) * log(1 - prob))
      }
    }
  }
  mean_cv_errors <- rowMeans(cv_errors)
  best_lambda_index <- which.min(mean_cv_errors)
  best_lambda <- lambda[best_lambda_index]
  best_fit <- asgl(x, y, index, family = family, offset = offset, 
                   alpha = alpha, lambda = lambda, lambda_min = lambda_min, 
                   nlambda = nlambda, maxit = maxit, thresh = thresh, 
                   gamma = gamma, step = step, standardize = standardize, 
                   grp_weights = grp_weights, ind_weights = ind_weights)
  
  return(list(fit = best_fit, lambda = best_lambda, cv_errors = cv_errors))
}
plot_cv_errors <- function(cv_result) {
  lambda <- cv_result$fit$lambda
  cv_errors <- cv_result$cv_errors
  mean_cv_errors <- rowMeans(cv_errors)
  plot(log(lambda), mean_cv_errors, type = "b", xlab = "log(lambda)", ylab = "Mean CV Error",
       main = "Cross-Validation Error vs. log(lambda)")
  abline(v = log(cv_result$lambda), col = "red", lty = 2)
  legend("topright", legend = paste("Best lambda =", round(cv_result$lambda, 4)), 
         col = "red", lty = 2)
}
plot_coefficients <- function(cv_result) {
  best_lambda_index <- which.min(rowMeans(cv_result$cv_errors))  # 找到最佳lambda索引
  beta <- cv_result$fit$beta[, best_lambda_index]  # 获取最佳lambda对应的系数
  feature_names <- colnames(cv_result$fit$x)
  if (is.null(feature_names)) {
    feature_names <- paste("X", 1:length(beta), sep = "")
  }
  plot(beta, type = "h", lwd = 2, xlab = "Features", ylab = "Coefficients",
       main = paste("Coefficients at Best Lambda (", round(cv_result$lambda, 4), ")", sep = ""))
  axis(1, at = 1:length(beta), labels = feature_names, las = 2, cex.axis = 0.7)
}
  cv_result <- cv_asgl(X.latent, y, grp.vec, family = "binomial", alpha = alpha, standardize = FALSE, nfolds = nfolds, lambda = fit$lambda, lambda_min = lambda_min)
  lambda.min <- cv_result$lambda
  lambda_min_index <- which(abs(fit$lambda - lambda.min) < tolerance)
  coefficients <- fit$beta[, lambda_min_index]
  coefficients_df <- as.data.frame(coefficients)
  rownames(coefficients_df) <- colnames(X.latent)
  SGR_pos <- colnames(X.latent)[which(coefficients_df$coefficients > 0)]
  SGR_neg <- colnames(X.latent)[which(coefficients_df$coefficients < 0)]
  pos_coefficients <- coefficients_df[SGR_pos, , drop = FALSE]
  neg_coefficients <- coefficients_df[SGR_neg, , drop = FALSE] 
  if (!dir.exists(plot_dir)) {
    dir.create(plot_dir)
  }
  pdf(file.path(plot_dir, paste0("cv_errors_", alpha, ".pdf")))
  plot_cv_errors(cv_result)
  dev.off() 
  pdf(file.path(plot_dir, paste0("coefficients_", alpha, ".pdf")))
  plot_coefficients(cv_result)
  dev.off()
  return(list(fit = fit, coefficients_df = coefficients_df, SGR_pos = SGR_pos, 
              SGR_neg = SGR_neg, pos_coefficients = pos_coefficients, 
              neg_coefficients = neg_coefficients, cv_result = cv_result))
}

#' Process Expression Data and Calculate Enrichment Scores
#'
#' This function reads expression data, coefficients, and gene sets, applies weights to the expression data,
#' and calculates enrichment scores using ssGSEA.
#'
#' @param exprSet_file A string specifying the file path of the expression dataset file (e.g., TPM.txt).
#'                     The dataset should be a tab-delimited file with samples as rows and genes as columns.
#' @param geneSet A list of filtered gene sets. Each element in the list is a vector of gene names or indices 
#'                           representing a specific gene group.
#' @param model_data A list containing the latent variable matrix (X.latent) and the group vector (grp.vec) generated by the 
#'                   `generate_model_data` function.
#' @param X.latent A matrix of latent variables generated by the `generate_model_data` function.
#' @param grp.vec A vector of group indices generated from the `generate_model_data` function.
#' @param alpha The elastic net mixing parameter (alpha between 0 and 1).
#' @param sample_info_file A string representing the file path to the sample information file. The file should contain
#'                         at least one column named "Type" for the response variable.
#' @param fit_results A list containing the fit object, coefficients dataframe, positive coefficients, negative coefficients, 
#'                    and cross-validation result obtained from the `sgr_analysis_with_plots` function.
#' @param coef_file A string specifying the path to the coefficients data file obtained from the `sgr_analysis_with_plots` function.
#' @param pos_file A string specifying the path to the positive gene set file obtained from the `sgr_analysis_with_plots` function.
#' @param neg_file A string specifying the path to the negative gene set file obtained from the `sgr_analysis_with_plots` function.
#' @param expr_file A string specifying the path to the validation data file (validation.txt).
#'
#' @return A data frame containing the enrichment scores and final scores for each sample.
#'
#' @examples
#' exprSet_file <- "TPM.txt"
#' geneSet <- readRDS("filtered_gene_sets.rds")
#' model_data <- generate_model_data(exprSet_file, geneSet)
#' X.latent <- model_data$X.latent
#' grp.vec <- model_data$grp.vec
#' alpha <- 0.95
#' sample_info_file <- "phenotype.txt"
#' fit_results <- sgr_analysis_with_plots(X.latent, sample_info_file, grp.vec, alpha, plot_dir = "my_plots")
#' coef_file <- fit_results$coefficients_df
#' pos_file <- fit_results$SGR_pos
#' neg_file <- fit_results$SGR_neg
#' expr_file <- "validation.txt"
#' result <- calculate_total_score(expr_file, geneSet, coef_file, pos_file, neg_file)
#' print(result)
#'
#' @export
calculate_total_score <- function(expr_file, geneSet, coef_file, pos_file, neg_file) {
  library(GSVA)
  # Read the expression dataset
  exprSet <- read.table(file = expr_file, sep = "\t", header = TRUE, row.names = 1)
  X <- t(exprSet)
  # Ensure column names are valid
  if (length(colnames(X)) != ncol(X)) {
    if (!is.null(colnames(X))) {
      colnames(X) <- colnames(X)[1:ncol(X)]
    } else {
      colnames(X) <- paste0("V", 1:ncol(X))
    }
  }
  # Function to create incidence matrix
  incidenceMatrix <- function(X, group) {
    n <- nrow(X)
    p <- ncol(X)
    if (!is.list(group)) {
      stop("Argument 'group' must be a list of integer indices or character names of variables!")
    }
    J <- length(group)
    grp.mat <- Matrix(0, nrow = J, ncol = p, sparse = TRUE, 
                      dimnames = list(as.character(rep(NA, J)), as.character(rep(NA, p))))
    if (is.null(colnames(X))) {
      colnames(X) <- paste("V", 1:ncol(X), sep = "")
    }
    if (is.null(names(group))) {
      names(group) <- paste("grp", 1:J, sep = "")
    }
    # Fill the incidence matrix
    if (is.numeric(group[[1]])) {
      for (i in 1:J) {
        ind <- group[[i]]
        grp.mat[i, ind] <- 1
        colnames(grp.mat)[ind] <- colnames(X)[ind]
      }
    } else {
      for (i in 1:J) {
        grp.i <- as.character(group[[i]])
        ind <- colnames(X) %in% grp.i
        grp.mat[i, ] <- 1 * ind
        colnames(grp.mat)[ind] <- colnames(X)[ind]
      }
    }
    rownames(grp.mat) <- as.character(names(group))
    
    if (all(grp.mat == 0)) {
      stop("The names of variables in X don't match with names in group!")
    }
    return(grp.mat)
  }
  # Function to expand expression matrix based on gene sets
  expandX <- function(X, group) {
    incidence.mat <- incidenceMatrix(X, group)
    incidence.mat <- as(incidence.mat, "CsparseMatrix") 
    over.mat <- incidence.mat %*% t(incidence.mat)
    grp.vec <- rep(1:nrow(over.mat), times = diag(over.mat))
    X.latent <- NULL
    names <- NULL
    for (i in 1:nrow(incidence.mat)) {
      idx <- incidence.mat[i, ] == 1
      X.latent <- cbind(X.latent, X[, idx, drop = FALSE])
      names <- c(names, colnames(incidence.mat)[idx])
    }
    colnames(X.latent) <- paste("grp", grp.vec, "_", names, sep = "")
    return(as.matrix(X.latent))
  }
  # Expand the expression matrix based on filtered gene sets
  X.latent <- expandX(X, geneSet)
  # Apply weights to the expression data
  weighted_expression_data <- coef_file
  weighted_expression_data$Weights <- abs(weighted_expression_data$coefficients) + 1
  expression_data <- X.latent
  gene_weights <- setNames(weighted_expression_data$Weights, rownames(weighted_expression_data))
  common_genes <- intersect(colnames(expression_data), names(gene_weights))
  weighted_expression_matrix <- expression_data
  for (gene in common_genes) {
    weighted_expression_matrix[, gene] <- expression_data[, gene] * gene_weights[gene]
  }
  # Define positive and negative gene sets
  Pos <- pos_file
  Neg <- neg_file
  gene_sets <- list(
    Pos = Pos,
    Neg = Neg
  )
  # Perform ssGSEA
  cc <- t(weighted_expression_matrix)
  Enrichment_score <- gsva(expr = as.matrix(cc), gene_sets, kcdf = "Gaussian", method = "ssgsea", abs.ranking = TRUE)
  score <- Enrichment_score["Pos", ] - Enrichment_score["Neg", ]
  score <- as.data.frame(score)
  Enrichment_score <- t(Enrichment_score)
  # Check if row names match
  check_row_names <- function(score, Enrichment_score) {
    if (all(rownames(score) == rownames(Enrichment_score))) {
      return(TRUE)
    } else {
      return(FALSE)
    }
  }
  if (check_row_names(score, Enrichment_score)) {
    message("The row names of both matrices match")
  } else {
    message("The row names of both matrices do not match")
  }
  # Add the final scores to the enrichment results
  Enrichment_score <- as.data.frame(Enrichment_score)
  Enrichment_score$Score <- score$score
  Enrichment_score$Sample <- rownames(Enrichment_score)
  return(Enrichment_score)
}



