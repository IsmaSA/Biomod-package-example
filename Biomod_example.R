################################################################################
#######################            BIOMOD 2        #############################
################################################################################


suppressMessages({
  library(dplyr, quiet = TRUE, warn.conflicts = FALSE)
  library(reshape, quiet = TRUE, warn.conflicts = FALSE)
  library(metafor, quiet = TRUE, warn.conflicts = FALSE)
  library(ggplot2)
  library(tidyr)  
  library(biomod2)
  library(ggplot2)
  library(rgbif)
  library(gridExtra)
  library(raster)
  library(rasterVis)
  library(devtools)
  Sys.setenv(LANGUAGE = "en")
  
})

install.packages("biomod2", dependencies = TRUE)

devtools::install_github("biomodhub/biomod2", dependencies = TRUE)


#### Species Data ####

sp <- occ_data(scientificName ="Tetrax tetrax", hasCoordinate = TRUE,
               occurrenceStatus = "PRESENT", continent="europe",
               limit = 300)
sp <- sp[["data"]]

head(sp)

sp <- sp[,c(3,4)]
sp$Presence <- 1
sp <- sp[!duplicated(sp[c("decimalLatitude", "decimalLongitude")]), ]



###### Predictors ######
bio <- raster::getData('worldclim', var='bio', res=10)

remove <- c("bio1","bio2","bio3","bio10")
bio <- raster::dropLayer(bio, remove)
bio

#bio <- 
#  raster::stack(
#    c(
#      bio_5  = '../data/worldclim_ZA/worldclim_ZA_bio_5.asc',
#      bio_7  = '../data/worldclim_ZA/worldclim_ZA_bio_7.asc',
#      bio_11 = '../data/worldclim_ZA/worldclim_ZA_bio_11.asc',
#      bio_19 = '../data/worldclim_ZA/worldclim_ZA_bio_19.asc'
#    )
#  )

#bio



#### Formating the data #####
install.packages('xfun', repos = 'https://yihui.r-universe.dev')

data <- 
  biomod2::BIOMOD_FormatingData(
    resp.var = sp['Presence'],
    resp.xy = sp[, c('decimalLongitude', 'decimalLatitude')],
    expl.var = bio,
    resp.name = "Presence",
    filter.raster = TRUE,
    PA.nb.rep = 2,
    PA.nb.absences = 100,
    PA.strategy = 'random'
  )

data
plot(data)


#### Model  #####
data_opt <- 
  BIOMOD_ModelingOptions(
    GLM = list(type = 'quadratic', interaction.level = 1),
    GBM = list(n.trees = 1000),
    GAM = list(algo = 'GAM_mgcv')
  )

myBiomodOptions <- BIOMOD_ModelingOptions()


#### run the individual models #####

?BIOMOD_Modeling

myBiomodModelOut <- BIOMOD_Modeling(bm.format = data,
                                    bm.options = myBiomodOptions,
                                    modeling.id = 'AllModels',
                                    CV.strategy = 'random',
                                    CV.nb.rep = 2,
                                    CV.perc = 0.8,
                                    var.import = 3,
                                    metric.eval = c('TSS','ROC'))

myBiomodModelOut
#### asses individual models quality ####

## get models evaluation scores
ProLau_models_scores <- get_evaluations(myBiomodModelOut)

## ProLau_models_scores is a 5 dimension array containing the scores of the models
dim(ProLau_models_scores)
dimnames(ProLau_models_scores)

## plot models evaluation scores
bm_PlotEvalMean(bm.out = myBiomodModelOut)

bm_PlotEvalMean(
  myBiomodModelOut,
  metric.eval = NULL,      #ROC,  TSS, KAPPA, ACCURACY
  dataset = "calibration" # validation or evaluation
) 



## check variable importance
ProLau_models_var_import <- get_variables_importance(myBiomodModelOut)


## make the mean of variable importance by algorithm
apply(ProLau_models_var_import, c(1,2), mean)

## individual models response plots
ProLau_glm <- BIOMOD_LoadModels(ProLau_models, models='GLM')
ProLau_gbm <- BIOMOD_LoadModels(ProLau_models, models='GBM')
ProLau_rf <- BIOMOD_LoadModels(ProLau_models, models='RF')
ProLau_gam <- BIOMOD_LoadModels(ProLau_models, models='GAM')

glm_eval_strip <- 
  biomod2::response.plot2(
    models  = ProLau_glm,
    Data = get_formal_data(ProLau_models,'expl.var'), 
    show.variables= get_formal_data(ProLau_models,'expl.var.names'),
    do.bivariate = FALSE,
    fixed.var.metric = 'median',
    legend = FALSE,
    display_title = FALSE,
    data_species = get_formal_data(ProLau_models,'resp.var')
  )

