#!/usr/bin/env nextflow
	
/**
	Yet Another Metagenomic Pipeline (YAMP)
	Copyright (C) 2017 	Dr Alessia Visconti 	      
	      
	This script is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This script is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this script. If not, see <http://www.gnu.org/licenses/>.
	
	For any bugs or problems found, please contact us at:
	- alessia.visconti@kcl.ac.uk ; 
	- https://github.com/alesssia/YAMP/issues
*/

	
/**
	STEP 0. 
	
	Checks input parameters and (if it does not exists) creates the directory 
	where the results will be stored (aka working directory). 
	Initialises the log file.
	
	The working directory is named after the prefix and located in the outdir 
	folder. The log file, that will save summary statistics, execution time,
	and warnings generated during the pipeline execution, will be saved in the 
	working directory as "prefix.log".
*/


//Checking user-defined parameters	
if (params.mode != "QC" && params.mode != "characterisation" && params.mode != "complete") {
	exit 1, "Mode not available. Choose any of <QC, characterisation, complete>"
}	

if (params.librarylayout != "paired" && params.librarylayout != "single") { 
	exit 1, "Library layout not available. Choose any of <single, paired>" 
}   

if (params.qin != 33 && params.qin != 64) { 
	exit 1, "Input quality offset (qin) not available. Choose either 33 (ASCII+33) or 64 (ASCII+64)" 
}   

//--reads2 can be omitted when the library layout is "single" (indeed it specifies single-end
//sequencing)
if (params.librarylayout != "single" && (params.reads2 == "null") ) {
	exit 1, "If dealing with paired-end reads, please set the reads2 parameters\nif dealing with single-end reads, please set the library layout to 'single'"
}

//--reads1 and --reads2 can be omitted (and the default from the config file used instead) 
//only when mode is "characterisation". Obviously, --reads2 should be always omitted when the
//library layout is single.
if (params.mode != "characterisation" && ( (params.librarylayout == "paired" && (params.reads1 == "null" || params.reads2 == "null")) ||			
 							 			   params.librarylayout == "single" && params.reads1 == "null") ) {
	exit 1, "Please set the reads1 and/or reads2 parameters"
}


//Creates working dir
workingpath = params.outdir + "/" + params.prefix
workingdir = file(workingpath)
if( !workingdir.exists() ) {
    if( !workingdir.mkdirs() ) 	{
        exit 1, "Cannot create working directory: $workingpath"
    } 
}	

//Creates main log file
mylog = file(params.outdir + "/" + params.prefix + "/" + params.prefix + ".log")

//Logs headers
mylog <<  """---------------------------------------------
YET ANOTHER METAGENOMIC PIPELINE (YAMP) v 0.9.3
---------------------------------------------
	
Copyright (C) 2017 Dr Alessia Visconti   <alessia.visconti@kcl.ac.uk>

This pipeline is distributed in the hope that it will be useful
but WITHOUT ANY WARRANTY. See the GNU GPL v3.0 for more details.

Please report comments and bugs to: alessia.visconti@kcl.ac.uk						  
Check http://github.com/alesssia/YAMP for updates.

++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++   						   	   
"""
	   
//Logs starting time and other information about the run
sysdate = new java.util.Date() 
mylog << """ 
Analysis starting at $sysdate 
Analysed samples are: $params.reads1 and $params.reads2
Results will be saved at $workingdir
New files will be saved using the '$params.prefix' prefix

Analysis mode? $params.mode
Library layout? $params.librarylayout
Saving QC temporary files? $params.keepQCtmpfile
Saving community characterisation temporary files? $params.keepCCtmpfile
Performing de-duplication? $params.dedup	
	     
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++   
	   
""" 
	   		

/**
	STEP 1. Assessment of read quality of FASTQ file, done by FastQC. Multiple 
	plots are generated to show average phred quality scores and other metrics.

	This step will generate (for each end, if the layout is paired) an HTML page,
	showing a summary of the results and a set of plots offering a visual guidance
	and for assessing the quality of the sample, and a zip file, that includes the 
	HTML page, all the images and a text report. The script will save the HTML page 
	and the text report and delete the archive.
	Several information on multiple QC parameters are logged.
*/


