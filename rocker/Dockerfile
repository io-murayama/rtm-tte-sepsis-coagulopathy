FROM rocker/tidyverse:4.5.1

# System libs needed when CRAN binaries fall back to source builds
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    cmake \
    libcurl4-openssl-dev \
    libssl-dev \
    libgit2-dev \
    libuv1-dev \
  && rm -rf /var/lib/apt/lists/*

RUN R -q -e "utils::install.packages('renv', repos='https://cloud.r-project.org')"

WORKDIR /home/rstudio/repository
COPY . /home/rstudio/repository

RUN R -q -e " \
if (file.exists('renv.lock')) { \
  message('renv.lock found → restore environment'); \
  renv::restore(prompt = FALSE); \
} else { \
  stop('renv.lock is required for a reproducible build'); \
}"