gbm_eval_strip <- 
  biomod2::response.plot2(
    models  = ProLau_gbm,
    Data = get_formal_data(ProLau_models,'expl.var'), 
    show.variables= get_formal_data(ProLau_models,'expl.var.names'),
    do.bivariate = FALSE,
    fixed.var.metric = 'median',
    legend = FALSE,
    display_title = FALSE,
    data_species = get_formal_data(ProLau_models,'resp.var')
  )

rf_eval_strip <- 
  biomod2::response.plot2(
    models  = ProLau_rf,
    Data = get_formal_data(ProLau_models,'expl.var'), 
    show.variables= get_formal_data(ProLau_models,'expl.var.names'),
    do.bivariate = FALSE,
    fixed.var.metric = 'median',
    legend = FALSE,
    display_title = FALSE,
    data_species = get_formal_data(ProLau_models,'resp.var')
  )

gam_eval_strip <- 
  biomod2::response.plot2(
    models  = ProLau_gam,
    Data = get_formal_data(ProLau_models,'expl.var'), 
    show.variables= get_formal_data(ProLau_models,'expl.var.names'),
    do.bivariate = FALSE,
    fixed.var.metric = 'median',
    legend = FALSE,
    display_title = FALSE,
    data_species = get_formal_data(ProLau_models,'resp.var')
  )

## run the ensemble models ----

?BIOMOD_EnsembleModeling
myBiomodEM <- BIOMOD_EnsembleModeling(bm.mod = myBiomodModelOut,
                                      models.chosen = 'all',
                                      em.by = 'all', # all,algo,PA, PA+algo, PA+run
                                      em.algo = c('EMmean', 'EMca'), #Median, mean...
                                      metric.select = c('TSS'),
                                      metric.select.thresh = c(0.7), #minimu, threshold
                                      metric.eval = c('TSS', 'ROC'),
                                      var.import = 3 #permutations
                                      )




## asses ensemble models quality ----
ProLau_ensemble_models_scores <- get_evaluations(myBiomodEM)

## do models projections ----

## current projections
myBiomodProj  <- 
  BIOMOD_Projection(
    bm.mod = myBiomodModelOut,
    new.env = bio,
    proj.name = "current",
    binary.meth = "TSS",
    output.format = ".img",
    do.stack = FALSE
  )

# project ensemble of all models
myBiomodEnProj <- BIOMOD_EnsembleForecasting(bm.em = myBiomodEM,
                                             bm.proj = myBiomodProj,
                                             selected.models = "all")


plot(myBiomodEnProj)


utils::remove.packages("biomod2")
devtools::install_gitlab("IanOndo/ShinyBIOMOD")
library(ShinyBIOMOD)
run_shinyBIOMOD()













## future projections

## load 2050 bioclim variables
bioclim_ZA_2050_BC45 <-
  stack(
    c(
      bio_5  = '../data/worldclim_ZA/worldclim_ZA_2050_BC45_bio_5.asc',
      bio_7  = '../data/worldclim_ZA/worldclim_ZA_2050_BC45_bio_7.asc',
      bio_11 = '../data/worldclim_ZA/worldclim_ZA_2050_BC45_bio_11.asc',
      bio_19 = '../data/worldclim_ZA/worldclim_ZA_2050_BC45_bio_19.asc'
    )
  )

ProLau_models_proj_2050_BC45 <- 
  BIOMOD_Projection(
    modeling.output = ProLau_models,
    new.env = bioclim_ZA_2050_BC45,
    proj.name = "2050_BC45",
    binary.meth = "TSS",
    output.format = ".img",
    do.stack = FALSE
  )

ProLau_ensemble_models_proj_2050_BC45 <- 
  BIOMOD_EnsembleForecasting(
    EM.output = ProLau_ensemble_models,
    projection.output = ProLau_models_proj_2050_BC45,
    binary.meth = "TSS",
    output.format = ".img",
    do.stack = FALSE
  )

## load 2070 bioclim variables
bioclim_ZA_2070_BC45 <-
  stack(
    c(
      bio_5  = '../data/worldclim_ZA/worldclim_ZA_2070_BC45_bio_5.asc',
      bio_7  = '../data/worldclim_ZA/worldclim_ZA_2070_BC45_bio_7.asc',
      bio_11 = '../data/worldclim_ZA/worldclim_ZA_2070_BC45_bio_11.asc',
      bio_19 = '../data/worldclim_ZA/worldclim_ZA_2070_BC45_bio_19.asc'
    )
  )

ProLau_models_proj_2070_BC45 <- 
  BIOMOD_Projection(
    modeling.output = ProLau_models,
    new.env = bioclim_ZA_2070_BC45,
    proj.name = "2070_BC45",
    binary.meth = "TSS",
    output.format = ".img",
    do.stack = FALSE
  )

ProLau_ensemble_models_proj_2070_BC45 <- 
  BIOMOD_EnsembleForecasting(
    EM.output = ProLau_ensemble_models,
    projection.output = ProLau_models_proj_2070_BC45,
    binary.meth = "TSS",
    output.format = ".img",
    do.stack = FALSE
  )

