###Installation and Usage Instructions

library(devtools)

devtools::install_github("Lai-Guichuan/SPRA")

library(SPRA)

filtered_gene_sets <- readRDS("filtered_gene_sets.rds")

coef_file <- readRDS("coef_file.rds")

pos_file <- readRDS("pos_file.rds")

neg_file <- readRDS("neg_file.rds")

expr_file <- "TPM.txt"

result <- calculate_total_score(expr_file, filtered_gene_sets, coef_file, pos_file, neg_file)

write.table(result, file = "PBIS-TP53.txt", sep = "\t", quote = FALSE)
