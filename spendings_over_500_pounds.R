library(readxl)
library(tidyverse)
df<-read.csv("spend500dec2015.csv",header=T, sep=",")
head(df)
companies <- df %>%
  filter(str_detect(str_to_lower(`Supplier Name`), "ltd|limited")) %>%
  distinct(`Supplier Name`)
#using tidyverse and dplyr to extract companies faster
