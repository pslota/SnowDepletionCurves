AnnualMax<-function(model,sdcNum){
  print (model)
  ###Read in Data from STATVAR file
  # read in the PRMs variable names
  vars<-as.data.frame(fread(paste(model,"/default",sdcNum,".statvar",sep=""),sep=" ",skip=1,nrows=26))
  PRMSvars<-vars$V1
  # read in the PRMS variable values
  vals<-as.data.frame(fread(paste(model,"/default",sdcNum,".statvar",sep=""),sep=" ",header=F,skip=27))
  # define column names
  colnames(vals)<-c("timestep","year","month","day","hour","minute","second",PRMSvars)
  
  # create dates and convert to water years
  vals$date<-as.Date(paste(vals$year,"-",vals$month,"-",vals$day,sep=""))
  vals$wyears<-as.numeric(levels(waterYear(vals$date))[waterYear(vals$date)])
  
  # remove columns we are not interested in
  vals<-vals[,!(names(vals) %in% c("timestep","month","day","hour","minute","second",NA,"basin_intcp_stor","basin_lake_stor",
                                   "basin_gwsink","basin_recharge"))]
  
  # melt the dataframe
  meltVals<-melt(vals,id=c("date","wyears"),stringsasFactors=F)
  meltVals<-rename(meltVals,PRMSvar=variable)
  # seven-yr rolling mean
  #meltVals<-meltVals %>% group_by(variable) %>% mutate(Roll=rollmean(value,k=7,fill=NA,align="center"))
  
  # Get Max Values for peakswe and corresponding date
  meltVals2<-meltVals %>% filter(PRMSvar == "basin_pweqv")
  yearMax<-meltVals2 %>% arrange(desc(value)) %>%group_by(PRMSvar,wyears) %>%filter(row_number() <= 1L)
  # order by water year and Max Value
  yearMax2<-yearMax[order(yearMax$PRMSvar,yearMax$wyears),]
  # Subset only to variables we are interested in 
  yearMax3<-yearMax2 %>% filter(PRMSvar %in% c("basin_sroff","basin_pweqv","basin_snowmelt","basin_snowcov","basin_cfs"))
  # Rename the Max column to something more meaning fule
  yearMax3<-rename(yearMax3,MaxVal=value)
  yearMax3<-yearMax3[,!(names(yearMax3) == "PRMSvar")]
  
  # Get SWE time series
# Find the dates where SWE is greater than 0
  sweDates<-meltVals$date[which(meltVals$PRMSvar=="basin_pweqv"& meltVals$value>0)]
  # Extract rows from Dframe for the other variables where their dates match SWE dates
  yearMin<-meltVals[which(meltVals$date %in% sweDates),]
  # subset to the variables we are interested in
  yearMin2<-yearMin %>% filter(PRMSvar %in% c("basin_sroff","basin_pweqv","basin_snowmelt","basin_snowcov","basin_cfs"))
  # value is the actual variable value
  # join to the yearMax3 dataframe to bring over the max value
  newMat<- left_join(yearMin2,yearMax3,by="wyears")
  newMat<- rename(newMat,maxSWEdate=date.y,maxSWE=MaxVal)
  
  # create a binary time series based on whether date is in the melt period
  # and subset data frame by the melt period
  MeltPer<-ifelse(newMat$date.x >= newMat$maxSWEdate,1,0)
  newMat$MeltPer<-MeltPer
  newMat2<-newMat %>% filter(MeltPer==1)
  
  varMax<-newMat2 %>% arrange(desc(value)) %>%group_by(PRMSvar,wyears) %>%filter(row_number() <= 1L)
  # order by water year and Max Value
  varMax2<-varMax[order(varMax$PRMSvar,varMax$wyears),]
 # Rename the Max column to something more meaning fule
  varMax3<-rename(varMax2,MaxVal=value)
  #varsMax3<-yearMax3[,!(names(yearMax3) == "PRMSvar")]
  varMax3<-varMax3[,!(names(newMat2) %in% c("maxSWEdate","maxSWE","MeltPer"))]
  
  newMat3<-left_join(newMat2,varMax3,by=c("PRMSvar","wyears"))
  
  # Summarize statistics
  # number of days in melt period
  NumDays_meltPeriod_total<-newMat3 %>% group_by(PRMSvar)%>% summarise(count=sum(MeltPer))
  NumDays<-NumDays_meltPeriod_total[1,2]
  
  # standard deviation of length of melt period
  MeltPeriod_byYR<-newMat3 %>% group_by(PRMSvar,wyears) %>% summarise (sum=sum(MeltPer))
  MeltYrs<-unlist(MeltPeriod_byYR[which(MeltPeriod_byYR$PRMSvar=="basin_pweqv"),3])
  sdMelt<-sd(MeltYrs,na.rm=TRUE)
  
  # total volume of melt period
  Vol_total<-as.data.frame(newMat3 %>% group_by(PRMSvar)%>% summarise(count=sum(value,na.rm=TRUE)))
  melt_total<-Vol_total[2,2]
  sroff_total<-Vol_total[4,2]
  cfs_total<-Vol_total[5,2]
  #evap total
  
  # difference in days between PeakSWE and peaksnowmelt, peakrunoff, basin cfs
  # peakSWEdate,peakMeltDate,peakRODate, peakCFSDate
  Diff_date<-newMat3 %>% group_by(PRMSvar,wyears) %>% mutate(ddiff=maxSWEdate-date.x.y)
  Diff<-Diff_date %>% arrange(desc(date.x.y)) %>%group_by(PRMSvar,wyears) %>%filter(row_number() <= 1L)
  #Mean_by_Group<-Diff %>% group_by(PRMSvar) %>% summarise(mean=mean(ddiff))
  #Sd_by_Group<-Diff %>% group_by(PRMSvar) %>% summarise(sd=sd(ddiff))
  Diff_by_Group<-Diff %>% group_by(PRMSvar) %>% summarise_each(funs(mean,sd),ddiff)
  melt_diff<-Diff_by_Group[2,2]
  melt_sd<-Diff_by_Group[2,3]
  
  run_diff<-Diff_by_Group[4,2]
  run_sd<-Diff_by_Group[4,3]
  
  cfs_diff<-Diff_by_Group[5,2]
  cfs_sd<-Diff_by_Group[5,3]
  
  outVec<-c(as.numeric(NumDays),mean(MeltYrs),sdMelt,melt_total,sroff_total,cfs_total,as.numeric(melt_diff),
            melt_sd,as.numeric(run_diff),run_sd,as.numeric(cfs_diff),cfs_sd)
  return(outVec)
}