#!/usr/bin/perl

=head1 Revision

    Last edited 2008-12-24

=cut

=head1 Author

    Copyright 2008 Pedro Silva <psilva@dzlab.pmb.berkeley.edu/>

=cut

=head1 Copyright

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

=head1 Synopsis

=cut

use strict;
use warnings;
use diagnostics;
use Getopt::Long;
use Data::Dumper;
use Carp;

# Globals, passed as command line options
my $gff_file_1 = '';
my $gff_file_2 = '';
my $operation = 'sub';
my $statistic = 'Fisher::right';
my $inverse_log = -1;
my $reverse = 0;
my $threshold = 0;
my $output = '-';
my $verbose = 0;
my $quiet = 0;
my $usage = 0;

# Initial check of command line parameters
if (@ARGV < 2) {
    usage();
}
my @argv = @ARGV;

# Grabs and parses command line options
my $result = GetOptions ( 
    'gff-a|a=s' => \$gff_file_1,
    'gff-b|b=s' => \$gff_file_2,
    'operation|op|p:s' => \$operation,
    'statistic|stat|s=s' => \$statistic,
    "inverse-log|ilog|i:i" => \$inverse_log,
    'reverse-score|rev|r' => \$reverse,
    'output|o:s' => \$output,
    'threshold|t=f' => \$threshold,
    'verbose|v' => sub {enable diagnostics;use warnings;},
    'quiet|q' => sub {disable diagnostics;no warnings;},
    'usage|help|h' => \&usage
);

# use the appropriate statistic measure based on user input
eval "use Text::NSP::Measures::2D::$statistic";

# redirects STDOUT to file if specified by user
if (!($output eq '-')) {
    open(STDOUT, '>', "$output") or croak ("Can't redirect STDOUT to file: $output");
}

# prints out header fields that contain gff v3 header, generating program, time, and field names
gff_print_header ($0, @argv);

# opens gff files
open (my $GFFA, '<', $gff_file_1) or croak ("Can't read file: $gff_file_1");
open (my $GFFB, '<', $gff_file_2) or croak ("Can't read file: $gff_file_2");

# @window_buffers hold contiguous gff records, in the hash form produced by gff_read
#
# These buffers get filled while the current gff line being processed is contiguous 
# to the last one and get flushed (ie. processing resumes and the buffer is emptied) 
# when the current read is not contiguous to the last one
#
# The algorithm for determining contiguity is not very sophisticated: two windows are 
# adjacent or overlapping if the current line's starting coordinate is larger than the
# last processed line's start coordinate but smaller than, or equal to, the last 
# processed line's end coordinate
my (@window_buffer_a, @window_buffer_b) = ();