//Defines channel with <readfile, label> as input for fastQC script
//When layout is single, the params.reads2 is not used
if (params.librarylayout == "paired") {
	rawreads = Channel.from( [file(params.reads1), '_R1'], [file(params.reads2), '_R2'] )
}
else {
	rawreads = Channel.value( [file(params.reads1), ''] )
}

//This step is not a prerequisite for any other, so it does not redirect any of its output to channels
process qualityAssessmentRaw {
	
	publishDir  workingdir, mode: 'copy', pattern: "*.{html,txt}"
	  	
	input:
   	set file(reads), val(label) from rawreads

	output:
	file ".log.1$label" into log1
	file "${params.prefix}*_fastqc.html" 
	file "${params.prefix}*_fastqc_data.txt" 

	when:
	(params.mode == "QC" || params.mode == "complete") 

   	script:
	"""	
	#Measures execution time
	sysdate=\$(date)
	starttime=\$(date +%s.%N)
	echo \"Performing STEP 1 [Assessment of read quality of FASTQ file] at \$sysdate on $reads\" > .log.1$label
	echo \" \" >> .log.1$label
	 
	#Does QC, extracts relevant information, and removes temporary files
	bash fastQC.sh $reads ${params.prefix}${label} $threads $reads
	
	#Logging QC statistics (number of sequences, Pass/warning/fail, basic statistics, duplication level, kmers)
	base=\$(basename $reads)
	bash logQC.sh \$base ${params.prefix}${label}_fastqc_data.txt .log.1$label
				
	#Measures and log execution time			
	endtime=\$(date +%s.%N)
	exectime=\$(echo \"\$endtime - \$starttime\" | bc)
	sysdate=\$(date)
	echo \"STEP 1 on $reads terminated at \$sysdate (\$exectime seconds)\" >> .log.1$label
	echo \" \" >> .log.1$label	
	echo \"++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\" >> .log.1$label
	echo \" \" >> .log.1$label	
	"""	
}



/**
	STEP 2. De-duplication. Only exact duplicates are removed.

	If the layout is "paired", two FASTQ files are outputted, one for each paired-end.
	If "single", a single FASTQ file will be generated.
*/

// Defines channel with <readfile1, readfile2> as input for de-duplicates
// When layout is single, the params.reads2 is not used, so nevermind its value
if (params.librarylayout == "paired") {
	todedup = Channel.value( [file(params.reads1), file(params.reads2)] )
} 
else {
	todedup = Channel.value( [file(params.reads1), "null"] )
}

process dedup {
	
	input:
	set file(in1), file(in2) from todedup

	output:
	file  ".log.2" into log2
	file("${params.prefix}_dedupe*.fq.gz") into totrim
	file("${params.prefix}_dedupe*.fq.gz") into topublishdedupe

	when:
	(params.mode == "QC" || params.mode == "complete") && params.dedup

	script:
	"""
	set -e
	#Measures execution time
	sysdate=\$(date)
	starttime=\$(date +%s.%N)
	echo \"Performing STEP 2 [De-duplication] at \$sysdate\" > .log.2
	echo \" \" >> .log.2

	#De-duplicates
	if [ \"$params.librarylayout\" = \"paired\" ]; then
		clumpify.sh -Xmx$maxmem in1=$in1 in2=$in2 out1=${params.prefix}_dedupe_R1.fq.gz out2=${params.prefix}_dedupe_R2.fq.gz qin=$params.qin dedupe subs=0 threads=$threads &> tmp.log
	else
		clumpify.sh -Xmx$maxmem in=$in1 out=${params.prefix}_dedupe.fq.gz qin=$params.qin dedupe subs=0 threads=$threads &> tmp.log
	fi

	#Logs some figures about sequences passing de-duplication
	echo  \"BBduk's de-duplication stats: \" >> .log.2
	echo \" \" >> .log.2
	sed -n '/Reads In:/,/Duplicates Found:/p' tmp.log >> .log.2
	echo \" \" >> .log.2
	totR=\$(grep \"Reads In:\" tmp.log | cut -f 1 | cut -d: -f 2 | sed 's/ //g')
	remR=\$(grep \"Duplicates Found:\" tmp.log | cut -f 1 | cut -d: -f 2 | sed 's/ //g')
	survivedR=\$((\$totR-\$remR))
	percentage=\$(echo \$survivedR \$totR | awk '{print \$1/\$2*100}' )
	echo \"\$survivedR out of \$totR paired reads survived de-duplication (\$percentage%, \$remR reads removed)\" >> .log.2
	echo \" \" >> .log.2

	#Measures and logs execution time
	endtime=\$(date +%s.%N)
	exectime=\$(echo \"\$endtime - \$starttime\" | bc)
	sysdate=\$(date)
	echo \"STEP 2 terminated at \$sysdate (\$exectime seconds)\" >> .log.2
	echo \" \" >> .log.2
	echo \"++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\" >> .log.2
	echo \" \" >> .log.2
	"""
}

