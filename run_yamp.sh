#!/bin/bash


export PATH="$PATH:$(pwd)/bin:$(pwd)/bin/bbmap:$(pwd)/bin/FastQC"

data_folder="../testdata/"
sample_name="C2"
nextflow run YAMP.nf --reads1 $data_folder/$sample_name/*.1.fq.gz --reads2 $data_folder/$sample_name/*.2.fq.gz --prefix $sample_name --outdir $data_folder/../preprocessed --mode QC -resume --dedup false