## check how projections looks like
plot(ProLau_ensemble_models_proj_2070_BC45, str.grep = "EMca|EMwmean")

## compute Species Range Change (SRC) ----
## load binary projections
ProLau_bin_proj_current <- 
  stack( 
    c(
      ca = "Protea.laurifolia/proj_current/individual_projections/Protea.laurifolia_EMcaByTSS_mergedAlgo_mergedRun_mergedData_TSSbin.img",
      wm = "Protea.laurifolia/proj_current/individual_projections/Protea.laurifolia_EMwmeanByTSS_mergedAlgo_mergedRun_mergedData_TSSbin.img"
    )
  )

ProLau_bin_proj_2050_BC45 <- 
  stack( 
    c(
      ca = "Protea.laurifolia/proj_2050_BC45/individual_projections/Protea.laurifolia_EMcaByTSS_mergedAlgo_mergedRun_mergedData_TSSbin.img",
      wm = "Protea.laurifolia/proj_2050_BC45/individual_projections/Protea.laurifolia_EMwmeanByTSS_mergedAlgo_mergedRun_mergedData_TSSbin.img"
    )
  )

ProLau_bin_proj_2070_BC45 <- 
  stack( 
    c(
      ca = "Protea.laurifolia/proj_2070_BC45/individual_projections/Protea.laurifolia_EMcaByTSS_mergedAlgo_mergedRun_mergedData_TSSbin.img",
      wm = "Protea.laurifolia/proj_2070_BC45/individual_projections/Protea.laurifolia_EMwmeanByTSS_mergedAlgo_mergedRun_mergedData_TSSbin.img"
    )
  )

## SRC current -> 2050
SRC_current_2050_BC45 <- 
  BIOMOD_RangeSize(
    ProLau_bin_proj_current,
    ProLau_bin_proj_2050_BC45
  )

SRC_current_2050_BC45$Compt.By.Models

## SRC current -> 2070
SRC_current_2070_BC45 <- 
  BIOMOD_RangeSize(
    ProLau_bin_proj_current,
    ProLau_bin_proj_2070_BC45
  )

SRC_current_2070_BC45$Compt.By.Models

ProLau_src_map <- 
  stack(
    SRC_current_2050_BC45$Diff.By.Pixel, 
    SRC_current_2070_BC45$Diff.By.Pixel
  )
names(ProLau_src_map) <- c("ca cur-2050", "wm cur-2050", "ca cur-2070", "wm cur-2070")

my.at <- seq(-2.5, 1.5, 1)
myColorkey <- 
  list(
    at = my.at, ## where the colors change
    labels = 
      list(
        labels = c("lost", "pres", "abs","gain"), ## labels
        at = my.at[-1] - 0.5 ## where to print labels
      )
  )

rasterVis::levelplot( 
  ProLau_src_map, 
  main = "Protea laurifolia range change",
  colorkey = myColorkey,
  col.regions=c('#f03b20', '#99d8c9', '#f0f0f0', '#2ca25f'),
  layout = c(2,2)
)

## compute the stratified density of probabilities on SRC ----
## the reference projetion
ref <- subset(ProLau_bin_proj_current, "ca")

## define the facets we want to study
mods <- c("GLM", "GBM", "RF", "GAM")
data_set <- c("PA1", "PA2")
cv_run <- c("RUN1", "RUN2", "Full")

## construct combination of all facets
groups <- 
  as.matrix(
    expand.grid(
      models = mods, 
      data_set = data_set, 
      cv_run = cv_run,
      stringsAsFactors = FALSE)
  )

## load all projections we have produced
all_bin_proj_files <- 
  list.files( 
    path = "Protea.laurifolia",  
    pattern = "_TSSbin.img$",
    full.names = TRUE, 
    recursive = TRUE
  )

## current versus 2070 (removed the projections for current and 2050)
current_and_2070_proj_files <- grep(all_bin_proj_files, pattern="2070", value=T)

## keep only projections that match with our selected facets groups
selected_bin_proj_files <- 
  apply(
    groups, 1, 
    function(x){
      proj_file <- NA
      match_tab <- sapply(x, grepl, current_and_2070_proj_files)
      match_id <- which(apply(match_tab, 1, all))
      if(length(match_id)) proj_file <- current_and_2070_proj_files[match_id]
      proj_file
    }
  )

## remove no-matching groups
to_remove <- which(is.na(selected_bin_proj_files))
if(length(to_remove)){
  groups <- groups[-to_remove,]
  selected_bin_proj_files <- selected_bin_proj_files[-to_remove]
}

## build stack of selected projections
proj_groups <- stack(selected_bin_proj_files)

ProbDensFunc(
  initial = as.vector(ref),
  projections = raster::as.matrix(proj_groups),
  groups = t(groups),
  plothist = TRUE,
  resolution = 10,
  cvsn = FALSE
)