/**
	STEP 3. Trimming of low quality bases and of adapter sequences. Short reads
	are discarded. A decontamination of synthetic sequences is also pefoermed.
	If dealing with paired-end reads, when either forward or reverse of a paired-read
	are discarded, the surviving read is saved on a file of singleton reads.

	If layout is "paired", three compressed FASTQ file (forward/reverse paired-end 
	and singleton reads) are outputed, if "single", only one compressed FASTQ file
	is returned. Several information are logged.
*/


//When the de-suplication is not done, the raw file should be pushed in the corret channel
if (!params.dedup) {
	if (params.librarylayout == "paired") {
		totrim = Channel.value( [file(params.reads1), file(params.reads2)] )
	} 
	else {
		totrim = Channel.value( [file(params.reads1), "null"] )
	}
}

//When single-end reads are used, the input tuple (singleton) will not match input set 
//cardinality declared by 'trim' process (pair), so I push two mock files in the channel,
//and then I take only the first two files
mocktrim = Channel.from("null")
process trim {

	input:
   	set file(reads1), file(reads2) from totrim.concat(mocktrim).flatMap().take(2).buffer(size : 2)
	file(adapters) from Channel.from( file(params.adapters) )
	file(artifacts) from Channel.from( file(params.artifacts) )
	file(phix174ill) from Channel.from( file(params.phix174ill) )

	output:
	file  ".log.3" into log3
	file("${params.prefix}_trimmed*.fq") into trimmedreads
	file("${params.prefix}_trimmed*.fq") into todecontaminate
	file("${params.prefix}_trimmed*.fq") into topublishtrim 	

	when:
	params.mode == "QC" || params.mode == "complete"

   	script:
	"""	
	set -e
	#Measures execution time
	sysdate=\$(date)
	starttime=\$(date +%s.%N)
	echo \"Performing STEP 3 [Trimming] at \$sysdate\" > .log.3
	echo \" \" >> .log.3

	#Trims adapters and low quality sequences
	if [ \"$params.librarylayout\" = \"paired\" ]; then
		bbduk.sh -Xmx$maxmem in=$reads1 in2=$reads2 out=${params.prefix}_trimmed_R1_tmp.fq out2=${params.prefix}_trimmed_R2_tmp.fq outs=${params.prefix}_trimmed_singletons_tmp.fq ktrim=r k=$params.kcontaminants mink=$params.mink hdist=$params.hdist qtrim=rl trimq=$params.phred  minlength=$params.minlength ref=$adapters qin=$params.qin threads=$threads tbo tpe ow &> tmp.log
	else
		bbduk.sh -Xmx$maxmem in=$reads1 out=${params.prefix}_trimmed_tmp.fq ktrim=r k=$params.kcontaminants mink=$params.mink hdist=$params.hdist qtrim=rl trimq=$params.phred  minlength=$params.minlength ref=$adapters qin=$params.qin threads=$threads tbo tpe ow &> tmp.log
	fi
	
	#Logs some figures about sequences passing trimming
	echo  \"BBduk's trimming stats (trimming adapters and low quality sequences): \" >> .log.3
	sed -n '/Input:/,/Result:/p' tmp.log >> .log.3
	echo \" \" >> .log.3			
	if [ \"$params.librarylayout\" = \"paired\" ]; then
		unpairedR=\$(wc -l ${params.prefix}_trimmed_singletons_tmp.fq | cut -d\" \" -f 1)
		unpairedR=\$((\$unpairedR/4))
		echo  \"\$unpairedR singleton reads whose mate was trimmed shorter preserved\" >> .log.3
		echo \" \" >> .log.3
	fi

	#Removes synthetic contaminants
	if [ \"$params.librarylayout\" = \"paired\" ]; then
		bbduk.sh -Xmx$maxmem in=${params.prefix}_trimmed_R1_tmp.fq in2=${params.prefix}_trimmed_R2_tmp.fq out=${params.prefix}_trimmed_R1.fq out2=${params.prefix}_trimmed_R2.fq k=31 ref=$phix174ill,$artifacts qin=$params.qin threads=$threads ow &> tmp.log
	else
		bbduk.sh -Xmx$maxmem in=${params.prefix}_trimmed_tmp.fq out=${params.prefix}_trimmed.fq k=31 ref=$phix174ill,$artifacts qin=$params.qin threads=$threads ow &> tmp.log
	fi

	#Logs some figures about sequences passing deletion of contaminants
	echo  \"BBduk's trimming stats (synthetic contaminants): \" >> .log.3
	sed -n '/Input:/,/Result:/p' tmp.log >> .log.3
	echo \" \" >> .log.3

	#Removes synthetic contaminants and logs some figures (singleton read file, 
	#that exists iif the library layout was 'paired')
	if [ \"$params.librarylayout\" = \"paired\" ]; then
		bbduk.sh -Xmx$maxmem in=${params.prefix}_trimmed_singletons_tmp.fq out=${params.prefix}_trimmed_singletons.fq k=31 ref=$phix174ill,$artifacts qin=$params.qin threads=$threads ow &> tmp.log
							
		#Logs some figures about sequences passing deletion of contaminants
		echo  \"BBduk's trimming stats (synthetic contaminants, singleton reads): \" >> .log.3
		sed -n '/Input:/,/Result:/p' tmp.log >> .log.3
		echo \" \" >> .log.3
	fi
	
	#Removes tmp files. This avoids adding them to the output channels
	rm -rf ${params.prefix}_trimmed*_tmp.fq 

	#Measures and log execution time
	endtime=\$(date +%s.%N)
	exectime=\$(echo \"\$endtime - \$starttime\" | bc)
	sysdate=\$(date)
	echo \"STEP 3 terminated at \$sysdate (\$exectime seconds)\" >> .log.3
	echo \" \" >> .log.3
	echo \"++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\" >> .log.3
	echo \"\" >> .log.3
	"""
}


