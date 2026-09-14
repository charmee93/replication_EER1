* ************************************************************
* Master do file to replicate
* "The Unintended Cost of Distance Learning: An Analysis of Child Maltreatment"

* Author: Sungmee Kim

* ************************************************************

* Master Replication File

* This master file runs all data preparation, dataset construction, 
* empirical analysis, and output-generation programs required to replicate 
* the results reported in
* "The Unintended Cost of Distance Learning: An Analysis of Child Maltreatment."

* Programs are executed in the following order:

* 0.0  Prepare remote-learning data
* 0.1  Prepare raw data for control variables
* 0.2  Prepare NVSS mortality data
* 0.3  Prepare NCANDS Child File data
* 0.4  Prepare hypothetical county data
* 1.1  Construct master county-level dataset
* 1.2  Construct aggregated county-level dataset
* 1.3  Construct master state-level dataset
* 2.1  Generate figures
* 2.2  Generate tables
* 3.1  Run county-level regressions
* 3.2  Run state-level regressions

* ************************************************************
* Set Working Folder           
* ************************************************************

global dir "[project folder]"

global data "${dir}data/"
global datao "${data}original/"
global datap "${data}processed/"
global output "${dir}output/"

* ************************************************************
* 0.0. Prep remote learning
* ************************************************************

clear all

*-------------------------------------------*
* 0) import raw remote learning data
*-------------------------------------------*

// 2020-21

import delimited "${datao}School_Learning_Modalities__2020-2021_20240514.csv", stringcols(1) clear 
replace city = lower(city)

*--------------------------------*

* extract month & year from week variable
split week, p("")
gen date = date(week1, "MDY")
format %td date

gen year = year(date)
gen month = month(date)
gen day = day(date)

drop week2 week3

*--------------------------------*

* gen learning mode dummies
tab learning_modality, m
gen prop_remote = 1 if learning_modality == "Remote"
replace prop_remote = 0.5 if learning_modality == "Hybrid"
replace prop_remote = 0 if learning_modality == "In Person"

*--------------------------------*

keep district_nces_id learning_modality operational_schools student_count state date year month day prop_remote
rename (district_nces_id student_count) (leaid total_student_count)

save "${datap}remote SY21.dta", replace

*-------------------------------------------*
*-------------------------------------------*

// 2021-22

import delimited "${datao}School_Learning_Modalities__2021-2022.csv", stringcols(1) clear 
replace city = lower(city)

*--------------------------------*

* extract month & year from week variable
split week, p("")
gen date = date(week1, "MDY")
format %td date

gen year = year(date)
gen month = month(date)
gen day = day(date)

drop week2 week3

*--------------------------------*

* gen learning mode dummies
tab learningmodality, m
gen prop_remote = 1 if learningmodality == "Remote"
replace prop_remote = 0.5 if learningmodality == "Hybrid"
replace prop_remote = 0 if learningmodality == "In Person"

*--------------------------------*

keep districtncesid learningmodality operationalschools studentcount state date year month day prop_remote
rename (districtncesid learningmodality operationalschools studentcount) (leaid learning_modality operational_schools total_student_count)

save "${datap}remote SY22.dta", replace

*-------------------------------------------*
* 1) construct 1:1 zipcode-county crosswalk
*-------------------------------------------*
import excel "${datao}ZIP_COUNTY_032024.xlsx", sheet("Export Worksheet") firstrow clear

// keep the observations with highest total ratio + check duplicates
gen t_ratio = round(TOT_RATIO, .0001)
bys ZIP: egen max = max(t_ratio)
keep if t_ratio == max

// still some duplicates. keep the observations with highest resident ratio + check duplicates
gen r_ratio = round(RES_RATIO, .0001)
bys ZIP: egen max2 = max(r_ratio)
keep if r_ratio == max2

// ZIP=51603 not in our school universe data. just drop
drop if ZIP=="51603"

keep ZIP COUNTY USPS_ZIP_PREF_STATE
rename (ZIP COUNTY USPS_ZIP_PREF_STATE) (zipcode countyfips stateabbr)

// drop bureau of indian education, guam, northern marianas, puerto rico, us virgin islands
drop if stateabbr=="BI" | stateabbr=="GU" | stateabbr=="MP" | stateabbr=="PR" | stateabbr=="VI"

replace county="02232" if county=="02105" | county=="02230"
replace county="02261" if county=="02063" | county=="02066"

save "${datap}countyzip crosswalk.dta", replace

*-------------------------------------------*
* 2) clean school universe data & merge zip + student count
*-------------------------------------------*
// import school directory to extract zipcode
import delimited "${datao}CCD NCES/ccd_sch_029_2021_w_1a_080621.csv", stringcols(2 10 12 13 19) clear 
keep fipst statename st leaid ncessch schid lzip sch_type_text sch_type

save "${datap}CCD School Directory SY21.dta", replace

// import school membership to extract student count & merge directory into membership
import delimited "${datao}CCD NCES/ccd_SCH_052_2021_l_1a_080621.csv", stringcols(2 9 11 12) clear 
keep if total_indicator=="Education Unit Total"
keep fipst statename st leaid ncessch schid student_count 
keep if student_count!=0 & student_count!=.

save "${datap}CCD School Membership SY21.dta", replace

merge 1:1 schid using "${datap}CCD School Directory SY21.dta"
keep if _merge==3	// only keep schools with student count
drop _merge

rename (fipst st) (statefips stateabbr)

tostring lzip, replace format(%05.0f)

rename lzip zipcode		// use location zipcode to assign each school to unique county

// drop bureau of indian education, guam, northern marianas, puerto rico, us virgin islands
drop if stateabbr=="BI" | stateabbr=="GU" | stateabbr=="MP" | stateabbr=="PR" | stateabbr=="VI"

*-------------------------------------------*
* 3) merge zipcode-county & construct school-district-county student counts
*-------------------------------------------*

merge m:1 zipcode using "${datap}countyzip crosswalk.dta"
keep if _merge==3
drop _merge

order ncessch leaid schid statefips stateabbr statename zipcode countyfips student_count

// there are some schools that zipcode-county crosswalk resulted in discrepancy between statefips & corresponding countyfips. there aren't many. drop them.
gen str2 countyfips_prefix = substr(countyfips, 1, 2)
list zipcode if statefips!=countyfips_prefix

drop if statefips!=countyfips_prefix

save "${datap}CCD School-County Crosswalk SY21.dta", replace

*-------------------------------------------*
* 4) construct district-county student counts (collapse by district-county)
*-------------------------------------------*
// only keep Regular School
keep if sch_type==1

// calculate student count by district-county
collapse (sum) student_count, by(leaid statefips stateabbr statename countyfips)

// reshape wide to merge
bys leaid (countyfips): egen count=seq()
reshape wide countyfips student_count, i(leaid statefips stateabbr statename) j(count)
save "${datap}CCD District-County Crosswalk SY21.dta", replace

*-------------------------------------------*
* 5) merge remote + district-county student count (2021)
*-------------------------------------------*
use "${datap}remote SY21.dta", clear

merge m:1 leaid using "${datap}CCD District-County Crosswalk SY21.dta"
keep if _merge==3
drop _merge

drop state
replace statename = proper(statename)

// reshape long, to collapse by county
reshape long countyfips student_count, i(statefips leaid learning_modality operational_schools total_student_count date year month day) j(count)

drop if missing(student_count)
order statefips stateabbr statename

*-------------------------------------------*
* 6) collapse (mean) prop_remote... (2021)
*-------------------------------------------*
// county-month
preserve

collapse (mean) prop_remote [w=student_count], by(statefips stateabbr statename countyfips year month)

save "${datap}remote SY21 county.dta", replace

restore

// state (for state-level analysis)
gen schoolyear=2021

preserve

collapse (mean) prop_remote [w=student_count], by(statefips stateabbr statename schoolyear)
rename schoolyear year

save "${datap}remote SY21 state.dta", replace

restore

