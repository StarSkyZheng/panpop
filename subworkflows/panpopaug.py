
def getvcf_aug(wildcards):
    GRAPH = config['graph']
    MAP = config['mapper']
    MINQ = str(config['MAP_MINQ'])
    return('2.callSV/{sample}/{sample}-' + GRAPH + '.' + MAP + '.aug.q' + MINQ + '.call.ext.vcf.gz')

def getpack_aug(wildcards):
    GRAPH = config['graph']
    MAP = config['mapper']
    MINQ = str(config['MAP_MINQ'])
    return('2.callSV/{sample}/{sample}-' + GRAPH + '.' + MAP + '.aug.q' + MINQ + '.pack')

def getpg_aug(wildcards):
    GRAPH = config['graph']
    MAP = config['mapper']
    MINQ = str(config['MAP_MINQ'])
    return('2.callSV/{sample}/{sample}-' + GRAPH + '.' + MAP + '.aug.pg')


rule vcf2poss:
    input: '4.realign/1.realign1.{chrm}.sorted.vcf.gz',
    output: '6.aug_dp/1.{chrm}.poss',
    log:  'logs/6.1.vcf2poss.{chrm}.log',
    threads: 1
    shell:
        """
        perl {workflow.basedir}/scripts/vcf2pos_range.pl {input} {output} > {log} 2>&1
        """

rule cal_aug_dp:
    input:
        poss = '6.aug_dp/1.{chrm}.poss',
        pack = getpack_aug,
        pg = getpg_aug
    output: 
        list_packpg = '6.aug_dp/2.dps.{chrm}/{sample}.list_packpg',
        dpfile = '6.aug_dp/2.dps.{chrm}/{sample}.depth.txt.gz',
    log: 'logs/6.2.cal_aug_dp.{chrm}.{sample}.log',
    threads: 1
    params:
        outdir = '6.aug_dp/2.dps.{chrm}'
    shell:
        """
        echo '{wildcards.sample} {input.pack} {input.pg}' > {output.list_packpg}
        perl {workflow.basedir}/scripts/cal_range_depth_aug.pl --vcfposs {input.poss} --list_packpg {output.list_packpg} --outdir {params.outdir} -t {threads} --chr {wildcards.chrm} > {log} 2>&1
        """

rule merge_dp_vcf:
    input:
        dpfile = '6.aug_dp/2.dps.{chrm}/{sample}.depth.txt.gz',
        vcf = getvcf_aug,
        ref = GRAPH + '.gfa.fa',
    output:
        vcf = '6.aug_dp/3.vcf_with_dp.{chrm}/{sample}.vcf.gz',
        vcf_sorted = '6.aug_dp/3.vcf_with_dp.{chrm}/{sample}.sort.vcf.gz',
        vcf_sortedtbi = '6.aug_dp/3.vcf_with_dp.{chrm}/{sample}.sort.vcf.gz.tbi',
    params:
        min_dp = config['aug_nomut_min_dp'],
        min_cov = config['aug_nonmut_min_cov'],
    log: 'logs/6.3.merge_dp_vcf.{chrm}.{sample}.log',
    shell:
        """
        perl {workflow.basedir}/scripts/cal_range_depth_aug.fillvcf.pl --in_vcf {input.vcf} --out_vcf {output.vcf} --ref {input.ref} --min_dp {params.min_dp} --min_cov {params.min_cov} --chr {wildcards.chrm} --dp_file {input.dpfile} > {log} 2>&1
        {BCFTOOLS} sort --temp-dir {ZTMPDIR}/ -o {output.vcf_sorted} -O z {output.vcf} >> {log} 2>&1
        {TABIX} {output.vcf_sorted}
        """


rule aug_merge_rawvcfs_gen_list:
    input:
        vcfs = expand('6.aug_dp/3.vcf_with_dp.{chrm}/{sample}.sort.vcf.gz', sample=SAMPLES, chrm='all'), ############
    output:
        outfile = '7.aug_merge_rawvcf/1.inputvcfs.{chrm}.list',
    run:
        with open(output.outfile, 'w') as f:
            for vcf in input.vcfs:
                f.write(vcf + '\n')

