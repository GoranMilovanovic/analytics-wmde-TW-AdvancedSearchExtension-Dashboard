#!/usr/bin/env Rscript

### ---------------------------------------------------------------------------
### --- Advanced Search Extension Update
### --- Script: AdvancedSearchExtension_Update_Production.R
### --- Author: Goran S. Milovanovic, Data Analyst, WMDE
### --- Developed under the contract between Goran Milovanovic PR Data Kolektiv
### --- and WMDE.
### --- Contact: goran.milovanovic_ext@wikimedia.de
### ---------------------------------------------------------------------------
### --- DESCRIPTION:
### --- The script fetches data hourly from log.AdvancedSearchRequest_17379859
### --- and produces the tsv file used on Labs (wikidataconcepts.eqiad.wmflabs)
### --- to update the Extension Report Dashboard.
### ---------------------------------------------------------------------------
### --- RUN FROM: /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/
### --- on crontab
### ---------------------------------------------------------------------------

### ---------------------------------------------------------------------------
### --- LICENSE:
### ---------------------------------------------------------------------------
### --- GPL v2
### --- AdvancedSearchExtension_Update_Production.R is free software: 
### --- you can redistribute it and/or modify
### --- it under the terms of the GNU General Public License as published by
### --- the Free Software Foundation, either version 2 of the License, or
### --- (at your option) any later version.
### ---
### --- AdvancedSearchExtension_Update_Production.R is distributed in 
### --- the hope that it will be useful,
### --- but WITHOUT ANY WARRANTY; without even the implied warranty of
### --- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### --- GNU General Public License for more details.
### ---
### --- You should have received a copy of the GNU General Public License
### --- along with AdvancedSearchExtension_Update_Production.R. 
### --- If not, see <http://www.gnu.org/licenses/>.
### ---------------------------------------------------------------------------

### --- generate asExtensionUpdate.csv update

### --- Setup
library(jsonlite)
library(stringr)
library(data.table)
library(dplyr)

# - crontab: Rscript /srv/home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/AdvancedSearchExtension_Query.R

### -----------------------------------------------------------
### --- produce asExtensionUpdate.csv
### -----------------------------------------------------------

setwd('/home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension')
# - toReport:
print(paste0("Regular SQL update for: Advanced Search Extension on ... ", as.character(Sys.time())))
  
# - Intake A: AdvancedSearchRequest_17841562 schema

sqlLogIn <- 'mysql --defaults-file=/etc/mysql/conf.d/analytics-research-client.cnf -h analytics-slave.eqiad.wmnet -A -e'
query <- '"use log; select id, DATE_FORMAT(timestamp, \'%Y-%m-%d %H:%i:%S\') as timestamp, userAgent, wiki,
event_hastemplate, event_intitle, event_not,
event_or, event_phrase, event_plain, event_filetype
from AdvancedSearchRequest_17841562"'
outFile <- '> /srv/home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/asExtensionUpdate.tsv'
sQuery <- paste(sqlLogIn, query, outFile, sep = " ")
system(sQuery, wait = T)
updateFile <- read.delim('asExtensionUpdate.tsv', sep = "\t")
# - as.POSIXct: updateFile$timestamp
updateFile$timestamp <- as.POSIXct(updateFile$timestamp, tz = "UTC")
# - UTC to CET
attr(updateFile$timestamp, "tzone") <- "Europe/Berlin"
# - filter bots
updateFile <- dplyr::filter(updateFile,
                          grepl("is_bot: false", updateFile$userAgent, fixed = T))
# - remove userAgent
updateFile <- dplyr::select(updateFile, -userAgent)
# - save
write.csv(updateFile, 'asExtensionUpdate_A.csv')
# - delete the unredacted .tsv file
file.remove('asExtensionUpdate.tsv')

# - fix asExtensionUpdate_A.csv
update <- read.csv('asExtensionUpdate_A.csv',
                   header = T, stringsAsFactors = F,
                   row.names = 1)
