#!/usr/bin/env perl
use strict;
use warnings;
use v5.10;
use Getopt::Long;
use Data::Dumper;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use zzIO;

my ($in, $out, $min_supporting, $samplename, $opt_help);

$min_supporting = 2;

sub help {
    my ($info) = @_;
    say STDERR $info if $info;
    say <<EOF;
    perl $0 -i <in.vcf> -o <out.vcf> -s <sample_name>
    -i, --in <in.vcf>           input vcf file
    -o, --out <out.vcf>         output vcf file
    -m, --min_supporting <int>  min supporting samples, default $min_supporting
    -s, --sample <str>          sample name
    -h, --help                  print this help message
EOF
    exit(-1);
}

my $ARGVs = join ' ', $0, @ARGV;

GetOptions (
        'help|h!' => \$opt_help,
        'i|in=s' => \$in,
        'o|out=s' => \$out,
        'm|min_supporting=s' => \$min_supporting,
        's|sample=s' => \$samplename,
);

&help() if $opt_help;
&help() unless defined $in;
&help() unless defined $out;

my $I = open_in_fh($in);
my $O = open_out_fh($out);
my @header;

while(my $line = <$I>) { # vcf
    chomp $line;
    if($line=~/^#/) {
        if($line=~/^##/) {
            say $O $line;
            next;
        }
        say $O q|##INFO=<ID=SUPP,Number=1,Type=String,Description="Number of samples supporting the variant">|;
        say $O qq+##CommandLine="$ARGVs"+;
        @header = split /\t/, $line;
        say $O join("\t", @header[0..8], $samplename);
        next;
    }
    my @F = split /\t/, $line;
    my ($chr, $pos, $svid, $ref, $alts) = @F[0,1,2,3,4];
    #next unless $pos == 4474552;
    my ($max_alle, $new_gt, $supp) = &cal_alle_freq(\@F);
    #say $O join "\t", $F[0], $F[1], $max_alle if defined $max_alle;
    say $O &rebuild_line(\@F, $max_alle, $new_gt, $supp) if defined $max_alle;
}

exit;

sub rebuild_line {
    my ($F, $alle, $new_gt, $supp) = @_;
    my @newline = $F->@[0..8];
    my $alts = $$F[4];
    my @alts = split /,/, $alts;
    my $newalt = $alts[$alle-1];
    $newline[4] = $newalt;
    if($newline[7] eq '.') {
        $newline[7] = "SUPP=$supp";
    } else {
        $newline[7] .= ";SUPP=$supp";
    }
    $newline[8] = 'GT';
    $newline[9] = $new_gt;
    return join "\t", @newline;
}

sub cal_max_alle {
    my ($alle_freq, $hetero_freq) = @_;
    my @alles = sort{$$alle_freq{$b} <=> $$alle_freq{$a}} keys %{$alle_freq};
    my $max_alle = $alles[0] // return undef;
    my $max_alle_freq = $$alle_freq{$max_alle};
    if($max_alle_freq < $min_supporting) {
        return undef;
    }
    if(scalar(@alles) >= 2) {
        my $max_alle2 = $alles[1];
        my $max2_alle_freq = $$alle_freq{$max_alle2};
        if($max2_alle_freq == $max_alle_freq) {
            $$hetero_freq{$max_alle} //= 0;
            $$hetero_freq{$max_alle2} //= 0;            
            if($$hetero_freq{$max_alle} < $$hetero_freq{$max_alle2}) {
                # 频率相同，输出纯合多的
                return $max_alle;
            } elsif($$hetero_freq{$max_alle} > $$hetero_freq{$max_alle2}) {
                return $max_alle2;
            } else {
                # ??? select first
                return $max_alle;
            }
        }
    }
    return $max_alle;
}

sub cal_alle_freq {
    my ($F) = @_;
    my %alle_freq;
    my %heteros;
    foreach my $i (9..$#{$F}) {
        my $gt = $F->[$i];
        if($gt=~/^\./) {
            next;
        }
        $gt=~m#(\d+)/(\d+)# or die;
        my ($gt1, $gt2) = ($1, $2);
        if($gt1!=0 and $gt2!=0 and $gt1!=$gt2) { # 1/2
            #die "Error: $gt";
            $alle_freq{$gt1} += 1;
            $alle_freq{$gt2} += 1;
            $heteros{$gt1}++;
            $heteros{$gt2}++;
        } elsif($gt1!=$gt2) { # 0/1 or 1/0 or 1/2 or 0/2
            foreach my $gt ($gt1, $gt2) {
                next if $gt==0;
                $alle_freq{$gt}++;
                $heteros{$gt}++;
            }
        } elsif($gt1==$gt2 and $gt1!=0) { # 1/1 or 2/2
            $alle_freq{$gt1}++;
        }
    }
    my $max_alle = &cal_max_alle(\%alle_freq, \%heteros);
    if(! defined $max_alle) {
        return(undef);
    }
    my $supp = $alle_freq{$max_alle};
    my $hetero_alle = $heteros{$max_alle} // 0;
    my $hetero_rate = $hetero_alle / $supp;
    my $gt;
    if($hetero_rate > 0.5) {
        $gt = '0/1';
    } else {
        $gt = '1/1';
    }
    return($max_alle, $gt, $supp);
}