*-------------------------------------------*
* 5) merge remote + district-county student count (2022)
*-------------------------------------------*
use "${datap}remote SY22.dta", clear
keep if (year==2021 & inrange(month, 9, 12)) | (year==2022 & inrange(month, 1, 5))

merge m:1 leaid using "${datap}CCD District-County Crosswalk SY21.dta"
keep if _merge==3
drop _merge

drop state
replace statename = proper(statename)

// reshape long, to collapse by county
reshape long countyfips student_count, i(statefips leaid learning_modality operational_schools total_student_count date year month day) j(count)

drop if missing(student_count)
order statefips stateabbr statename

*-------------------------------------------*
* 6) collapse (mean) prop_remote... (2022)
*-------------------------------------------*
// county-month
preserve

collapse (mean) prop_remote [w=student_count], by(statefips stateabbr statename countyfips year month)

save "${datap}remote SY22 county.dta", replace

restore

// state (for state-level analysis)
gen schoolyear=2021

preserve

collapse (mean) prop_remote [w=student_count], by(statefips stateabbr statename schoolyear)
rename schoolyear year

save "${datap}remote SY22 state.dta", replace

restore

* ************************************************************
* 0.1. Prep raw (controls) data
* ************************************************************

* Controls data list

* 1) COVID cases+deaths
* 2) SEER population by single age
* 3) BLS unemp
* 4) SAIPE

* ************************************************************

clear all

*-------------------------------------------*
* 1) COVID cases+deaths
*-------------------------------------------*

import delimited "${datao}Weekly_United_States_COVID-19_Cases_and_Deaths_by_County_-_ARCHIVED_20240906.csv", numericcols(1 4 6 7 8 9) clear

// county-month
split date, p("/")
destring date*, replace
rename (date1 date2 date3) (month day year)
rename (fips_code state_fips state) (countyfips statefips stateabbr)

drop date cumulative*

collapse (sum) newcases newdeaths, by(month year statefips countyfips stateabbr)

// drop state observations (those countyfips ending with "000")
drop if mod(countyfips, 1000) == 0

// incorporate AK county fips changes
replace countyfips=2261 if countyfips==2063 | countyfips==2066
replace countyfips=2232 if countyfips==2105 | countyfips==2230

collapse (sum) newcases newdeaths, by(month year stateabbr statefips countyfips)
tostring countyfips, replace format(%05.0f)

drop if stateabbr=="PR"	// drop Puerto Rico

save "${datap}covid2020_2023_county.dta", replace

		// state (for state-level analysis)
		rename year calendaryear
		gen year = calendaryear if inrange(month, 1, 9)
		replace year = calendaryear + 1 if inrange(month, 10, 12)
		
		collapse (sum) newcases newdeaths, by(year statefips stateabbr)
		
		save "${datap}covid2020_2023_state.dta", replace

*-------------------------------------------*
* 2) SEER population by single age
*-------------------------------------------*

import delimited "${datao}SEER/us.1990_2023.singleages.through89.90plus.adjusted.txt", clear 

gen year = substr(v1, 1, 4)
keep if year >= "2010"
gen stateabbr = substr(v1, 5, 2)
gen statefips = substr(v1, 7, 2)
gen countyfips = substr(v1, 7, 5)

// race & hispanic & sex
gen race = substr(v1, 14, 1)
gen hispanic = substr(v1, 15, 1)
gen sex = substr(v1, 16, 1)
gen female = (sex == "2")

// age & pop
gen age = substr(v1, 17, 2)
gen pop = substr(v1, 19, 8)

drop v1 sex

destring year race hispanic female age pop, replace

gen agegroup = age if inrange(age, 0, 19)
replace agegroup = 20 if inrange(age, 20, 29)
replace agegroup = 30 if inrange(age, 30, 39)
replace agegroup = 40 if inrange(age, 40, 49)
replace agegroup = 50 if inrange(age, 50, 59)
replace agegroup = 60 if inrange(age, 60, 69)
replace agegroup = 70 if inrange(age, 70, 79)
replace agegroup = 80 if age>=80

// AK county fips recoded/changes
replace county="02232" if county=="02105" | county=="02230"
replace county="02261" if county=="02063" | county=="02066"
replace county="02158" if county=="02270"

drop if county=="02201" | county=="02280"

// SD county fips recoded
replace county="46102" if county=="46113"

// VA county fips recoded
replace county="51019" if county=="51917"

save "${datap}SEER population_lv1.dta", replace

// race-age & total race
preserve

collapse (sum) pop, by(year stateabbr statefips countyfips race)
reshape wide pop, i(year stateabbr statefips countyfips) j(race)
rename (pop1 pop2 pop3 pop4) (popwhite popblack popaian popasian)

tempfile racetotal
save `racetotal'

restore

preserve

collapse (sum) pop, by(year stateabbr statefips countyfips race agegroup)
reshape wide pop, i(year stateabbr statefips countyfips agegroup) j(race)
rename (pop1 pop2 pop3 pop4) (popwhite popblack popaian popasian)
reshape wide pop*, i(year stateabbr statefips countyfips) j(agegroup)

tempfile raceage
save `raceage'

restore

// hispanic-age & total hisp
preserve

collapse (sum) pop, by(year stateabbr statefips countyfips hispanic)
reshape wide pop, i(year stateabbr statefips countyfips) j(hispanic)
rename (pop0 pop1) (popnonhisp pophisp)

tempfile hisptotal
save `hisptotal'

restore

preserve

collapse (sum) pop, by(year stateabbr statefips countyfips hispanic agegroup)
reshape wide pop, i(year stateabbr statefips countyfips agegroup) j(hispanic)
rename (pop0 pop1) (popnonhisp pophisp)
reshape wide pop*, i(year stateabbr statefips countyfips) j(agegroup)

tempfile hispage
save `hispage'

restore

// sex-age & sex total
preserve

collapse (sum) pop, by(year stateabbr statefips countyfips female)
reshape wide pop, i(year stateabbr statefips countyfips) j(female)
rename (pop0 pop1) (popmale popfemale)

tempfile sextotal
save `sextotal'

restore

preserve

collapse (sum) pop, by(year stateabbr statefips countyfips female agegroup)
reshape wide pop, i(year stateabbr statefips countyfips agegroup) j(female)
rename (pop0 pop1) (popmale popfemale)
reshape wide pop*, i(year stateabbr statefips countyfips) j(agegroup)

tempfile sexage
save `sexage'

restore

// age total & total
collapse (sum) pop, by(year stateabbr statefips countyfips agegroup)

preserve
reshape wide pop, i(year stateabbr statefips countyfips) j(agegroup)
tempfile agewide
save `agewide'
restore

collapse (sum) pop, by(year stateabbr statefips countyfips)

// "total" total

//  + merge all
merge 1:1 year stateabbr statefips countyfips using `agewide'
drop _merge
merge 1:1 year stateabbr statefips countyfips using `racetotal'
drop _merge
merge 1:1 year stateabbr statefips countyfips using `hisptotal'
drop _merge
merge 1:1 year stateabbr statefips countyfips using `sextotal'
drop _merge
merge 1:1 year stateabbr statefips countyfips using `raceage'
drop _merge
merge 1:1 year stateabbr statefips countyfips using `hispage'
drop _merge
merge 1:1 year stateabbr statefips countyfips using `sexage'
drop _merge

save "${datap}SEER population_county.dta", replace

// state (for state-level analysis)

collapse (sum) pop*, by(year stateabbr statefips)

save "${datap}SEER population_state.dta", replace

*-------------------------------------------*
* 3) BLS unemp
*-------------------------------------------*

* 2010-2019