# processing stops when either we run out of 'a' file lines
# OR we run out of 'b' file lines (see below)
PROCESSING:
while (my $line_a = <$GFFA>) {

    # get a line from each file to be compared
    # ignore comments or blank lines and clean it up
    next if ($line_a =~ m/^#.*$|^\s*$/);
    my $line_b = <$GFFB>;
    last unless defined $line_b; # stop if we run out of 'b' lines
    while ($line_b =~ m/^#.*$|^\s*$/) {
        $line_b = <$GFFB>;
    }
    chomp $line_a;
    chomp $line_b;
    $line_a =~ s/\r//g;
    $line_b =~ s/\r//g;

    # read each line into a hash
    # see gff_read() sub definition for hash keys
    my %rec_a = %{&gff_read ($line_a)};
    my %rec_b = %{&gff_read ($line_b)};

    # is threshold is given, this is a preliminary statistic to filter out
    # records less than it. if no threshold is given, this is the final calculation
    # gff_calculate_statistic will call the Text::NSP module
    # return value is -200 if a record doesn't have coverage (ie. attribute field eq '.')
    my $ngram = gff_calculate_statistic (\%rec_a, \%rec_b);
    my $score = 0;
    #if ($ngram == -200)

    # if threshold is defined
    if ($threshold) {
        # filter out records with statistic measures below it
        next PROCESSING if ($ngram > $threshold);

        # if our buffers are empty OR
        # if we think the current window is contiguous to the ones already stored
        # push the current windows into the buffers
        # and skip processing for now
        if(@window_buffer_a == 0) {
            push @window_buffer_a, $line_a;
            push @window_buffer_b, $line_b;
            next PROCESSING;
        }
        elsif ($rec_a{'start'} > (split "\t", $window_buffer_a[-1])[3] and
               $rec_a{'start'} <= (split "\t", $window_buffer_a[-1])[4] + 1) {
            push @window_buffer_a, $line_a;
            push @window_buffer_b, $line_b;
            next PROCESSING;
        }
        else {
            # if the current window is NOT contiguous with the last buffer entry
            # we flush the buffer, start filling it up again, and overwrite the current
            # window with the concatenated window
            my $tmp_window_a_ref = gff_concatenate (\@window_buffer_a);
            my $tmp_window_b_ref = gff_concatenate (\@window_buffer_b);
            my $tmp_ngram = gff_calculate_statistic ($tmp_window_a_ref, $tmp_window_b_ref);

            # deletes buffer contents, saves current windows to the buffer
            # and overwrites current windows and ngram score for printing
            (@window_buffer_a, @window_buffer_b) = ();
            push @window_buffer_a, $line_a;
            push @window_buffer_b, $line_b;

            # filter out records with statistic measures below it
            # this should never happen because of the preliminary filtering above
            # I'm leaving it for now for debugging purposes
            next PROCESSING if ($tmp_ngram > $threshold);

            %rec_a = %{$tmp_window_a_ref};
            %rec_b = %{$tmp_window_b_ref};
            $ngram = $tmp_ngram;
        }
    }

    # calculates the appropriate result on the scores of both windows
    if ($operation eq 'sub') {
        $score = $rec_a{'score'} - $rec_b{'score'};
    } elsif ($operation eq 'div' && 
                 $rec_b{'score'} != 0) {
        $score = $rec_a{'score'} / $rec_b{'score'};
    }

    # calculates the inverse log (with base specified by user) of the ngram
    if ($ngram > 0 and $ngram != 1 and $inverse_log != -1) {
        if ($inverse_log == 0) {
            $ngram = 1 / log($ngram)
        } else {
            $ngram = 1 / (log($ngram) / log($inverse_log));
        }
    }

    # puts the score in the 'attribute' field and the statistic in the 'score' field
    if ($reverse) {
        my $tmp = $score;
        $score = $ngram;
        $ngram = $tmp;
        $statistic = $operation;
    }

    ### NOTE: this is temporary: it naively parses the input file names to try to
    # put something meaningful in the 'feature' field
    my $tmp = "a/$operation/b";

    # prints out the current window (or concatenated windows) as a gff record
    print join("\t",
               $rec_a{'seqname'},
               "cmp",
               $tmp,
               $rec_a{'start'},
               $rec_a{'end'},
               sprintf("%.3f", $score),
               ".",
               ".",
               sprintf("$statistic=%.5f", $ngram)), "\n";
}

close ($GFFA);
close ($GFFB);

exit 0;

=head1 Subroutines

=head2 gff_calculate_statistic()

    Takes two references to hashes output by gff_read().

    Returns an $ngram value determined by the choice of statistical measure

    Depends on the Text::NSP module by Ted Pedersen <http://search.cpan.org/dist/Text-NSP/>

=cut


sub gff_calculate_statistic {
    # unpack arguments
    my ($rec_a_ref, $rec_b_ref) = @_;
    my %rec_a = %{$rec_a_ref};
    my %rec_b = %{$rec_b_ref};

    # naively tries to parse the 'feature' field into the line/organism
    # and the context. assumes it is in the form $LINE[;_]$CONTEXT
    my ($line_a, $context_a) = split(/;|_/, $rec_a{'feature'});
    my ($line_b, $context_b) = split(/;|_/, $rec_b{'feature'});

    # basic sanity test for matching coordinates, chromosome and context
    if ($rec_a{'start'} != $rec_b{'start'} or
            $rec_a{'end'} != $rec_b{'end'} or
                $rec_a{'seqname'} ne $rec_b{'seqname'} or
                    $context_a ne $context_b) {
        Croak ("Can't match windows in input files. Make sure these are sorted by starting coordinate and that each input file contains only one chromosome and one context. This will be modified in the future to allow multiple chromosomes and contexts per input file.");
    }

    # checks for no coverage in the windows (ie. 'attribute' field eq ".")
    my $ngram = 0;
    if ( ($rec_a{'attribute'} =~ m/\./) or
             ($rec_b{'attribute'} =~ m/\./) ) {
        $ngram = -200;
    } else {
        # contigency table:
        #
        #  |line a|line b|
        # -|------|------|----
        # c| n11  | n12  | n1p
        # -|------|------|----
        # t| n21  | n22  |
        #  |------|------|----
        #  | np1  |      | npp 
        my ($n11, $n21) = split(/;/, $rec_a{'attribute'});
        my ($n12, $n22) = split(/;/, $rec_b{'attribute'});
        ($n11) = $n11 =~ m/(\d+)/;
        ($n12) = $n12 =~ m/(\d+)/;
        ($n21) = $n21 =~ m/(\d+)/;
        ($n22) = $n22 =~ m/(\d+)/;

        if ($n11 + $n12 + $n21 + $n22) {
            $ngram = calculateStatistic
            (
                n11 => $n11,
                n1p => ($n11 + $n12),
                np1 => ($n11 + $n21),
                npp => ($n11 + $n12 + $n21 + $n22)
            );
        }

        if ( my $error_code = getErrorCode() ) {
            print STDERR $error_code, ": ", getErrorMessage(), "\n";
        }
    }
    return $ngram;
}


=head2 gff_concatenate()

    Takes a reference to an array of contiguous windows in the form of gff_read() hashes

    Returns a similarly formatted hash with all contiguous windows merged and scores recalculated

=cut
sub gff_concatenate {
    # unpack argument
    my $contig_windows_ref = shift;
    my @contig_windows = @{$contig_windows_ref};

    my ($seqname, $source, $feature, $start, $end, $score, $strand, $frame, $attribute);
    my ($c_count, $t_count) = (0, 0);
    # loops through every contiguous window
    for my $x (0..$#contig_windows) {

        my %rec = %{gff_read ($contig_windows[$x])};

        if ($x > 0) {
            # basic sanity test on whether current line is consistent with previous one
            if ($seqname ne $rec{'seqname'}
                    or $source ne $rec{'source'}
                        or $feature ne $rec{'feature'}
                            or $strand ne $rec{'strand'}
                                or $frame ne $rec{'frame'}
                                    or $end + 1 < $rec{'start'}) {
                croak ("Given records to be merged are inconsistent")
            }
        }
        # if ok, save current line
        else {
            $seqname = $rec{'seqname'};
            $source = $rec{'source'};
            $feature = $rec{'feature'};
            $strand = $rec{'strand'};
            $frame = $rec{'frame'};
        }

        # get the lowest coordinate, naively assuming input windows are sorted
        # well, it is checked above, so we should never get an unsorted array
        $start = $rec{'start'} if ($x == 0);
        $end = $rec{'end'};
        $score += $rec{'score'};

        # extract c and t counts from 'attribute' field
        # and update the total counts
        if ($rec{'attribute'} ne '.') {
            my ($tmp1, $tmp2) = split(/;/, $rec{'attribute'});
            ($tmp1) = $tmp1 =~ m/(\d+)/;
            ($tmp2) = $tmp2 =~ m/(\d+)/;
            $c_count += $tmp1;
            $t_count += $tmp2;
        }
    }

    if ($c_count + $t_count == 0) {
        $score = 0;
    } else {
        $score = $c_count/($c_count+$t_count);
    }

    # format 'score' to only output 3 decimal places
    $score = sprintf ("%.3f", $score);

    # format 'attribute' field for consistency here
    $attribute = "c=$c_count;t=$t_count";

    # declare and initialize a non-anonymous hash
    # (as opposed to just returning an anonymous one)
    # because strictures won't let me use scalar interpolation
    # in the 'attribute' field when anonymously returning
    my %concatenated_hash = (
        'seqname' => $seqname,
        'source' => $source,
        'feature' => $feature,
        'start' => $start,
        'end' => $end,
        'score' => $score,
        'strand' => $strand,
        'frame' => $frame,
        'attribute' => $attribute
    );
    return \%concatenated_hash;
}


=head2 gff_read()

    Takes in a single GFF line string

    Returns a reference to an anonymous hashw with keys equal to the GFF v3 spec

=cut
sub gff_read {
    my ($seqname, $source, $feature, $start, $end, $score, $strand, $frame, $attribute) = split(/\t/, shift);
    my %rec = (
        'seqname'=>$seqname,
        'source'=>$source,
        'feature'=>$feature,
        'start'=>$start,
        'end'=>$end,
        'score'=>$score,
        'strand'=>$strand,
        'frame'=>$frame,
        'attribute'=>$attribute
    );
    return \%rec;
}

=head2 gff_print_header()

    Takes the program call (including the name of the program and its arguments) as input

    Prints out a commented line with header fields

=cut
sub gff_print_header {
    my @call_and_args = @_;
    print "##gff-version 3\n";
    print join(' ',
               '#',
               @call_and_args,
               "\n");
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime (time);
    printf "# %4d-%02d-%02d %02d:%02d:%02d\n", $year+1900, $mon+1, $mday, $hour, $min, $sec;
    print join("\t",
               '# SEQNAME',
               'SOURCE',
               'FEATURE',
               'START',
               'END',
               'SCORE',
               'STRAND',
               'FRAME',
               'ATTRIBUTES',
           ), "\n";
    return;
}


=head2 usage()

    Prints out usage information

=cut
sub usage {
    print STDERR <<'EOF';
countMethylation.pl <REQUIRED> [OPTIONS]
    <--gff-a          -a>    First GFF alignment input file
    <--gff-b          -b>    Second GFF alignment input file
    [--operation      -p]    Arithmetic operation on scores from a and b ('sub' or 'div')
    [--statistic      -s]    Type of indendence/significance statistic to use
                      Statistics options: (run 'pellet's Text::NSP' for more information)
                      CHI::phi                 Phi coefficient measure 
		      CHI::tscore              T-score measure of association 
		      CHI::x2                  Pearson's chi squared measure of association 
		      Dice::dice               Dice coefficient 
		      Dice::jaccard            Jaccard coefficient
		      Fisher::left             Left sided Fisher's exact test
		      Fisher::right            Right sided Fisher's exact test
		      Fisher::twotailed        Two-sided Fisher's exact test
		      MI::ll                   Loglikelihood measure of association 
		      MI::pmi                  Pointwise Mutual Information
		      MI::ps                   Poisson-Stirling measure of association
		      MI::tmi                  True Mutual Information
    [--inverse-log    -i]    Step interval of sliding window in BS
    [--reverse-score  -r]    Output scores in attributes field and statistics in scores field 
    [--threshold      -t]    Minimum threshold for filtering out windows
    [--output         -o]    Filename to write results to (default is STDOUT)
    [--verbose        -v]    Output Pall's diagnostic and warning messages
    [--quiet          -q]    Supress Pail's diagnostic and warning messages
    [--usage          -h]    Print this information
EOF
    exit 0;
}

#  LocalWords:  gff GFF indendence Jaccard Loglikelihood Pointwise Filename
#  LocalWords:  STDOUT Supress

