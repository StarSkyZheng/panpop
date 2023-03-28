#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;
use Getopt::Long;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use zzIO;
use zzBed;
no warnings 'experimental::smartmatch';
# use Data::Dumper;

my ($in, $ref_fasta_file, $opt_help, $software, $not_rename);

my ($out, $out_inv);

my $max_len = 50000;
my $min_dp = 5;
my @known_softwares = qw/pbsv svim cutesv sniffles2/;

sub help {
    my ($info) = @_;
    say STDERR $info if $info;
    say <<EOF;
Usage: $0 -i <in.vcf> -r <ref.fa> -o <out.vcf>
    -i, --in <in.vcf>       input vcf file
    -r, --ref <ref.fa>      reference fasta file
    -o, --out <out.vcf>     output vcf file
    -O, --out_inv <out.bed> output inv bed file
    -s, --software <str>    software name: pbsv, svim, cutesv, sniffles2
    -h, --help              print this help message
    --max_len <int>         max length of SV, default $max_len
    --min_dp <int>          min reads depth of SV, default $min_dp
    --not_rename
EOF
    exit(-1);
}

my $ARGVs = join ' ', $0, @ARGV;

GetOptions (
        'help|h!' => \$opt_help,
        'i|in=s' => \$in,
        'r|ref=s' => \$ref_fasta_file,
        'o|out=s' => \$out,
        'O|out_inv=s' => \$out_inv,
        'max_len=s' => \$max_len,
        'd|min_dp=i' => \$min_dp,
        's|software=s' => \$software,
        'not_rename!' => \$not_rename,
);

&help() if $opt_help;
&help("--in not defined") unless defined $in;
&help("--out not defined") unless defined $out;
&help("--out_inv not defined") unless defined $out_inv;
#&help("--software not defined") unless defined $software;
&help("--ref not defined") unless defined $ref_fasta_file;

$software = lc($software) if defined $software;
&help() if(defined $software and ! $software ~~ @known_softwares);


my $ref_fasta;
$ref_fasta = &read_ref_fasta($ref_fasta_file) if defined $ref_fasta_file;
my $I = open_in_fh($in);
my $O = open_out_fh($out);
my $inv_bed = new zzBed({outfile=>$out_inv});
#my $inv_bed = new zzBed({outfile=>$out_inv, max_len=>$max_len});
#my $OB = open_out_fh($out_inv);
my @header;

LINE:while(<$I>) { # vcf-header
    chomp;
    my $software_guessed;
    if(/^#/) {
        if(/^##/) {
            if(/^##source=([a-zA-Z0-9]+)/) {
                $software_guessed = $1;
                $software_guessed = lc $software_guessed;
                if(!defined $software) {
                    if ($software_guessed ~~ @known_softwares) {
                        $software = $software_guessed;
                        say STDERR "software guessed: $software";
                    } else {
                        die "Fail to guess software and software name not defined, please use -s to specify it";
                    }
                }
            }
            say $O $_;
            next;
        }
        say $O qq+##CommandLine="$ARGVs"+;
        @header = split /\t/, $_;
        if(defined $not_rename) {
            say $O $_;
        } else {
            say $O join "\t", @header[0..8], $software;
        }
        last;
    }
}