rule aug_merge_rawvcfs:
    input:
        vcfslist = '7.aug_merge_rawvcf/1.inputvcfs.{chrm}.list'
    output:
        vcf = '7.aug_merge_rawvcf/2.merge_rawvcf.{chrm}.vcf.gz'
    log:
        'logs/7.2.merge_rawvcf.{chrm}.log'
    shell:
        """
        {BCFTOOLS} merge -m none -o {output.vcf} -O z -l {input.vcfslist} > {log} 2>&1
        """

rule aug_merge_same_pos:
    input:
        vcf = '7.aug_merge_rawvcf/2.merge_rawvcf.{chrm}.vcf.gz'
    output:
        vcf = '7.aug_merge_rawvcf/3.merge_same_pos.{chrm}.vcf.gz'
    log:
        'logs/7.3.merge_same_pos.{chrm}.vcf.gz.log'
    threads: config['core_realign']
    resources:
        mem_mb=2000
    shell:
        """
        perl {workflow.basedir}/scripts/merge_vcf_same_pos.pl --invcf {input.vcf} --outvcf {output.vcf} --threads {threads} > {log} 2>&1
        """

rule aug_filter_raw_vcf:
    input:
        vcf = '7.aug_merge_rawvcf/3.merge_same_pos.{chrm}.vcf.gz',
        depthfile = '2.callSV.DPinfos.txt',
    output:
        vcf = '7.aug_merge_rawvcf/4.filter_raw_vcf.{chrm}.vcf.gz',
    log:
        'logs/7.4.filter_raw_vcf.{chrm}.vcf.gz.log'
    threads: config['core_realign']
    resources:
        mem_mb=2000
    params:
        dp_min_fold = config['dp_min_fold'],
        dp_max_fold = config['dp_max_fold'],
        mad_min_fold = config['mad_min_fold'],
    shell:
        """
        perl {workflow.basedir}/scripts/flt_raw_vcfs.pl --invcf {input.vcf} --outvcf {output.vcf} --miss_threshold 1 --threads {threads} --dp_min_fold {params.dp_min_fold} --dp_max_fold {params.dp_max_fold} --mad_min_fold {params.mad_min_fold} --depth_file {input.depthfile} > {log} 2>&1
        """

# Realign
rule aug_realign1:
    input:
        vcf = '7.aug_merge_rawvcf/4.filter_raw_vcf.{chrm}.vcf.gz',
        ref_fasta_file = GRAPH + '.gfa.fa'
    output:
        vcf = '8.aug_realign/1.realign1.{chrm}.vcf.gz',
        vcf_sorted = '8.aug_realign/1.realign1.{chrm}.sorted.vcf.gz',
    log:
        'logs/8.1.realign1.{chrm}.vcf.gz.log'
    threads: config['core_realign']
    resources:
        mem_mb=config['mem_realign']
    params:
        realign_extend_bp_max = config['realign_extend_bp_max'],
        realign_extend_bp_min = config['realign_extend_bp_min'],
        tmpdir = config['memory_tmp_dir']
    shell:
        """
        perl {workflow.basedir}/scripts/realign.pl --in_vcf {input.vcf} --out_vcf {output.vcf} --ref_fasta_file {input.ref_fasta_file} --threads {threads} --ext_bp_max {params.realign_extend_bp_max} --ext_bp_min {params.realign_extend_bp_min} --tmpdir {params.tmpdir}  > {log} 2>&1
        {BCFTOOLS} sort --temp-dir {ZTMPDIR}/ -o {output.vcf_sorted} -O z {output.vcf} >> {log} 2>&1
        """

rule aug_filter_maf1:
    input:
        vcf = '8.aug_realign/1.realign1.{chrm}.sorted.vcf.gz'
    output:
        vcf = '8.aug_realign/2.filter_maf1.{chrm}.vcf.gz'
    log:
        'logs/8.2.filter_maf1.{chrm}.vcf.gz.log'
    threads: config['core_realign']
    params:
        min_maf = config['MAF'],
        max_miss_freq = config['max_missing_rate']
    shell:
        """
        perl {workflow.basedir}/scripts/flt_vcf_maf_by_allele.pl --in {input.vcf} --out {output.vcf} --min_maf {params.min_maf} --max_miss_freq {params.max_miss_freq} --threads {threads} > {log} 2>&1
        """