/**
	STEP 4. Quality control after trimming.

	An output similar to that generated by STEP 1 is produced
*/

process qualityAssessmentTrimmed {

	publishDir  workingdir, mode: 'copy', pattern: "*.{html,txt}"
	
	//Merges the files with their labels (that is 1 for R1 and 2 for R2)
	input:
   	set file(reads), val(label) from trimmedreads.flatMap().merge( Channel.from( ['_R1', '_R2'] ) ){ a, b -> [a, b] }

	output:
	file  ".log.4$label" into log4
	file "${params.prefix}_trimmed*fastqc.html"
	file "${params.prefix}_trimmed*fastqc_data.txt"

	when:
	params.mode == "QC" || params.mode == "complete"

   	script:
	"""
	set -e
	#Measures execution time
	sysdate=\$(date)
	starttime=\$(date +%s.%N)
	
	#If the library layout is 'single', there is no label to be added to the file
	if [ \"$params.librarylayout\" = \"paired\" ]; then
		label=$label
	else
		label=\"\"
	fi		
		
	echo \"Performing STEP 4 [Assessment of read quality of trimmed FASTQ file] at \$sysdate on $reads\" > .log.4$label
	echo \" \" >> .log.4$label

	#Does QC, extracts relevant information, and removes temporary files
	bash fastQC.sh $reads ${params.prefix}_trimmed\${label} $threads

	#Logging QC statistics (number of sequences, Pass/warning/fail, basic statistics, duplication level, kmers)
	base=\$(basename $reads)
	bash logQC.sh \$base ${params.prefix}_trimmed\${label}_fastqc_data.txt .log.4$label

	#Measures and log execution time
	endtime=\$(date +%s.%N)
	exectime=\$(echo \"\$endtime - \$starttime\" | bc)
	sysdate=\$(date)
	echo \"STEP 4 on $reads terminated at \$sysdate (\$exectime seconds)\" >> .log.4$label
	echo \" \" >> .log.4$label
	echo \"++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\" >> .log.4$label
	echo \" \" >> .log.4$label
	"""
}


