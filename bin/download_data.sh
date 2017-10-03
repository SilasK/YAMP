#! /bin/bash

curl -fsSL get.nextflow.io | bash
#wget http://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.11.5.zip
#unzip fastqc*

wget https://sourceforge.net/projects/samtools/files/samtools/1.6/samtools-1.6.tar.bz2
tar -xjf samtools-1.6.tar.bz2

wget  https://sourceforge.net/projects/bbmap/files/BBMap_37.56.tar.gz
tar -xzf BBMap_37.56.tar.gz