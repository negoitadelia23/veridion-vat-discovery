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
#duck duck go search for loop
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
        #here it checks the val_vat function
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

library(jsonlite)
#testing the hmrc api 
client_id <- "id"
client_secret <- "secret"
#for security measures, I didn't put the actual id and secret
#get token function
get_hmrc_token <- function(id, secret) {
  token_url <- "https://test-api.service.hmrc.gov.uk/oauth/token"
  response <- POST(
    token_url,
    body = list(
      client_id = id,
      client_secret = secret,
      grant_type = "client_credentials"
    ),
    encode = "form"
  )
  
  if (status_code(response) == 200) {
    parsed <- fromJSON(content(response, as = "text", encoding = "utf-8"))
    return(parsed$access_token)
  } else {
    stop("Token generation error. Please check if you are inside the Sandbox Environment.")
  }
}
  
my_token <- get_hmrc_token(client_id, client_secret)
#now we check the vat with the one we found
check_hmrc_vat <-function(vat, token){
  clean_num <- gsub("^GB", "", toupper(trimws(vat)))
  api_url <- paste0("https://test-api.service.hmrc.gov.uk/organisations/vat/check-vat-number/lookup/", clean_num)
  response <- tryCatch({
    GET(api_url, 
        add_headers(
          Accept = "application/vnd.hmrc.2.0+json",
          Authorization = paste("Bearer", token)
        ))
  }, error = function(e) NULL)
  if (is.null(response) || status_code(response) != 200) {
    return(list(valid = FALSE, company_name = "ERROR/Doesn't exist"))
  }
  
  content_text <- content(response, as = "text", encoding = "utf-8")
  parsed <- fromJSON(content_text)
  if (!is.null(parsed$target$name)) {
    return(list(
      valid = TRUE,
      company_name = parsed$target$name,
      address = parsed$target$address$line1
    ))
  } else {
    return(list(valid = FALSE, company_name = NA))
  }
}
#getting valid_vats where the validity is true AND the vat id isn't NA
valid_vats <- final_vat_results$vat[final_vat_results$valid == TRUE & final_vat_results$vat != "Not found/NA"]
hmrc_verification_results <- do.call(rbind, lapply(valid_vats, function(v) {
  res <- check_hmrc_vat(v, my_token)
  data.frame(
    input_vat = v,
    hmrc_valid = res$valid,
    official_name = ifelse(is.null(res$company_name), NA, res$company_name),
    stringsAsFactors = FALSE
  )
}))
hmrc_verification_results
#the sandbox environment doesn't let me have access to actual company data


#!!! SCALABILITY TEST !!!
#as documented in the README, I tested scalability using a different dataset
# increased the sample size
# slice_sample(n=35) %>%
# pull(Name)
#in the case of that dataset, the "Supplier.Name" variable is called Name 
#for(company in scalability_sample){
                #same http req logic as above 
      #added a human-like delay to bypass rate-limiting
      #Sys.sleep(sample(2:4,1))
#}                                          

#the result from that dataset and sample was a 100% failure rate, because of the 403 Forbidden error