/**
	STEP 5. Decontamination. Removes external organisms' contamination, using a previously
	created index. When paired-end are used, decontamination is carried on idependently
	on paired reads and on singleton reads thanks to BBwrap, that calls BBmap once
	on the paired reads and once on the singleton ones, merging the results on a
	single output file.

	Two files are outputted: the FASTQ of the decontaminated reads (including both
	paired-reads and singletons) and that of the contaminating reads (that can be
	used for refinements/checks).
	Please note that if keepQCtmpfile is set to false, the file of the contaminating 
	reads is discarded

	TODO: use BBsplit for multiple organisms decontamination, or fix the ref to a 
	FASTA file pangenome
*/

//When single-end reads are used, the input tuple (singleton) will not match input set 
//cardinality declared by 'trim' process (triplet), so I push two mock files in the channel,
//and then I take only the first three files.
mockdecontaminate = Channel.from("null", "null")
process decontaminate {

	publishDir  workingdir, mode: 'copy', pattern: "*_clean*.fq"
		
	input:
	set file(infile1), file(infile2), file(infile12) from todecontaminate.concat(mockdecontaminate).flatMap().take(3).buffer(size : 3)
	file(refForeingGenome) from Channel.from( file(params.refForeingGenome, type: 'dir') )
	
	output:
	file  ".log.5" into log5
	file "${params.prefix}_clean*.fq" into decontaminatedreads
	file "${params.prefix}_clean*.fq" into topairmates
	file "${params.prefix}_cont.fq" into topublishdecontaminate

	when:
	params.mode == "QC" || params.mode == "complete"
	
	script:
	"""
	set -e
	#Measures execution time
	sysdate=\$(date)
	starttime=\$(date +%s.%N)
	echo \"Performing STEP 5 [Decontamination] at \$sysdate\" > .log.5
	echo \" \" >> .log.5

	if [ \"$params.librarylayout\" = \"paired\" ]; then
		bbwrap.sh  -Xmx$maxmem mapper=bbmap append=t in1=$infile1,$infile12 in2=$infile2,null outu1=${params.prefix}_clean_R1.fq,${params.prefix}_clean_single.fq outu2=${params.prefix}_clean_R2.fq,null outm=${params.prefix}_cont.fq minid=$params.mind maxindel=$params.maxindel bwr=$params.bwr bw=12 minhits=2 qtrim=rl trimq=$params.phred path=$refForeingGenome qin=$params.qin threads=$threads untrim quickmatch fast ow &> tmp.log
	else
		bbwrap.sh  -Xmx$maxmem mapper=bbmap append=t in1=$infile1 outu=${params.prefix}_clean.fq outm=${params.prefix}_cont.fq minid=$params.mind maxindel=$params.maxindel bwr=$params.bwr bw=12 minhits=2 qtrim=rl trimq=$params.phred path=$refForeingGenome qin=$params.qin threads=$threads untrim quickmatch fast ow &> tmp.log
	fi
	
	#Logs some figures about decontaminated/contaminated reads
	echo  \"BBmap's ost decontamination stats (paired reads): \" >> .log.5
	sed -n '/Read 1 data:/,/N Rate:/p' tmp.log | head -17 >> .log.5
	echo \" \" >> .log.5
	sed -n '/Read 2 data:/,/N Rate:/p' tmp.log >> .log.5
	echo \" \" >> .log.5
	
	if [ \"$params.librarylayout\" = \"paired\" ]; then
		echo  \"BBmap's human decontamination stats (singletons reads): \" >> .log.5
		sed -n '/Read 1 data:/,/N Rate:/p' tmp.log | tail -17 >> .log.5
		echo \" \" >> .log.5
	fi

	nClean=\$(wc -l ${params.prefix}_clean_*.fq | cut -d\" \" -f 1)
	nClean=\$((\$nClean/4))
	nCont=\$(wc -l ${params.prefix}_cont.fq | cut -d\" \" -f 1)
	nCont=\$((\$nCont/4))
	echo \"\$nClean reads survived decontamination (\$nCont reads removed)\" >> .log.5
	echo \" \" >> .log.5

	#Measures and log execution time
	endtime=\$(date +%s.%N)
	exectime=\$(echo \"\$endtime - \$starttime\" | bc)
	sysdate=\$(date)
	echo \"STEP 5 terminated at \$sysdate (\$exectime seconds)\" >> .log.5
	echo \" \" >> .log.5
	echo \"++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\" >> .log.5
	echo \"\" >> .log.5
	"""
}