forvalues i=10/19{
	
	import excel "${datao}BLS/laucnty`i'.xlsx", sheet("laucnty`i'") firstrow clear
	keep statefips countyfips countyname year laborforce unemp
	drop if missing(unemp)

	// construct fips code
	gen temp = statefips + countyfips
	drop *fips
	destring temp year, replace
	rename temp countyfips
	
	// extract state
	split countyname, p(", ")
	rename (countyname1 countyname2) (county stateabbr)
	drop countyname
	replace stateabbr = "DC" if missing(stateabbr) // DC

	order stateabbr county countyfips year laborforce unemp
	
	tempfile unemp`i'_county
	save `unemp`i'_county'

}

* 2020 - no emp data for PR ("N.A.")
import excel "${datao}BLS/laucnty20.xlsx", sheet("laucnty20") firstrow clear
keep statefips countyfips countyname year laborforce unemp
drop if missing(unemp)
drop if unemp == "N.A."

destring laborforce, replace

// construct fips code
gen temp = statefips + countyfips
drop *fips
destring temp year unemp, replace
rename temp countyfips
	
// extract state
split countyname, p(", ")
rename (countyname1 countyname2) (county stateabbr)
drop countyname
replace stateabbr = "DC" if missing(stateabbr) // DC

order stateabbr county countyfips year laborforce unemp
	
	tempfile unemp20_county
	save `unemp20_county'

* 2021-2023
	
forvalues i=21/23{
	
	import excel "${datao}BLS/laucnty`i'.xlsx", sheet("laucnty`i'") firstrow clear
	keep statefips countyfips countyname year laborforce unemp
	drop if missing(unemp)
	
	// construct fips code
	gen temp = statefips + countyfips
	drop *fips
	destring temp year, replace
	rename temp countyfips
	
	// extract state
	split countyname, p(", ")
	rename (countyname1 countyname2) (county stateabbr)
	drop countyname
	replace stateabbr = "DC" if missing(stateabbr) // DC

	order stateabbr county countyfips year laborforce unemp
	
	tempfile unemp`i'_county
	save `unemp`i'_county'

}

*--------------------------------*

* append 2010-2023 county

clear all

forvalues i=10/23{
	
	append using `unemp`i'_county'
	
}

// AK county fips recoded/changes
replace countyfips=2232 if countyfips==2105 | countyfips==2230
replace countyfips=2261 if countyfips==2063 | countyfips==2066

tostring countyfips, replace format(%05.0f) 

sort stateabbr countyfips year

collapse (sum) laborforce (mean) unemp, by(stateabbr countyfips year)

save "${datap}unemp2010_2023_county.dta", replace

// state (for state-level analysis)

collapse (sum) laborforce (mean) unemp, by (stateabbr year)

sort stateabbr year

save "${datap}unemp2010_2023_state.dta", replace

*-------------------------------------------*
* 4) SAIPE
*-------------------------------------------*

// SAIPE CT 2022_23
/*
// change to county-equivalents in the State of Connecticut

// Fairfield (9001) = Greater Bridgeport (9120) + Western Connecticut (9190)
/// Hartford (9003) 0.857 + Tolland (9013) 0.143 = Capitol (9110)
// Litchfield (9005) = Northwest Hills (9160)
// Middlesex (9007) = Lower Connecticut River Valley (9130)
// New Haven (9009) = Naugatuck Valley (9140) + South Central Connecticut (9170)
// New London (9011) = Southeastern Connecticut (9180)
// Windham (9015) = Northeastern Connecticut (9150)
*/

import excel "${datao}saipe_CT.xlsx", sheet("Sheet1") firstrow case(lower) clear
drop i j

destring countyfips, replace
format poverty* %6.2f
format medhhincome %9.0f

save "${datap}saipe_CT.dta", replace

* 2010-23

forvalues i = 10/11 {

	import excel "${datao}SAIPE/est`i'all.xls", sheet("est`i'ALL") firstrow allstring clear

	// drop states
	drop if CountyFIPSCode == "0"
	
	// replace countyfips to have same length
	replace CountyFIPSCode = "00"+CountyFIPSCode if length(CountyFIPSCode) == 1
	replace CountyFIPSCode = "0"+CountyFIPSCode if length(CountyFIPSCode) == 2

	// keep necessary variables
	keep StateFIPSCode CountyFIPSCode PostalCode Name PovertyPercentAllAges PovertyPercentAge017 PovertyPercentAge517inFam MedianHouseholdIncome

	// rename variables
	rename (PostalCode Name PovertyPercentAllAges PovertyPercentAge017 PovertyPercentAge517inFam MedianHouseholdIncome) ///
		(stateabbr countyname poverty_pct_all poverty_pct_017 poverty_pct_517 medhhincome)

	// generate county fips
	gen countyfips = StateFIPSCode + CountyFIPSCode

	// destring variables
	destring countyfips poverty_pct_all poverty_pct_017 poverty_pct_517 medhhincome, replace

	drop StateFIPSCode CountyFIPSCode
	
	// generate year
	gen year = 20`i'
	
	order countyfips year

	tempfile saipe`i'_county
	save `saipe`i'_county'
	
}

forvalues i = 12/21 {
	import excel "${datao}SAIPE/est`i'all.xls", sheet("est`i'ALL") firstrow allstring clear

	// drop states
	drop if CountyFIPSCode == "000"

	// keep necessary variables
	keep StateFIPSCode CountyFIPSCode PostalCode Name PovertyPercentAllAges PovertyPercentAge017 PovertyPercentAge517inFam MedianHouseholdIncome

	// rename variables
	rename (PostalCode Name PovertyPercentAllAges PovertyPercentAge017 PovertyPercentAge517inFam MedianHouseholdIncome) ///
		(stateabbr countyname poverty_pct_all poverty_pct_017 poverty_pct_517 medhhincome)

	// generate county fips
	gen countyfips = StateFIPSCode + CountyFIPSCode

	// destring variables
	destring countyfips poverty_pct_all poverty_pct_017 poverty_pct_517 medhhincome, replace

	drop StateFIPSCode CountyFIPSCode
	
	// generate year
	gen year = 20`i'
	
	order countyfips year

	tempfile saipe`i'_county
	save `saipe`i'_county'
	
}

forvalues i = 22/23 {
	import excel "${datao}SAIPE/est`i'all.xls", sheet("est`i'ALL") firstrow allstring clear

	// drop states
	drop if CountyFIPSCode == "000"

	// keep necessary variables
	keep StateFIPSCode CountyFIPSCode PostalCode Name PovertyPercentAllAges PovertyPercentAge017 PovertyPercentAge517inFam MedianHouseholdIncome

	// rename variables
	rename (PostalCode Name PovertyPercentAllAges PovertyPercentAge017 PovertyPercentAge517inFam MedianHouseholdIncome) ///
		(stateabbr countyname poverty_pct_all poverty_pct_017 poverty_pct_517 medhhincome)

	// generate county fips
	gen countyfips = StateFIPSCode + CountyFIPSCode

	// destring variables
	destring countyfips poverty_pct_all poverty_pct_017 poverty_pct_517 medhhincome, replace

	drop StateFIPSCode CountyFIPSCode
	
	// generate year
	gen year = 20`i'
	
	order countyfips year
	
	// correct fipscode for Connecticut - drop and merge separated file
	drop if stateabbr=="CT"
	
	tempfile saipe`i'_county
	save `saipe`i'_county'
	
}

*--------------------------------*

* append

clear all
forvalues i = 10/23{
	append using "`saipe`i'_county'"
}

	append using "${datap}saipe_CT.dta"

// AK county fips recoded/changes
replace countyfips=2232 if countyfips==2105 | countyfips==2230
replace countyfips=2261 if countyfips==2063 | countyfips==2066
replace countyfips=2158 if countyfips==2270

tostring countyfips, replace format(%05.0f) 

collapse (mean) poverty_pct_all poverty_pct_017 poverty_pct_517 medhhincome, by(year stateabbr countyfips)

save "${datap}saipe2010_2023_county.dta", replace

// state (for state-level analysis)

collapse (mean) poverty* medhhincome, by (stateabbr year)

save "${datap}saipe2010_2023_state.dta", replace

* ************************************************************
* 0.2. Prep NVSS data
* ************************************************************

clear all

*--------------------------------*
*--------------------------------*

* load raw data (2016-2020)
forvalues i=2016/2020{
	
infix  ///
year 102-105 month 65-66 deathmanner 107 str stateabbr 29-30 str staterecode 33-34 str county 35-37 str sex 69 agetype 70 agetotal 71-73 race 445-446 racerecode 450 hispanic 484-486 hisprecode 487-488 str icd_10 146-149 a0 163-164 str a1 165-171 str a2 172-178 str a3 179-185 str a4 186-192 str a5 193-199 str a6 200-206 str a7 207-213 str a8 214-220 str a9 221-227 str a10 228-234 str a11 235-241 str a12 242-248 str a13 249-255 str a14 256-262 str a15 263-269 str a16 270-276 str a17 277-283 str a18 284-290 str a19 291-297 str a20 298-304 b0 341-342 str b1 344-348 str b2 349-353 str b3 354-358 str b4 359-363 str b5 364-368 str b6 369-373 str b7 374-378 str b8 379-383 str b9 384-388 str b10 389-393 str b11 394-398 str b12 399-403 str b13 404-408 str b14 409-413 str b15 414-418 str b16 419-423 str b17 424-428 str b18 429-433 str b19 434-438 str b20 439-443 ///
using "${datao}NVSS_4-15-2025/MULT`i'.USAllCnty.txt", clear

*--------------------------------*

merge m:1 stateabbr using "${datao}state crosswalk.dta"
keep if _merge==3
drop _merge

gen countyfips = statefips + county

// drop non-us residents
drop if stateabbr!=staterecode
drop staterecode

// recode age and only keep ages 0-17
gen age = 0 if agetype>1 & agetype!=9, before(agetype)
replace age = agetotal if missing(age)
keep if inrange(age, 0, 17)

// sex
gen female = sex == "F"
gen male = sex == "M"

// race + hisp
gen white = racerecode==1
gen black = racerecode==2
gen aian = racerecode==3
gen asian = racerecode==4 | racerecode==5

gen hisp = hispanic>199 if hispanic<996

/*
Race Recode 6 (2022 and after)
Beginning with the 2022 data file, new variable Race Recode 6 replaces Race
Recode 5 at this file location. Race Recode 6 is based on single race which is
consistent with 1997 Office of Management and Budget (OMB) race standards
whereas Race Recode 5 was based on bridged race consistent with 1977 OMB
standards. As of data year 2021, data by bridged race are no longer available, so
Race Recode 5 is not applicable after data year 2020. Single-race data are not
comparable with bridged-race data, so data at this location using Race Recode 6
in 2022 are not comparable with data using Race Recode 5 for earlier years. File
location 450 is reserved, i.e., not populated, in the 2021 data file.
1 ... White (only)
2 ... Black (only)
3 ... American Indian and Alaska Native (only)
4 ... Asian (only)
5 ... Native Hawaiian or Other
*/

*--------------------------------*

// icd-10 code
gen icda = substr(icd_10, 1, 3), before(a0)
gen icdb = substr(icd_10, 4, .), before(a0)

foreach var in a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a17 a18 a19 a20{
	gen `var'a = substr(`var', 3, 3), before(a0)
	gen `var'b = substr(`var', 6, .), before(a0)  

}

foreach var in b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15 b16 b17 b18 b19 b20{
	gen `var'a = substr(`var', 1, 3), before(a0)
	gen `var'b = substr(`var', 4, .), before(a0)  

}

// 1) accident & homicide
gen v1_all = (deathmanner==1 | deathmanner==3) & !missing(deathmanner)
gen v1_female = female == 1 & v1_all == 1
gen v1_male = male == 1 & v1_all == 1

gen v1_white = white == 1 & v1_all == 1
gen v1_black = black == 1 & v1_all == 1
gen v1_aian = aian == 1 & v1_all == 1
gen v1_asian = asian == 1 & v1_all == 1
gen v1_hisp = hisp == 1 & v1_all == 1


// 2) T74 + others
gen v2_all = 1 if icda == "X85" | icda == "X86" | icda == "X87" | icda == "X88" | icda == "X89" | ///
			icda == "X90" | icda == "X91" | icda == "X91" | icda == "X92" | icda == "X93" | icda == "X94" | ///
			icda == "X95" | icda == "X96" | icda == "X97" | icda == "X98" | icda == "X99" | ///
			icda == "Y00" | icda == "Y01" | icda == "Y02" | icda == "Y03" | icda == "Y04" | icda == "Y05" | ///
			icda == "Y06" | icda == "Y07" | icda == "Y08" | icda == "Y09" | icda == "T74"
gen v2_female = female == 1 & v2_all == 1
gen v2_male = male == 1 & v2_all == 1

gen v2_white = white == 1 & v2_all == 1
gen v2_black = black == 1 & v2_all == 1
gen v2_aian = aian == 1 & v2_all == 1
gen v2_asian = asian == 1 & v2_all == 1
gen v2_hisp = hisp == 1 & v2_all == 1

foreach var in a1a a2a a3a a4a a5a a6a a7a a8a a9a a10a a11a a12a a13a a14a a15a a16a a16a a17a a18a a19a a20a{
	replace v2_all = 1 if  `var' == "X85" |  `var' == "X86" |  `var' == "X87" |  `var' == "X88" |  `var' == "X89" | ///
			 `var' == "X90" |  `var' == "X91" |  `var' == "X91" |  `var' == "X92" |  `var' == "X93" |  `var' == "X94" | ///
			 `var' == "X95" |  `var' == "X96" |  `var' == "X97" |  `var' == "X98" |  `var' == "X99" | ///
			 `var' == "Y00" |  `var' == "Y01" |  `var' == "Y02" |  `var' == "Y03" |  `var' == "Y04" |  `var' == "Y05" | ///
			 `var' == "Y06" |  `var' == "Y07" |  `var' == "Y08" |  `var' == "Y09" |  `var' == "T74"

}

foreach var in b1a b2a b3a b4a b5a b6a b7a b8a b9a b10a b11a b12a b13a b14a b15a b16a b16a b17a b18a b19a b20a{
	replace v2_all = 1 if  `var' == "X85" |  `var' == "X86" |  `var' == "X87" |  `var' == "X88" |  `var' == "X89" | ///
			 `var' == "X90" |  `var' == "X91" |  `var' == "X91" |  `var' == "X92" |  `var' == "X93" |  `var' == "X94" | ///
			 `var' == "X95" |  `var' == "X96" |  `var' == "X97" |  `var' == "X98" |  `var' == "X99" | ///
			 `var' == "Y00" |  `var' == "Y01" |  `var' == "Y02" |  `var' == "Y03" |  `var' == "Y04" |  `var' == "Y05" | ///
			 `var' == "Y06" |  `var' == "Y07" |  `var' == "Y08" |  `var' == "Y09" |  `var' == "T74"

}

foreach x in v1 v2{
	gen `x'_03 = `x'_all==1 & inrange(age, 0, 3)
	gen `x'_417 = `x'_all==1 & inrange(age, 4, 17)
	gen `x'_04 = `x'_all==1 & inrange(age, 0, 4)
	gen `x'_517 = `x'_all==1 & inrange(age, 5, 17)
	gen `x'_05 = `x'_all==1 & inrange(age, 0, 5)
	gen `x'_617 = `x'_all==1 & inrange(age, 6, 17)

	foreach var in female male white black aian asian hisp{
		gen `x'_`var'_03 = `x'_03 ==1 & `var' == 1
		gen `x'_`var'_417 = `x'_417 ==1 & `var' == 1
		gen `x'_`var'_04 = `x'_04 ==1 & `var' == 1
		gen `x'_`var'_517 = `x'_517 ==1 & `var' == 1
		gen `x'_`var'_05 = `x'_05 ==1 & `var' == 1
		gen `x'_`var'_617 = `x'_617 ==1 & `var' == 1
	
	}

}

save "${datap}nvss`i'_lv1.dta", replace

collapse (sum) v1* v2*, by(countyfips year month)

save "${datap}nvss`i'_lv2.dta", replace

}

*--------------------------------*
*--------------------------------*

* load raw data (2021)

infix  ///
year 102-105 month 65-66 deathmanner 107 str stateabbr 29-30 str staterecode 33-34 str county 35-37 str sex 69 agetype 70 agetotal 71-73 hispanic 484-486 hisprecode 487-488 racerecode 489-490 str icd_10 146-149 a0 163-164 str a1 165-171 str a2 172-178 str a3 179-185 str a4 186-192 str a5 193-199 str a6 200-206 str a7 207-213 str a8 214-220 str a9 221-227 str a10 228-234 str a11 235-241 str a12 242-248 str a13 249-255 str a14 256-262 str a15 263-269 str a16 270-276 str a17 277-283 str a18 284-290 str a19 291-297 str a20 298-304 b0 341-342 str b1 344-348 str b2 349-353 str b3 354-358 str b4 359-363 str b5 364-368 str b6 369-373 str b7 374-378 str b8 379-383 str b9 384-388 str b10 389-393 str b11 394-398 str b12 399-403 str b13 404-408 str b14 409-413 str b15 414-418 str b16 419-423 str b17 424-428 str b18 429-433 str b19 434-438 str b20 439-443 ///
using "${datao}NVSS_4-15-2025/MULT2021.USAllCnty.txt", clear

*--------------------------------*

merge m:1 stateabbr using "${datao}state crosswalk.dta"
keep if _merge==3
drop _merge

gen countyfips = statefips + county

// drop non-us residents
drop if stateabbr!=staterecode
drop staterecode

// recode age and only keep those aged 0-17
gen age = 0 if agetype>1 & agetype!=9, before(agetype)
replace age = agetotal if missing(age)
keep if inrange(age, 0, 17)

// sex
gen female = sex == "F"
gen male = sex == "M"

// race + hisp
gen white = racerecode==1
gen black = racerecode==2
gen aian = racerecode==3
gen asian = inrange(racerecode, 4, 14)

gen hisp = hispanic>199 if hispanic<996

/*
01 … White
02 … Black
03 … American Indian or Alaskan Native (AIAN)
04 … Asian Indian
05 … Chinese
06 … Filipino
07 … Japanese
08 … Korean
09 … Vietnamese
10 … Other or Multiple Asian
11 … Hawaiian
12 … Guamanian
13 … Samoan
14 … Other or Multiple PI
*/

*--------------------------------*

// icd-10 code
gen icda = substr(icd_10, 1, 3), before(a0)
gen icdb = substr(icd_10, 4, .), before(a0)

foreach var in a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a17 a18 a19 a20{
	gen `var'a = substr(`var', 3, 3), before(a0)
	gen `var'b = substr(`var', 6, .), before(a0)  

}

foreach var in b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15 b16 b17 b18 b19 b20{
	gen `var'a = substr(`var', 1, 3), before(a0)
	gen `var'b = substr(`var', 4, .), before(a0)  

}

// 1) accident & homicide
gen v1_all = (deathmanner==1 | deathmanner==3) & !missing(deathmanner)
gen v1_female = female == 1 & v1_all == 1
gen v1_male = male == 1 & v1_all == 1

gen v1_white = white == 1 & v1_all == 1
gen v1_black = black == 1 & v1_all == 1
gen v1_aian = aian == 1 & v1_all == 1
gen v1_asian = asian == 1 & v1_all == 1
gen v1_hisp = hisp == 1 & v1_all == 1


// 2) T74 + others
gen v2_all = 1 if icda == "X85" | icda == "X86" | icda == "X87" | icda == "X88" | icda == "X89" | ///
			icda == "X90" | icda == "X91" | icda == "X91" | icda == "X92" | icda == "X93" | icda == "X94" | ///
			icda == "X95" | icda == "X96" | icda == "X97" | icda == "X98" | icda == "X99" | ///
			icda == "Y00" | icda == "Y01" | icda == "Y02" | icda == "Y03" | icda == "Y04" | icda == "Y05" | ///
			icda == "Y06" | icda == "Y07" | icda == "Y08" | icda == "Y09" | icda == "T74"
gen v2_female = female == 1 & v2_all == 1
gen v2_male = male == 1 & v2_all == 1

gen v2_white = white == 1 & v2_all == 1
gen v2_black = black == 1 & v2_all == 1
gen v2_aian = aian == 1 & v2_all == 1
gen v2_asian = asian == 1 & v2_all == 1
gen v2_hisp = hisp == 1 & v2_all == 1

foreach var in a1a a2a a3a a4a a5a a6a a7a a8a a9a a10a a11a a12a a13a a14a a15a a16a a16a a17a a18a a19a a20a{
	replace v2_all = 1 if  `var' == "X85" |  `var' == "X86" |  `var' == "X87" |  `var' == "X88" |  `var' == "X89" | ///
			 `var' == "X90" |  `var' == "X91" |  `var' == "X91" |  `var' == "X92" |  `var' == "X93" |  `var' == "X94" | ///
			 `var' == "X95" |  `var' == "X96" |  `var' == "X97" |  `var' == "X98" |  `var' == "X99" | ///
			 `var' == "Y00" |  `var' == "Y01" |  `var' == "Y02" |  `var' == "Y03" |  `var' == "Y04" |  `var' == "Y05" | ///
			 `var' == "Y06" |  `var' == "Y07" |  `var' == "Y08" |  `var' == "Y09" |  `var' == "T74"

}

foreach var in b1a b2a b3a b4a b5a b6a b7a b8a b9a b10a b11a b12a b13a b14a b15a b16a b16a b17a b18a b19a b20a{
	replace v2_all = 1 if  `var' == "X85" |  `var' == "X86" |  `var' == "X87" |  `var' == "X88" |  `var' == "X89" | ///
			 `var' == "X90" |  `var' == "X91" |  `var' == "X91" |  `var' == "X92" |  `var' == "X93" |  `var' == "X94" | ///
			 `var' == "X95" |  `var' == "X96" |  `var' == "X97" |  `var' == "X98" |  `var' == "X99" | ///
			 `var' == "Y00" |  `var' == "Y01" |  `var' == "Y02" |  `var' == "Y03" |  `var' == "Y04" |  `var' == "Y05" | ///
			 `var' == "Y06" |  `var' == "Y07" |  `var' == "Y08" |  `var' == "Y09" |  `var' == "T74"

}

foreach x in v1 v2{
	gen `x'_03 = `x'_all==1 & inrange(age, 0, 3)
	gen `x'_417 = `x'_all==1 & inrange(age, 4, 17)
	gen `x'_04 = `x'_all==1 & inrange(age, 0, 4)
	gen `x'_517 = `x'_all==1 & inrange(age, 5, 17)
	gen `x'_05 = `x'_all==1 & inrange(age, 0, 5)
	gen `x'_617 = `x'_all==1 & inrange(age, 6, 17)

	foreach var in female male white black aian asian hisp{
		gen `x'_`var'_03 = `x'_03 ==1 & `var' == 1
		gen `x'_`var'_417 = `x'_417 ==1 & `var' == 1
		gen `x'_`var'_04 = `x'_04 ==1 & `var' == 1
		gen `x'_`var'_517 = `x'_517 ==1 & `var' == 1
		gen `x'_`var'_05 = `x'_05 ==1 & `var' == 1
		gen `x'_`var'_617 = `x'_617 ==1 & `var' == 1
	
	}

}

save "${datap}nvss2021_lv1.dta", replace

collapse (sum) v1* v2*, by(countyfips year month)

save "${datap}nvss2021_lv2.dta", replace

*--------------------------------*
*--------------------------------*

* load raw data (2022-2023)

forvalues i=2022/2023{
	
infix  ///
year 102-105 month 65-66 deathmanner 107 str stateabbr 29-30 str staterecode 33-34 str county 35-37 str sex 69 agetype 70 agetotal 71-73 race 445-446 racerecode 450 hispanic 484-486 hisprecode 487-488 str icd_10 146-149 a0 163-164 str a1 165-171 str a2 172-178 str a3 179-185 str a4 186-192 str a5 193-199 str a6 200-206 str a7 207-213 str a8 214-220 str a9 221-227 str a10 228-234 str a11 235-241 str a12 242-248 str a13 249-255 str a14 256-262 str a15 263-269 str a16 270-276 str a17 277-283 str a18 284-290 str a19 291-297 str a20 298-304 b0 341-342 str b1 344-348 str b2 349-353 str b3 354-358 str b4 359-363 str b5 364-368 str b6 369-373 str b7 374-378 str b8 379-383 str b9 384-388 str b10 389-393 str b11 394-398 str b12 399-403 str b13 404-408 str b14 409-413 str b15 414-418 str b16 419-423 str b17 424-428 str b18 429-433 str b19 434-438 str b20 439-443 ///
using "${datao}NVSS_4-15-2025/MULT`i'.USAllCnty.txt", clear

*--------------------------------*

merge m:1 stateabbr using "${datao}state crosswalk.dta"
keep if _merge==3
drop _merge

gen countyfips = statefips + county

// drop non-us residents
drop if stateabbr!=staterecode
drop staterecode

// recode age and only keep those aged 0-17
gen age = 0 if agetype>1 & agetype!=9, before(agetype)
replace age = agetotal if missing(age)
keep if inrange(age, 0, 17)

// sex
gen female = sex == "F"
gen male = sex == "M"

// race + hisp
gen white = racerecode==1
gen black = racerecode==2
gen aian = racerecode==3
gen asian = racerecode==4 | racerecode==5

gen hisp = hispanic>199 if hispanic<996

/*
Race Recode 6 (2022 and after)
Beginning with the 2022 data file, new variable Race Recode 6 replaces Race
Recode 5 at this file location. Race Recode 6 is based on single race which is
consistent with 1997 Office of Management and Budget (OMB) race standards
whereas Race Recode 5 was based on bridged race consistent with 1977 OMB
standards. As of data year 2021, data by bridged race are no longer available, so
Race Recode 5 is not applicable after data year 2020. Single-race data are not
comparable with bridged-race data, so data at this location using Race Recode 6
in 2022 are not comparable with data using Race Recode 5 for earlier years. File
location 450 is reserved, i.e., not populated, in the 2021 data file.
1 ... White (only)
2 ... Black (only)
3 ... American Indian and Alaska Native (only)
4 ... Asian (only)
5 ... Native Hawaiian or Other
*/

*--------------------------------*

// icd-10 code
gen icda = substr(icd_10, 1, 3), before(a0)
gen icdb = substr(icd_10, 4, .), before(a0)

foreach var in a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a17 a18 a19 a20{
	gen `var'a = substr(`var', 3, 3), before(a0)
	gen `var'b = substr(`var', 6, .), before(a0)  

}

foreach var in b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15 b16 b17 b18 b19 b20{
	gen `var'a = substr(`var', 1, 3), before(a0)
	gen `var'b = substr(`var', 4, .), before(a0)  

}

// 1) accident & homicide
gen v1_all = (deathmanner==1 | deathmanner==3) & !missing(deathmanner)
gen v1_female = female == 1 & v1_all == 1
gen v1_male = male == 1 & v1_all == 1

gen v1_white = white == 1 & v1_all == 1
gen v1_black = black == 1 & v1_all == 1
gen v1_aian = aian == 1 & v1_all == 1
gen v1_asian = asian == 1 & v1_all == 1
gen v1_hisp = hisp == 1 & v1_all == 1


// 2) T74 + others
gen v2_all = 1 if icda == "X85" | icda == "X86" | icda == "X87" | icda == "X88" | icda == "X89" | ///
			icda == "X90" | icda == "X91" | icda == "X91" | icda == "X92" | icda == "X93" | icda == "X94" | ///
			icda == "X95" | icda == "X96" | icda == "X97" | icda == "X98" | icda == "X99" | ///
			icda == "Y00" | icda == "Y01" | icda == "Y02" | icda == "Y03" | icda == "Y04" | icda == "Y05" | ///
			icda == "Y06" | icda == "Y07" | icda == "Y08" | icda == "Y09" | icda == "T74"
gen v2_female = female == 1 & v2_all == 1
gen v2_male = male == 1 & v2_all == 1

gen v2_white = white == 1 & v2_all == 1
gen v2_black = black == 1 & v2_all == 1
gen v2_aian = aian == 1 & v2_all == 1
gen v2_asian = asian == 1 & v2_all == 1
gen v2_hisp = hisp == 1 & v2_all == 1

foreach var in a1a a2a a3a a4a a5a a6a a7a a8a a9a a10a a11a a12a a13a a14a a15a a16a a16a a17a a18a a19a a20a{
	replace v2_all = 1 if  `var' == "X85" |  `var' == "X86" |  `var' == "X87" |  `var' == "X88" |  `var' == "X89" | ///
			 `var' == "X90" |  `var' == "X91" |  `var' == "X91" |  `var' == "X92" |  `var' == "X93" |  `var' == "X94" | ///
			 `var' == "X95" |  `var' == "X96" |  `var' == "X97" |  `var' == "X98" |  `var' == "X99" | ///
			 `var' == "Y00" |  `var' == "Y01" |  `var' == "Y02" |  `var' == "Y03" |  `var' == "Y04" |  `var' == "Y05" | ///
			 `var' == "Y06" |  `var' == "Y07" |  `var' == "Y08" |  `var' == "Y09" |  `var' == "T74"

}

foreach var in b1a b2a b3a b4a b5a b6a b7a b8a b9a b10a b11a b12a b13a b14a b15a b16a b16a b17a b18a b19a b20a{
	replace v2_all = 1 if  `var' == "X85" |  `var' == "X86" |  `var' == "X87" |  `var' == "X88" |  `var' == "X89" | ///
			 `var' == "X90" |  `var' == "X91" |  `var' == "X91" |  `var' == "X92" |  `var' == "X93" |  `var' == "X94" | ///
			 `var' == "X95" |  `var' == "X96" |  `var' == "X97" |  `var' == "X98" |  `var' == "X99" | ///
			 `var' == "Y00" |  `var' == "Y01" |  `var' == "Y02" |  `var' == "Y03" |  `var' == "Y04" |  `var' == "Y05" | ///
			 `var' == "Y06" |  `var' == "Y07" |  `var' == "Y08" |  `var' == "Y09" |  `var' == "T74"

}

foreach x in v1 v2{
	gen `x'_03 = `x'_all==1 & inrange(age, 0, 3)
	gen `x'_417 = `x'_all==1 & inrange(age, 4, 17)
	gen `x'_04 = `x'_all==1 & inrange(age, 0, 4)
	gen `x'_517 = `x'_all==1 & inrange(age, 5, 17)
	gen `x'_05 = `x'_all==1 & inrange(age, 0, 5)
	gen `x'_617 = `x'_all==1 & inrange(age, 6, 17)

	foreach var in female male white black aian asian hisp{
		gen `x'_`var'_03 = `x'_03 ==1 & `var' == 1
		gen `x'_`var'_417 = `x'_417 ==1 & `var' == 1
		gen `x'_`var'_04 = `x'_04 ==1 & `var' == 1
		gen `x'_`var'_517 = `x'_517 ==1 & `var' == 1
		gen `x'_`var'_05 = `x'_05 ==1 & `var' == 1
		gen `x'_`var'_617 = `x'_617 ==1 & `var' == 1
	
	}

}

save "${datap}nvss`i'_lv1.dta", replace

collapse (sum) v1* v2*, by(countyfips year month)

save "${datap}nvss`i'_lv2.dta", replace

}

*--------------------------------*
*--------------------------------*

clear all

forvalues i=2016/2023{
	
	append using "${datap}nvss`i'_lv2.dta"

}

sort countyfips year month  
save "${datap}nvss2016_2023_county.dta", replace


* ************************************************************
* 0.3. Prep NCANDS Child data
* ************************************************************

clear all

*--------------------------------*
* import raw data & level-0 cleaning
*--------------------------------*

forvalues i=2016/2023{
	append using "${datao}NCANDS/CF`i'.dta", force
}

drop if staterr=="PR"	// drop; no modality data

// set date based on "report" date
rename subyr ffy
gen reportdate = date(rptdt, "YMD")
format %td reportdate

gen year = year(reportdate), before(ffy)
gen month = month(reportdate), after(year)

tostring rptfips, gen(rptfipsstr)

// flag masked counties
gen agg_county = 1 if strpos(rptfipsstr, "000")
replace agg_county = 1 if strpos(rptfipsstr, "999")
replace agg_county = . if strpos(rptfipsstr, "000") == 2 & strlen(rptfipsstr) == 5 & strpos(rptfipsstr, "0000") == 0

// replace "unknown county" to have state fips (~000)
replace rptfips=rptfips-999 if strpos(rptfipsstr, "999")

drop rptfipsstr
rename rptfips countyfips

drop if year<2016

save "${datap}ncands_child2016_2023_lv0.dta", replace 

*--------------------------------*
* count cases
*--------------------------------*

// reported child dummies
gen total_all = 1
gen total_all_sub = total_all==1 & (rptdisp==1 | rptdisp==2)

// report source (rptsrc)
gen total_edu = 1 if rptsrc==5
gen total_social = 1 if rptsrc==1
gen total_medical = 1 if rptsrc==2
gen total_legal = 1 if rptsrc==4
gen total_othpro = 1 if rptsrc==3 | inrange(rptsrc, 6, 7)
gen total_nonpro = 1 if inrange(rptsrc, 8, 12)
gen total_other = 1 if rptsrc==13 | rptsrc==88 | rptsrc==99

// maltreatment type (chmal1-4)
gen total_physical = 1 if chmal1==1 | chmal2==1 | chmal3==1 | chmal4==1
gen total_neglect = 1 if chmal1==2 | chmal2==2 | chmal3==2 | chmal4==2 | chmal1==3 | chmal2==3 | chmal3==3 | chmal4==3
gen total_sxabuse = 1 if chmal1==4 | chmal2==4 | chmal3==4 | chmal4==4
gen total_psyemo = 1 if chmal1==5 | chmal2==5 | chmal3==5 | chmal4==5

// child sex
gen total_male = chsex==1
gen total_female = chsex==2


// child race
gen total_asian = chracas==1
gen total_black = chracbl==1
gen total_white = chracwh==1
gen total_aian = chracai==1
gen total_otherr = total_asian!=1 & total_black!=1 & total_white!=1 & total_aian!=1
gen total_hisp = cethn==1

// child age (chage)

forvalues i=0/17{

	gen total_`i' = chage==`i'

}

keep year month ffy staterr countyfips chage rptdisp agg_county total*

// child age (by age group)

forvalues i=4/6{
	
	// reported children
	gen total`i'17 = 1 if inrange(chage, `i', 17)	// PreK-12

	gen edu_`i'17 = total_edu==1 & inrange(chage, `i', 17)
	gen legal_`i'17 = total_legal==1 & inrange(chage, `i', 17)
	gen social_`i'17 = total_social==1 & inrange(chage, `i', 17)
	gen medical_`i'17 = total_medical==1 & inrange(chage, `i', 17)
	gen othpro_`i'17 = total_othpro==1 & inrange(chage, `i', 17)
	gen nonpro_`i'17 = total_nonpro==1 & inrange(chage, `i', 17)
	gen other_`i'17 = total_other==1 & inrange(chage, `i', 17)
	
	gen black_`i'17 = total_black==1 & inrange(chage, `i', 17)
	gen white_`i'17 = total_white==1 & inrange(chage, `i', 17)
	gen asian_`i'17 = total_asian==1 & inrange(chage, `i', 17)
	gen aian_`i'17 = total_aian==1 & inrange(chage, `i', 17)
	gen hisp_`i'17 = total_hisp==1 & inrange(chage, `i', 17)
	gen otherr_`i'17 = total_otherr==1 & inrange(chage, `i', 17)
	gen physical_`i'17 = total_physical==1 & inrange(chage, `i', 17)
	gen neglect_`i'17 = total_neglect==1 & inrange(chage, `i', 17)
	gen sxabuse_`i'17 = total_sxabuse==1 & inrange(chage, `i', 17)
	gen psyemo_`i'17 = total_psyemo==1 & inrange(chage, `i', 17)
	
	gen male_`i'17 = total_male==1 & inrange(chage, `i', 17)
	gen female_`i'17 = total_female==1 & inrange(chage, `i', 17)

	// substantiated children
	gen total`i'17_sub = total_all==1 & (rptdisp==1 | rptdisp==2) & inrange(chage, `i', 17)
	
	gen edu_`i'17_sub = total`i'17_sub == 1 & edu_`i'17 == 1
	gen legal_`i'17_sub = total`i'17_sub == 1 & legal_`i'17 == 1
	gen social_`i'17_sub = total`i'17_sub == 1 & social_`i'17 == 1
	gen medical_`i'17_sub = total`i'17_sub == 1 & medical_`i'17 == 1
	gen othpro_`i'17_sub = total`i'17_sub == 1 & othpro_`i'17 == 1
	gen nonpro_`i'17_sub = total`i'17_sub == 1 & nonpro_`i'17 == 1
	gen other_`i'17_sub = total`i'17_sub == 1 & other_`i'17 == 1
	
	gen black_`i'17_sub = total`i'17_sub == 1 & black_`i'17 == 1
	gen white_`i'17_sub = total`i'17_sub == 1 & white_`i'17 == 1
	gen asian_`i'17_sub = total`i'17_sub == 1 & asian_`i'17 == 1
	gen aian_`i'17_sub = total`i'17_sub == 1 & aian_`i'17 == 1
	gen hisp_`i'17_sub = total`i'17_sub == 1 & hisp_`i'17 == 1
	gen otherr_`i'17_sub = total`i'17_sub == 1 & otherr_`i'17 == 1
	gen physical_`i'17_sub = total`i'17_sub == 1 & physical_`i'17 == 1
	gen neglect_`i'17_sub = total`i'17_sub == 1 & neglect_`i'17 == 1
	gen sxabuse_`i'17_sub = total`i'17_sub == 1 & sxabuse_`i'17 == 1
	gen psyemo_`i'17_sub = total`i'17_sub == 1 & psyemo_`i'17 == 1
	
	gen male_`i'17_sub = total`i'17_sub == 1 & male_`i'17 == 1
	gen female_`i'17_sub = total`i'17_sub == 1 & female_`i'17 == 1
	//gen metro_`i'17_sub = total`i'17_sub == 1 & metro_`i'17 == 1
	//gen nonmetro_`i'17_sub = total`i'17_sub == 1 & nonmetro_`i'17 == 1
	//gen rural_`i'17_sub = total`i'17_sub == 1 & rural_`i'17 == 1

}

*--------------------------------*

forvalues i=3/5{

	// reported children
	gen total0`i' = inrange(chage, 0, `i')	// PreK-12

	gen edu_0`i' = total_edu==1 & inrange(chage, 0, `i')
	gen legal_0`i' = total_legal==1 & inrange(chage, 0, `i')
	gen social_0`i' = total_social==1 & inrange(chage, 0, `i')
	gen medical_0`i' = total_medical==1 & inrange(chage, 0, `i')
	gen othpro_0`i' = total_othpro==1 & inrange(chage, 0, `i')
	gen nonpro_0`i' = total_nonpro==1 & inrange(chage, 0, `i')
	gen other_0`i' = total_other==1 & inrange(chage, 0, `i')
	
	gen black_0`i' = total_black==1 & inrange(chage, 0, `i')
	gen white_0`i' = total_white==1 & inrange(chage, 0, `i')
	gen asian_0`i' = total_asian==1 & inrange(chage, 0, `i')
	gen aian_0`i' = total_aian==1 & inrange(chage, 0, `i')
	gen hisp_0`i' = total_hisp==1 & inrange(chage, 0, `i')
	gen otherr_0`i' = total_otherr==1 & inrange(chage, 0, `i')
	gen physical_0`i' = total_physical==1 & inrange(chage, 0, `i')
	gen neglect_0`i' = total_neglect==1 & inrange(chage, 0, `i')
	gen sxabuse_0`i' = total_sxabuse==1 & inrange(chage, 0, `i')
	gen psyemo_0`i' = total_psyemo==1 & inrange(chage, 0, `i')
	
	gen male_0`i' = total_male==1 & inrange(chage, 0, `i')	// PreK-12
	gen female_0`i' = total_female==1 & inrange(chage, 0, `i')	// PreK-12

	// substantiated children
	gen total0`i'_sub = total_all==1 & (rptdisp==1 | rptdisp==2) & inrange(chage, 0, `i')
	
	gen edu_0`i'_sub = total0`i'_sub == 1 & edu_0`i' == 1
	gen legal_0`i'_sub = total0`i'_sub == 1 & legal_0`i' == 1
	gen social_0`i'_sub = total0`i'_sub == 1 & social_0`i' == 1
	gen medical_0`i'_sub = total0`i'_sub == 1 & medical_0`i' == 1
	gen othpro_0`i'_sub = total0`i'_sub == 1 & othpro_0`i' == 1
	gen nonpro_0`i'_sub = total0`i'_sub == 1 & nonpro_0`i' == 1
	gen other_0`i'_sub = total0`i'_sub == 1 & other_0`i' == 1
	
	gen black_0`i'_sub = total0`i'_sub == 1 & black_0`i' == 1
	gen white_0`i'_sub = total0`i'_sub == 1 & white_0`i' == 1
	gen asian_0`i'_sub = total0`i'_sub == 1 & asian_0`i' == 1
	gen aian_0`i'_sub = total0`i'_sub == 1 & aian_0`i' == 1
	gen hisp_0`i'_sub = total0`i'_sub == 1 & hisp_0`i' == 1
	gen otherr_0`i'_sub = total0`i'_sub == 1 & otherr_0`i' == 1
	gen physical_0`i'_sub = total0`i'_sub == 1 & physical_0`i' == 1
	gen neglect_0`i'_sub = total0`i'_sub == 1 & neglect_0`i' == 1
	gen sxabuse_0`i'_sub = total0`i'_sub == 1 & sxabuse_0`i' == 1
	gen psyemo_0`i'_sub = total0`i'_sub == 1 & psyemo_0`i' == 1

	gen male_0`i'_sub = total0`i'_sub == 1 & male_0`i' == 1
	gen female_0`i'_sub = total0`i'_sub == 1 & female_0`i' == 1

	}

*--------------------------------*
* level-1 cleaning & county-level ncands
*--------------------------------*

rename staterr stateabbr
drop if stateabbr=="XX"

replace countyfips=. if agg_county==1	// replace countyfips to mising (to construct hypothetical county later)

save "${datap}ncands_child2016_2023_lv1.dta", replace 

collapse (sum) total_* *417 *03 *617 *05 *517 *04 *417_sub *03_sub *617_sub *05_sub *517_sub *04_sub, ///
	by(stateabbr countyfips agg_county year month)

rename (total417* total03* total517* total04* total617* total05*)	///
		(total_417* total_03* total_517* total_04* total_617* total_05*)

save "${datap}ncands_child2016_2023_county.dta", replace 

* ************************************************************
* 0.4. Prep hypothetical county data
* ************************************************************

*--------------------------------*
* 1) Merge unemp + SAIPE + census + modality +
*     covid + nvss (maltreatment-related fatalities)
	// yearly (county + state) and monthly (county)
