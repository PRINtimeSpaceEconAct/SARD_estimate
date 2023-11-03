require(spdep)
require(Matrix)
require(snow)

compute_D <- function(df,dMax=100){
    # dMax = 100Km by deafault. Assumes that we will never consider interaction
    # at distance higher than 100Km.
    # In DataFrame data we assume that Latitude Longitude are in degrees with
    # projection "+proj=longlat  +datum=WGS84  +no_defs"
    
    if (DEBUG == TRUE){ print("computing all distances") }
    
    coord = cbind(df$Longitude,df$Latitude)
    spatialNeighbors <- dnearneigh(coord, 0,dMax, row.names=NULL, longlat=TRUE)
    dlist <- nbdists(spatialNeighbors, coord, longlat=TRUE)
    dlist1 <- lapply(dlist, function(x) x)          
    spatialNeighbors <- suppressWarnings(nb2listw(spatialNeighbors,
                                  glist=dlist1, style="B", zero.policy=TRUE))
    D <- listw2mat(spatialNeighbors)
    D <- as(D, "sparseMatrix")
    
    return(D)
}

GFDM <- function(df){
    # starting from coordinates returns a list with all sparse matrices
    # Mx,My,Mxx,Myy,Mxy
    
    if (DEBUG == TRUE){ print("computing derivative matrices") }
    
    source("lib/L_GFDM.R")
    coord = cbind(df$Longitude,df$Latitude)
    MsDeriv = compute_MDiff(coord)
    return(MsDeriv)
}

compute_WhAR <- function(D,df,h){
    # weight matrices WhA or WhR
    
    if (DEBUG == TRUE){ print("computing WhAR") }
    
    dInvSq <- function(d,h) 1/(d+1)^2*((d <= h) & (d > 0))
    
    Wh = dInvSq(D,h)
    Wh[is.na(Wh)] = 0
    diag(Wh) = 1
    Wh = t(apply(Wh, 1, function(x) x * as.numeric(df$km2)))
    
    return(Wh)
}

LogLikAICcR2 <- function(df, coef, k, xS, xA, xR, xD, MS, MA, MR, MD, W_eps){
    # compute LogLik and AICc of the SARD Model, with dof degree of freedom
    # coefs is of length 11, in order
    # a, phi, gammaS, gammA, gammaR, gammaD, rhoS, rhoA, rhoR, rhoD, lambda.
    # used also for NAIVE, IV WN, SARD WN. 
    
    if (DEBUG == TRUE){ print("computing LogLik") }
    
    # thankyou R for being so modern    
    a=coef[1]; phi=coef[2]; gammaS=coef[3]; gammA=coef[4]; gammaR = coef[5];
    gammaD=coef[6]; rhoS=coef[7]; rhoA=coef[8]; rhoR=coef[9]; rhoD=coef[10]; 
    lambda=coef[11]

    N = nrow(MS)
    Y = df$delta
    X = cbind(df$ones,df$y0,xS,xA,xR,xD)
    colnames(X) <- c("ones","y0","xS","xA","xR","xD")
    
    A = diag(N) - rhoS*MS - rhoA*MA - rhoR*MR - rhoD*MD
    B = diag(N) - lambda*W_eps
    spatY = A %*% as.numeric(Y)
    # beta = coef(lm(spatY ~ X - 1))
    beta = solve( t(X) %*% X, t(X) %*% spatY)
    epsilon = spatY - X %*% beta
    
    mu = B %*% epsilon
    sigma2 = as.numeric(t(mu) %*% mu) / N
    Omega = sigma2 * diag(N)
    nu = mu / sqrt(sigma2)
    
    logAbsDetA = Matrix::det(A, modulus=TRUE)   # log(|det(A)|)
    logAbsDetB = det(B,modulus = TRUE)
    
    LogLiKelyhood = -(N/2)*(log(2*pi)) - (N/2)*log(sigma2) + 
        + logAbsDetB + logAbsDetA - 1/2 * as.numeric(t(nu) %*% nu)
    AIC = 2*k - 2*LogLiKelyhood
    AICc = AIC + (2*k^2+2*k)/(N-k-1)
    
    LL0 = logLik(lm(Y ~ 1))
    R2Nagelkerke =  c(1 - exp(-(2/N)*(LogLiKelyhood - LL0)))
    
    return(listN(LogLiKelyhood,AICc,R2Nagelkerke))
}

listN <- function(...){
    # automatically give names to list elements = var name
    anonList <- list(...)
    names(anonList) <- as.character(substitute(list(...)))[-1]
    anonList
}