rule aug_realign2:
    input:
        vcf = '8.aug_realign/2.filter_maf1.{chrm}.vcf.gz',
        ref_fasta_file = GRAPH + '.gfa.fa'
    output:
        vcf = '8.aug_realign/3.realign2.{chrm}.vcf.gz',
        vcf_sorted = '8.aug_realign/3.realign2.{chrm}.sorted.vcf.gz',
    log:
        'logs/8.3.realign1.{chrm}.vcf.gz.log'
    threads: config['core_realign']
    resources:
        mem_mb=config['mem_realign']
    params:
        realign_extend_bp_max = config['realign_extend_bp_max'],
        realign_extend_bp_min = config['realign_extend_bp_min'],
        tmpdir = config['memory_tmp_dir']
    shell:
        """
        perl {workflow.basedir}/scripts/realign.pl --in_vcf {input.vcf} --out_vcf {output.vcf} --ref_fasta_file {input.ref_fasta_file} --threads {threads} --ext_bp_max {params.realign_extend_bp_max} --ext_bp_min {params.realign_extend_bp_min} --tmpdir {params.tmpdir}  > {log} 2>&1
        {BCFTOOLS} sort --temp-dir {ZTMPDIR}/ -o {output.vcf_sorted} -O z {output.vcf} > {log} 2>&1
        """

rule aug_filter_maf2:
    input:
        vcf = '8.aug_realign/3.realign2.{chrm}.sorted.vcf.gz'
    output:
        vcf = '8.aug_realign/4.filter_maf1.{chrm}.vcf.gz'
    log:
        'logs/8.4.filter_maf1.{chrm}.vcf.gz.log'
    threads: config['core_realign']
    params:
        min_maf = config['MAF'],
        max_miss_freq = config['max_missing_rate']
    shell:
        """
        perl {workflow.basedir}/scripts/flt_vcf_maf_by_allele.pl --in {input.vcf} --out {output.vcf} --min_maf {params.min_maf} --max_miss_freq {params.max_miss_freq} --threads {threads} > {log} 2>&1
        """


# Finally
rule aug_split_vcf_by_type:
    input:
        vcf = '8.aug_realign/4.filter_maf1.{chrm}.vcf.gz'
    output:
        vcf_all = '9.aug_final_result/1.final.{chrm}.all.vcf.gz',
        vcf_snp = '9.aug_final_result/2.final.{chrm}.snp.vcf.gz',
        vcf_indel = '9.aug_final_result/2.final.{chrm}.indel.vcf.gz',
        vcf_sv = '9.aug_final_result/2.final.{chrm}.sv.vcf.gz'
    log:
        'logs/9.split_vcf.{chrm}.log'
    params:
        outprefix = '9.aug_final_result/2.final.{chrm}',
        min_sv_len = config['SV_min_length']
    shell:
        """
        cp {input.vcf} {output.vcf_all}
        perl {workflow.basedir}/scripts/vcf_split_snp_indel_sv.pl {input.vcf} {params.outprefix} {params.min_sv_len} > {log} 2>&1
        """


rule aug_merge_vcf_splitchrs:
    input:
        vcfs = expand('8.aug_realign/4.filter_maf1.{chrm}.vcf.gz', chrm=CHRS),
    output:
        vcf = '9.aug_final_result/1.final_mergechr.all.vcf.gz'
    threads:
        6
    log:
        'logs/9.1.merge.log'
    shell:
        """
        {BCFTOOLS} concat -o {output.vcf} -O z --threads {threads} {input.vcfs} > {log} 2>&1
        """

rule aug_split_vcf_by_type_splitchr:
    input:
        vcf = '9.aug_final_result/1.final_mergechr.all.vcf.gz'
    output:
        vcf_snp = '9.aug_final_result/2.final_mergechr.snp.vcf.gz',
        vcf_indel = '9.aug_final_result/2.final_mergechr.indel.vcf.gz',
        vcf_sv = '9.aug_final_result/2.final_mergechr.sv.vcf.gz'
    log:
        'logs/9.2.split_vcf.log'
    params:
        outprefix = '9.aug_final_result/2.final_mergechr',
        min_sv_len = config['SV_min_length']
    shell:
        """
        perl {workflow.basedir}/scripts/vcf_split_snp_indel_sv.pl {input.vcf} {params.outprefix} {params.min_sv_len} > {log} 2>&1
        """