*--------------------------------*

* unemp + saipe
use "${datap}unemp2010_2023_county.dta", clear	// county-year
merge 1:1 year countyfips using "${datap}saipe2010_2023_county.dta"	// county-year
keep if _merge==3
drop _merge

* +census
merge 1:1 year countyfips using  "${datap}SEER population_county.dta"	// county-year
keep if _merge==3
drop _merge

drop if year<2016

// county-year to county-month (to merge monthly modality data)
bys countyfips (year): egen seq=seq()
bys countyfips (year): egen max=max(seq)

expand 12
bys countyfips year: egen month = seq()
order year month
drop seq max

tostring countyfips, replace format(%05.0f)

* +modality
merge 1:1 year month countyfips using "${datap}remote SY21 county.dta"
drop _merge

destring statefips, replace

* +covid
merge 1:1 year month countyfips using "${datap}covid2020_2023_county.dta"
drop if _merge==2	// drop covid observations that weren't linked to the main dataset
drop _merge

* +nvss (maltreatment-related fatalities)
merge 1:1 countyfips year month using "${datap}nvss2016_2023_county.dta"
drop if _merge==2 // drop nvss observations that weren't linked to the main dataset
drop _merge

order pop*, after(newdeaths)

* impute 0 to pre- & post-covid datapoints
replace newcases = 0 if (year<2020 & missing(newcases)) | (year==2023 & inrange(month, 6, 12) & missing(newcases))
replace newdeaths = 0 if (year<2020 & missing(newdeaths)) | (year==2023 & inrange(month, 6, 12) & missing(newdeaths))