/**
	STEP 6. merge paired end reads

*/

//When single-end reads are used, the input tuple (singleton) will not match input set 
//cardinality declared by 'trim' process (triplet), so I push two mock files in the channel,
//and then I take only the first three files.
mockclean = Channel.from("null", "null")
process pairmates {

	publishDir  workingdir, mode: 'copy', pattern: "*preprocessed*"
		
	input:
	set file(infile1), file(infile2), file(infile12) from topairmates.concat(mockclean).flatMap().take(3).buffer(size : 3)
	
	output:
	file  ".log.6" into log6
	file "${params.prefix}_preprocessed*.fq" into preprocessedreads

	script:
	"""
	set -e

	bbmerge-auto.sh -Xmx$maxmem threads=$threads in1=$infile1 in2=$infile2 outm=merged.fq outu1=${params.prefix}_preprocessed_R1.fq outu2=${params.prefix}_preprocessed_R2.fq outadapter=detected_adapter.fasta vstrict rem k=62 extend2=50 ecct | tee tmp.log


	nmerged=\$(wc -l merged.fq | cut -d\" \" -f 1)
	nmerged=\$((\$nmerged/4))
	echo \"\$nmerged reads \" >> .log.6


	echo \"found adapters:\" >> .log.6
	cat adapters.fasta >> .log.6

	cat $infile12 merged.fq > ${params.prefix}_preprocessed_single.fq

	"""
}




/**
	CLEANUP 1. Collapses all the logs resulting from the QC in the main one, 
	and removes them.
*/

process logQC {

	input:
	file(tolog)  from log1.flatMap().mix(log2, log3, log4.flatMap(), log5, log6).toSortedList( { a, b -> a.name <=> b.name } )

	when:
	params.mode == "QC" || params.mode == "complete"

	script:
	"""
	cat $tolog >> $mylog
	"""
}

/**
	CLEANUP 2. Saves the temporary files generate during QC (if the users requested so)
*/

	
process saveQCtmpfile {

	publishDir  workingdir, mode: 'copy'
		
	input:
	file (tmpfile) from topublishdedupe.mix(topublishtrim, topublishdecontaminate).flatMap()

	output:
	file "$tmpfile"

	when:
	(params.mode == "QC" || params.mode == "complete") && params.keepQCtmpfile
		
	script:
	"""
	echo $tmpfile
	"""
}