LINE:while(<$I>) { # bed
    chomp;
    my @F = split /\t/;
    my ($chr, $pos, $svid, $ref, $alts) = @F[0,1,2,3,4];
    my $infos = $F[7];
    my $dp;
    if($software eq 'sniffles2') {
        $dp = &get_DR_DV(\@F);
        if( $F[4] eq '<DEL>' ) {
            next LINE if $dp < $min_dp;
            &Update_ref_alt(\@F, 'DEL');
        } elsif( $F[4] eq '<INS>' ) {
            next LINE if $dp < $min_dp;
            next LINE;
        } elsif( $svid =~ /^Sniffles2.INS\.\w+$/ ) {
            next LINE if $dp < $min_dp;
            &Update_ref_alt(\@F, 'INS');
        } elsif( $F[4] eq '<INV>' ) {
            #&Update_ref_alt(\@F, 'INV');
            $inv_bed->add_inv_bed(\@F, $svid); next LINE;
        } elsif( $F[4] eq '<DUP>' ) {
            next LINE if $dp < $min_dp;
            &Update_ref_alt(\@F, 'DUP');
            &Update_ref_alt(\@F, 'INS');
        } else {
            next LINE;
        }
    } elsif($software eq 'pbsv') {
        $dp = &get_DP(\@F);
        if($svid =~ /^pbsv.DEL\.\w+$/ or $svid =~ /^pbsv.INS\.\w+$/) {
            next LINE if $dp < $min_dp;
            # do nothing
        } elsif( $F[4] eq '<DUP>') {
            next LINE if $dp < $min_dp;
            &Update_ref_alt(\@F, 'DUP');
        } elsif( $F[4] eq '<INV>') {
            #&Update_ref_alt(\@F, 'INV');
            $inv_bed->add_inv_bed(\@F, $svid); next LINE;
        } else {
            # say STDERR "unknown type: @F";
            next LINE;
        }
    } elsif($software eq 'svim') {
        $dp = &get_DP(\@F);
        next LINE if $F[9]=~m#^0\/0#;
        next LINE if $F[9]=~m#^\./\.#;        
        if($svid =~ /^svim.DEL\.\w+$/ or $svid =~ /^svim.INS\.\w+$/) {
            next LINE if $dp < $min_dp;
            # do nothing
        } elsif( $svid =~ /^svim.INV\.\w+$/ ) {
            $inv_bed->add_inv_bed(\@F, $svid); next LINE;
        } elsif( $F[4]=~m/^<DUP/) {
            next LINE if $dp < $min_dp;
            &Update_ref_alt(\@F, 'DUP');
        } else {
            next LINE;
        }
    } elsif($software eq 'cutesv') {
        $dp = &get_DR_DV(\@F);
        if($svid =~ /^cuteSV.DEL\.\w+$/ or $svid =~ /^cuteSV.INS\.\w+$/) {
            next line if $dp < $min_dp;
            # do nothing
        } elsif( $F[4] eq '<DUP>') {
            next line if $dp < $min_dp;
            &Update_ref_alt(\@F, 'DUP');
        } elsif( $F[4] eq '<INV>' ) {
            #&Update_ref_alt(\@F, 'INV');
            $inv_bed->add_inv_bed(\@F, $svid); next LINE;
        } else {
            next LINE;
        }
    } else {
        die;
    }
    if( $F[4]=~m/</ or $F[3]=~m/</  ) {
        next LINE;
    } 
    my $svlen = &max(length($F[3]), length($F[4]));
    next if $svlen > $max_len;
    $F[7] = '.'; # remove all infos
    say $O join "\t", @F;
}


$inv_bed->sort_bed();
$inv_bed->merge_bed();
$inv_bed->print_bed();

exit;


sub max {
    my ($a, $b) = @_;
    return $a > $b ? $a : $b;
}


sub Update_ref_alt {
    my ($line, $type) = @_;
    my $chr = $$line[0];
    my $pos = $$line[1];
    my $infos = $$line[7];
    $infos =~ /SVLEN=(-?\d+)(;|$)/ or die;
    my ($svlen) = ($1);
    $svlen = abs($svlen);
    if($type eq 'DEL') {
        $$line[3] = substr($ref_fasta->{$chr}, $pos-1, $svlen);
        $$line[4] = substr($$line[3], 0, 1);
    } elsif($type eq 'INS') {
        $$line[3] = substr($ref_fasta->{$chr}, $pos-1, 1);
    } elsif($type eq 'INV') {
        $$line[3] = substr($ref_fasta->{$chr}, $pos-1, $svlen);
        $$line[4] = &revcomp($$line[3]);
    } elsif($type eq 'DUP') {
        $$line[4] = substr($ref_fasta->{$chr}, $pos-1, $svlen);
    } else {
        die;
    }
}

sub revcomp {
    my ($seq) = @_;
    my $rev = reverse $seq;
    $rev =~ tr/ACGTacgt/TGCAtgca/;
    $rev =~ s/[^ACGTacgt]/N/g;
    return $rev;
}

sub get_DP { # pbsv svim
    # extract DP from vcf line
    my ($line) = @_;
    my @format = split /:/, $$line[8];
    my @values = split /:/, $$line[9];
    my %hash;
    foreach my $i (0..$#format) {
        $hash{$format[$i]} = $values[$i];
    }
    my $DP = $hash{DP} // die;
    $DP = 0 if $DP eq '.';
    return($DP);
}

sub get_DR_DV { # cuteSV sniffles2
    # extract DR and DV from vcf line
    # ##FORMAT=<ID=DR,Number=1,Type=Integer,Description="Number of reference reads">
    # ##FORMAT=<ID=DV,Number=1,Type=Integer,Description="Number of variant reads">
    my ($line) = @_;
    my @format = split /:/, $$line[8];
    my @values = split /:/, $$line[9];
    my %hash;
    foreach my $i (0..$#format) {
        $hash{$format[$i]} = $values[$i];
    }
    my $DR = $hash{DR} // die;
    my $DV = $hash{DV} // die;
    $DR = 0 if $DR eq '.';
    $DV = 0 if $DV eq '.';
    my $DP = $DR + $DV;
    return($DP);
}

exit;

sub read_ref_fasta {
    my $ref_fasta_file = shift;
    my $I = open_in_fh($ref_fasta_file);
    my %ref;
    my $id;
    while(<$I>) {
        chomp;
        if(/^>(\S+)/) {
            $id = $1;
            next;
        }
        $ref{$id} .= $_;
    }
    return \%ref;
}

