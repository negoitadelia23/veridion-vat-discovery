library(readxl)
library(tidyverse)
df<-read.csv("spend500dec2015.csv",header=T, sep=",")
head(df)
#using tidyverse and dplyr to extract companies faster
ltd_suppliers <- df %>%
  filter(str_detect(str_to_lower(Supplier.Name), "ltd|limited")) %>%
  distinct(Supplier.Name)
#extracting a random sample out of all the companies
set.seed(123)
ltd_sample <- ltd_suppliers %>%
  slice_sample(n = 10) %>%
  pull(Supplier.Name)
ltd_sample
library(rvest)
library(httr)
library(stringr)

val_vat<-function(vat){
  clean_vat <- gsub("^GB", "", toupper(trimws(vat)))
  #we need to have this format : GB123456789. after gsub it is gonna
  #be 123456789
  if(!grepl("^\\d{9}$", clean_vat)){
    return (FALSE)
  } #if its not 9 digits return false
  digits <- as.numeric(strsplit(clean_vat,"")[[1]])
  weights<-8:2 #weights used in the alg
  s<-sum(digits[1:7] * weights)
  check<-digits[8]*10+digits[9]
  total<-s+check
  val<-(total %% 97 == 0) || 
      ((total - 27) %% 97 == 0) || 
      ((total - 55) %% 97 == 0) #returns true or false
  #depending on the results
  return(val)
}

results_list<-list()

for(company in ltd_sample){
  query<-URLencode(paste(company, "UK VAT number"))
  url<-paste0("https://html.duckduckgo.com/html/?q=", query)
  
  response<-tryCatch(
    GET(url, user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"))
, error = function(e) NULL)
  if (is.null(response) || status_code(response) != 200) {
    results_list[[company]] <- data.frame(company = company, vat = NA, valid = FALSE)
    next
  }
  page_text <- content(response, as = "text", encoding = "utf-8")
  matched_vats <- unlist(regmatches(page_text, gregexpr("(?:GB)?\\s*\\d{9}", page_text, ignore.case = TRUE)))
  
  valid_vat_found <- NA
  is_valid_check <- FALSE
  if(length(matched_vats)){
    for (v in unique(matched_vats)) {
      if (val_vat(v)) {
        valid_vat_found <- v
        is_valid_check <- TRUE
        break
      }
    }
  }
  results_list[[company]] <- data.frame(
    company = company, 
    vat = ifelse(is.na(valid_vat_found), "Not found/NA", valid_vat_found), 
    valid = is_valid_check
  )
  Sys.sleep(1)
}

final_vat_results <- do.call(rbind, results_list)
rownames(final_vat_results) <- NULL
final_vat_results  