# - keep three months only
# - as.POSIXct: updateFile$timestamp
update$timestamp <- as.POSIXct(update$timestamp, tz = "UTC")
# - UTC to CET
attr(update$timestamp, "tzone") <- "Europe/Berlin"
start3Months <- tail(update$timestamp, 1)
start3Months <- seq(as.Date(start3Months), length = 2, by = "-3 months")[2]
start3Months <- as.POSIXct(paste0(as.character(start3Months), "00:00:00"), tz = "Europe/Berlin")
update <- dplyr::filter(update,
                        timestamp >= start3Months)
write.csv(update, 'asExtensionUpdate.csv')
file.remove('asExtensionUpdate_A.csv')

### -----------------------------------------------------------
### --- collect from wmf_raw.CirrusSearchRequestSet
### -----------------------------------------------------------

### --- PART 1: Special:Search/Advanced Extension Search

### --- check update
lF <- list.files()
if ("cirrusSearchUpdate.csv" %in% lF) {
  # - load cirrusSearchUpdate.csv
  cirrusSearchUpdate <- read.csv('cirrusSearchUpdate.csv',
                                 header = T,
                                 check.names = F,
                                 row.names = 1,
                                 stringsAsFactors = F)
  # - extract the time of the latest update from cirrusSearchUpdate.csv
  updateY <- tail(cirrusSearchUpdate, 1)$year
  updateM <- tail(cirrusSearchUpdate, 1)$month
  updateD <- tail(cirrusSearchUpdate, 1)$day
  updateDate <- paste(updateY, updateM, updateD, sep = "-")
  updateDate <- as.POSIXct(updateDate)
  updateDate <- updateDate + 60*60*24
  updateDate <- as.integer(strsplit(as.character(updateDate),
                                    split = "-")[[1]])
  # - HiveQL

  # - toReport:
  print(paste0("Running regular update for: ", paste(updateDate, collapse = "-")))

  # - get SpecialSearchCount data:
  hiveQuery <- paste0('"SELECT year, month, day, COUNT(*) AS SpecialSearchCount FROM wmf_raw.CirrusSearchRequestSet WHERE year = ',
                      updateDate[1],
                      ' AND month = ',
                      updateDate[2],
                      ' AND day = ',
                      updateDate[3],
                      ' AND (payload[\'referer\'] LIKE \'%wiki%\') GROUP BY year, month, day;"')
  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdate1.tsv")
  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - toReport:
  print(paste0("Report from running HiveQL for SpecialSearchCount data: ", queryCom))

  # - get AdvancedExtensionCount data:
  hiveQuery <- paste0('"SELECT year, month, day, COUNT(*) AS AdvancedExtensionCount FROM wmf_raw.CirrusSearchRequestSet WHERE year = ',
                      updateDate[1],
                      ' AND month = ',
                      updateDate[2],
                      ' AND day = ',
                      updateDate[3],
                      ' AND (payload[\'referer\'] LIKE \'%wiki%\') AND (payload[\'queryString\'] LIKE \'%advancedSearch-current%\') GROUP BY year, month, day;"')
  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdate2.tsv")
  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - to Report:
  print(paste0("Report from running HiveQL for AdvancedExtensionCount data: ", queryCom))

  # - combine data sets and store cirrusSearchUpdate.csv
  cirrusSearchUpdate_1 <- read.delim('cirrusSearchUpdate1.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)
  cirrusSearchUpdate_2 <- read.delim('cirrusSearchUpdate2.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)
  cirrusUpdate <- data.frame(year = cirrusSearchUpdate_1$year,
                             month = cirrusSearchUpdate_1$month,
                             day = cirrusSearchUpdate_1$day,
                             specialsearchcount = cirrusSearchUpdate_1$specialsearchcount,
                             advancedextensioncount = cirrusSearchUpdate_2$advancedextensioncount,
                             stringsAsFactors = F)
  # - add update and store:
  cirrusSearchUpdate <- rbind(cirrusSearchUpdate, cirrusUpdate)
  write.csv(cirrusSearchUpdate, "cirrusSearchUpdate.csv")
} else {

  # - toReport:
  print("This is the initial intake. Running HiveQL queries and producing the cirrusSearchUpdate.csv file now.")

  # - get SpecialSearchCount data:
  hiveQuery <- '"SELECT year, month, day, hour, COUNT(*) AS SpecialSearchCount FROM wmf_raw.CirrusSearchRequestSet
                  WHERE (year = 2017 OR year = 2018) AND (payload[\'referer\'] LIKE \'%wiki%\') GROUP BY year, month, day, hour;"'
  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdate1.tsv")
  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - toReport:
  print(paste0("Report from running HiveQL for SpecialSearchCount data: ", queryCom))
  
  ### --- wait for 10 minutes
  print("Pausing for 10 minutes.")
  Sys.sleep(10*60)

  # - get AdvancedExtensionCount data:
  hiveQuery <- '"SELECT year, month, day, hour, COUNT(*) AS AdvancedExtensionCount FROM wmf_raw.CirrusSearchRequestSet
  WHERE ((year = 2017 OR year = 2018) AND (payload[\'referer\'] LIKE \'%wiki%\') AND
  (payload[\'queryString\'] LIKE \'%advancedSearch-current%\')) GROUP BY year, month, day, hour;"'
  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdate2.tsv")
  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - toReport:
  print(paste0("Report from running HiveQL for AdvancedExtensionCount data: ", queryCom))
  
  ### --- wait for 10 minutes
  print("Pausing for 10 minutes.")
  Sys.sleep(10*60)

  # - combine data sets and store cirrusSearchUpdate.csv
  cirrusSearchUpdate_1 <- read.delim('cirrusSearchUpdate1.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)
  cirrusSearchUpdate_1$date <- paste(cirrusSearchUpdate_1$year,
                                     cirrusSearchUpdate_1$month,
                                     cirrusSearchUpdate_1$day,
                                     cirrusSearchUpdate_1$hour,
                                     sep = "-")
  cirrusSearchUpdate_2 <- read.delim('cirrusSearchUpdate2.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)
  cirrusSearchUpdate_2$date <- paste(cirrusSearchUpdate_2$year,
                                     cirrusSearchUpdate_2$month,
                                     cirrusSearchUpdate_2$day,
                                     cirrusSearchUpdate_2$hour,
                                     sep = "-")
  # - join
  cirrusSearchUpdate <- left_join(cirrusSearchUpdate_1,
                                  select(cirrusSearchUpdate_2, advancedextensioncount, date),
                                  by = 'date')
  cirrusSearchUpdate$date <- NULL
  # - arrange
  cirrusSearchUpdate <- arrange(cirrusSearchUpdate, year, month, day, hour)
  cirrusSearchUpdate$specialsearchcount[is.na(cirrusSearchUpdate$specialsearchcount)] <- 0
  cirrusSearchUpdate$advancedextensioncount[is.na(cirrusSearchUpdate$advancedextensioncount)] <- 0
  # - aggreate daily and store
  cirrusSearchUpdate <- cirrusSearchUpdate %>%
    select(year, month, day, specialsearchcount, advancedextensioncount) %>%
    group_by(year, month, day) %>%
    summarise(specialsearchcount = sum(specialsearchcount),
              advancedextensioncount = sum(advancedextensioncount))
  # - delete previous day (probably incomplete)
  cirrusSearchUpdate <- cirrusSearchUpdate[-dim(cirrusSearchUpdate)[1], ]
  # - store:
  write.csv(cirrusSearchUpdate, "cirrusSearchUpdate.csv")
}

### --- PART 2: Special:Search/Advanced Extension KEYWORDS

### --- check update
lF <- list.files()
if ("cirrusSearchUpdateKeywords.csv" %in% lF) {
  # - load cirrusSearchUpdate.csv
  cirrusSearchUpdate <- read.csv('cirrusSearchUpdateKeywords.csv',
                                 header = T,
                                 check.names = F,
                                 row.names = 1,
                                 stringsAsFactors = F)
  # - extract the time of the latest update from cirrusSearchUpdate.csv
  updateY <- tail(cirrusSearchUpdate, 1)$year
  updateM <- tail(cirrusSearchUpdate, 1)$month
  updateD <- tail(cirrusSearchUpdate, 1)$day
  updateDate <- paste(updateY, updateM, updateD, sep = "-")
  updateDate <- as.POSIXct(updateDate)
  updateDate <- updateDate + 60*60*24
  updateDate <- as.integer(strsplit(as.character(updateDate),
                                    split = "-")[[1]])
  # - HiveQL

  # - toReport:
  print(paste0("Running regular keywords update for: ", paste(updateDate, collapse = "-")))

  # - get SpecialSearchCount data:
  hiveQuery <- paste0('"SELECT year, month, day, asyn as keyword, count(*) as count
                      FROM wmf_raw.CirrusSearchRequestSet csr
                      LATERAL VIEW EXPLODE(requests) req AS areq
                      LATERAL VIEW EXPLODE(split(areq.payload[\'syntax\'], \',\')) syn as asyn
                      WHERE year = ',
                      updateDate[1],
                      ' AND month = ',
                      updateDate[2],
                      ' AND day = ',
                      updateDate[3],
                      ' AND areq.queryType = \'full_text\' AND csr.source = \'web\' AND
                        (csr.payload[\'referer\'] LIKE \'%wiki%\')
                      GROUP BY year, month, day, asyn;"')

  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdateKeywords1.tsv")

  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - toReport:
  print(paste0("Report from running HiveQL for SpecialSearchCount data: ", queryCom))

  # - get AdvancedExtensionCount data:

  hiveQuery <- paste0('"SELECT year, month, day, asyn as keyword, count(*) as count
                      FROM wmf_raw.CirrusSearchRequestSet csr
                      LATERAL VIEW EXPLODE(requests) req AS areq
                      LATERAL VIEW EXPLODE(split(areq.payload[\'syntax\'], \',\')) syn as asyn
                      WHERE year = ',
                      updateDate[1],
                      ' AND month = ',
                      updateDate[2],
                      ' AND day = ',
                      updateDate[3],
                      ' AND areq.queryType = \'full_text\' AND csr.source = \'web\' AND
                        (csr.payload[\'queryString\'] LIKE \'%advancedSearch-current%\') AND
                        (csr.payload[\'referer\'] LIKE \'%wiki%\')
                      GROUP BY year, month, day, asyn;"')

  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdateKeywords2.tsv")

  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - toReport:
  print(paste0("Report from running HiveQL for AdvancedExtensionCount data: ", queryCom))

  # - combine data sets and store cirrusSearchUpdate.csv
  cirrusSearchUpdate_1 <- read.delim('cirrusSearchUpdateKeywords1.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)
  cirrusSearchUpdate_2 <- read.delim('cirrusSearchUpdateKeywords2.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)
  # - join
  cirrusUpdate <- full_join(cirrusSearchUpdate_1,
                            cirrusSearchUpdate_2,
                            by = c('year', 'month', 'day', 'keyword'))
  colnames(cirrusUpdate)[5:6] <- c('specialsearchcount', 'advancedextensioncount')
  # - add update and store:
  cirrusSearchUpdate <- rbind(cirrusSearchUpdate, cirrusUpdate)
  write.csv(cirrusSearchUpdate, "cirrusSearchUpdateKeywords.csv")
} else {

  # - toReport:
  print("This is the initial intake. Running HiveQL Keywords queries and producing the cirrusSearchUpdateKeywords.csv file now.")

  # - get SpecialSearchCount data:

  hiveQuery <- '"SELECT year, month, day, asyn as keyword, count(*) as count FROM wmf_raw.CirrusSearchRequestSet csr
                  LATERAL VIEW EXPLODE(requests) req AS areq
                  LATERAL VIEW EXPLODE(split(areq.payload[\'syntax\'], \',\')) syn as asyn
                WHERE (year = 2017 OR year = 2018) AND
                  areq.queryType = \'full_text\' AND
                  csr.source = \'web\' AND
                  (csr.payload[\'referer\'] LIKE \'%wiki%\')
                GROUP BY year, month, day, asyn;"'

  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdateKeywords1.tsv")

  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - toReport:
  print(paste0("Report from running HiveQL for Keywords in SpecialSearchCount data: ", queryCom))

  ### --- wait for 10 minutes
  print("Pausing for 10 minutes.")
  Sys.sleep(10*60)

  # - get AdvancedExtensionCount data:
  hiveQuery <- '"SELECT year, month, day, asyn as keyword, count(*) as count FROM wmf_raw.CirrusSearchRequestSet csr
                    LATERAL VIEW EXPLODE(requests) req AS areq
                    LATERAL VIEW EXPLODE(split(areq.payload[\'syntax\'], \',\')) syn as asyn
                WHERE (year = 2017 OR year = 2018) AND
                  areq.queryType = \'full_text\' AND
                  csr.source = \'web\' AND
                  (csr.payload[\'referer\'] LIKE \'%wiki%\') AND
                  (csr.payload[\'queryString\'] LIKE \'%advancedSearch-current%\')
                GROUP BY year, month, day, asyn;"'
  hiveQLQueryCommand <- paste0("/usr/local/bin/beeline --silent=true --incremental=true -e ",
                               hiveQuery,
                               " > /home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdateKeywords2.tsv")
  queryCom <- system(command = hiveQLQueryCommand, wait = TRUE)

  # - toReport:
  print(paste0("Report from running HiveQL for Keywords AdvancedExtensionCount data: ", queryCom))

  # - combine data sets and store cirrusSearchUpdate.csv
  cirrusSearchUpdate_1 <- read.delim('cirrusSearchUpdateKeywords1.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)

  cirrusSearchUpdate_2 <- read.delim('cirrusSearchUpdateKeywords2.tsv',
                                     sep = "\t",
                                     quote = "",
                                     check.names = F,
                                     stringsAsFactors = F)
  # - join
  cirrusSearchUpdate <- full_join(cirrusSearchUpdate_1,
                                  cirrusSearchUpdate_2,
                                  by = c('year', 'month', 'day', 'keyword'))
  colnames(cirrusSearchUpdate)[5:6] <- c('specialsearchcount', 'advancedextensioncount')
  # - arrange
  cirrusSearchUpdate$specialsearchcount[is.na(cirrusSearchUpdate$specialsearchcount)] <- 0
  cirrusSearchUpdate$advancedextensioncount[is.na(cirrusSearchUpdate$advancedextensioncount)] <- 0
  cirrusSearchUpdate <- arrange(cirrusSearchUpdate, year, month, day, keyword)
  # - delete previous day (probably incomplete)
  cirrusSearchUpdate <- cirrusSearchUpdate[-dim(cirrusSearchUpdate)[1], ]
  # - store:
  write.csv(cirrusSearchUpdate, "cirrusSearchUpdateKeywords.csv")
}

### ------------------------------------------------------------------
### - Copy files to public data sets:

system(command = 'cp /srv/home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/asExtensionUpdate.csv /srv/published-datasets/wmde-analytics-engineering/TechnicalWishes/AdvancedSearchExtension/',
       wait = T)

system(command = 'cp /srv/home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdate.csv /srv/published-datasets/wmde-analytics-engineering/TechnicalWishes/AdvancedSearchExtension/',
       wait = T)

system(command = 'cp /srv/home/goransm/RScripts/TechnicalWishes/AdvancedSearchExtension/cirrusSearchUpdateKeywords.csv /srv/published-datasets/wmde-analytics-engineering/TechnicalWishes/AdvancedSearchExtension/',
       wait = T)