* impute 0 to pre-variation-in-remote (periods before & after SY 2020-21) period
replace prop_remote = 0 if (year<2020 & missing(prop_remote)) | (year==2020 & inrange(month, 1, 5) & missing(prop_remote))
replace prop_remote = 0 if (year>2021 & missing(prop_remote)) | (year==2021 & inrange(month, 9, 12) & missing(prop_remote))

destring countyfips, replace	

save "${datap}!ncands2016_2023_county.dta", replace

*--------------------------------*
* 2) merge it into NCANDS & keep if _merge==2
	// these counties are the counties with <700 reported CM cases (so their countyfips are masked)
*--------------------------------*

merge m:1 stateabbr countyfips year month using "${datap}ncands_child2016_2023_county.dta"

/*
    Result                      Number of obs
    -----------------------------------------
    Not matched                       207,454
        from master                   203,008  (_merge==1)	// stats for aggregated counties (either MASKED or ZERO REPORTS)
        from using                      4,446  (_merge==2)	// aggregated counties

    Matched                            98,432  (_merge==3)	// identified counties
    -----------------------------------------

*/
// _merge==1 : have !ncands data but no reports --> these are probably the "masked" counties (OR THOSE WITH NO MALTREATMENT REPORTS)

save "${datap}!ncands2016_2023_county_flag.dta", replace

*-----------------------------------*

// masked counties
preserve

keep if _merge==1
drop _merge

collapse (sum) laborforce pop* new* v1*	v2* /// collapse them to have one aggregated county per state
		(mean) unemp poverty* medhhincome prop_remote  	///
		, by(year month stateabbr statefips agg_county)

gen countyfips=.
replace agg_county = 1

save "${datap}!ncands2016_2023_county_masked.dta", replace

restore

// non-masked counties
preserve

keep if _merge==3
drop _merge

drop total* ///
*_sub edu_* legal_* social_* medical_* othpro_* nonpro_* other_* black_* white_* asian_* ameind_* hisp_* ///
otherr_* physical_* neglect_* sxabuse_* psyemo_* male_* female_* statename

save "${datap}!ncands2016_2023_county_nonmasked.dta", replace

restore

* 3. append masked + non-masked counties

clear all
append using "${datap}!ncands2016_2023_county_nonmasked.dta"
append using "${datap}!ncands2016_2023_county_masked.dta"

save "${datap}!ncands2016_2023_county_master", replace


* ************************************************************
* 1.1. Construct master county dataset
* ************************************************************

* ************************************************************
* 1.2. Construct master county_agg
* ************************************************************

* ************************************************************
* 1.3. Construct master state (for state-year level analysis)
* ************************************************************

* ************************************************************
* 2.1. graphs
* ************************************************************

* Figure 1: Trends in Child Maltreatment Outcomes, by Remote Learning Exposure

* ************************************************************
* 2.2. tables
* ************************************************************

* Table 1: Pre-School-Closure Summary Statistics

* ************************************************************
* 3.1. regressions (county-level)
* ************************************************************

* ************************************************************
* 3.2. regressions (state-level)
* ************************************************************


